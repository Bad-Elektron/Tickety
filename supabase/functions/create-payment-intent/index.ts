import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import Stripe from 'https://esm.sh/stripe@14.21.0'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
})

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface PaymentIntentRequest {
  event_id: string
  amount_cents: number
  currency: string
  type: 'primary_purchase' | 'resale_purchase' | 'vendor_pos' | 'favor_ticket_purchase'
  user_id: string
  ticket_id?: string
  quantity?: number
  metadata?: Record<string, unknown>
}

// Fee constants — must match client-side ServiceFeeCalculator exactly
const PLATFORM_FEE_RATE = 0.05
const STRIPE_FEE_RATE = 0.029
const STRIPE_FEE_FIXED_CENTS = 30
const MINT_FEE_CENTS = 0

function calculateFees(baseCents: number) {
  if (baseCents <= 0) {
    return {
      base_cents: 0,
      platform_fee_cents: 0,
      mint_fee_cents: 0,
      stripe_fee_cents: 0,
      service_fee_cents: 0,
      total_cents: 0,
    }
  }

  const platform_fee_cents = Math.ceil(baseCents * PLATFORM_FEE_RATE)
  const mint_fee_cents = MINT_FEE_CENTS
  const subtotal = baseCents + platform_fee_cents + mint_fee_cents
  const total_cents = Math.ceil((subtotal + STRIPE_FEE_FIXED_CENTS) / (1 - STRIPE_FEE_RATE))
  const stripe_fee_cents = total_cents - subtotal
  const service_fee_cents = platform_fee_cents + stripe_fee_cents + mint_fee_cents

  return {
    base_cents: baseCents,
    platform_fee_cents,
    mint_fee_cents,
    stripe_fee_cents,
    service_fee_cents,
    total_cents,
  }
}

// Admin client for operations that need to bypass RLS (e.g. inserting payments)
const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Verify authentication
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Create Supabase client with user's JWT (for auth verification and RLS-respecting reads)
    const supabaseClient = createClient(supabaseUrl, supabaseServiceKey, {
      global: { headers: { Authorization: authHeader } }
    })

    // Verify the user is authenticated
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser(
      authHeader.replace('Bearer ', '')
    )

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid authentication' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const body: PaymentIntentRequest = await req.json()
    const { event_id, amount_cents, currency = 'usd', type, quantity = 1, metadata } = body

    // Validate required fields
    if (!event_id || !amount_cents || !type) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: event_id, amount_cents, type' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Allow test event IDs in development (skip database lookup)
    const isTestEvent = event_id.startsWith('test-')
    let event: { id: string; title: string; price_in_cents?: number; organizer_id?: string } | null = null

    if (isTestEvent) {
      // Mock event for testing
      console.log('Using test event mode for:', event_id)
      event = {
        id: event_id,
        title: 'Test Event',
        price_in_cents: amount_cents, // Accept any amount for test events
      }
    } else {
      // Verify event exists and get price info (prevent tampering)
      const { data: eventData, error: eventError } = await supabaseClient
        .from('events')
        .select('id, title, price_in_cents, organizer_id')
        .eq('id', event_id)
        .single()

      console.log('Event lookup result:', { eventData, eventError })

      if (eventError || !eventData) {
        console.log('Event not found:', event_id, eventError)
        return new Response(
          JSON.stringify({ error: 'Event not found' }),
          { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      event = eventData

      // For primary purchases, validate total = fees(quantity × unit price)
      if (type === 'primary_purchase' && event.price_in_cents) {
        const baseCents = event.price_in_cents * quantity
        const fees = calculateFees(baseCents)
        if (amount_cents !== fees.total_cents) {
          console.log(`Price mismatch: expected ${fees.total_cents} (base: ${baseCents}, fee: ${fees.service_fee_cents}), got ${amount_cents}`)
          return new Response(
            JSON.stringify({ error: 'Price mismatch. Please refresh and try again.' }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }
      }

      // For favor ticket purchases, validate total against offer price + fees
      if (type === 'favor_ticket_purchase' && metadata?.offer_id) {
        const { data: offer } = await supabaseAdmin
          .from('ticket_offers')
          .select('price_cents')
          .eq('id', metadata.offer_id)
          .single()

        if (offer && offer.price_cents > 0) {
          const fees = calculateFees(offer.price_cents)
          if (amount_cents !== fees.total_cents) {
            console.log(`Favor price mismatch: expected ${fees.total_cents} (base: ${offer.price_cents}), got ${amount_cents}`)
            return new Response(
              JSON.stringify({ error: 'Price mismatch. Please refresh and try again.' }),
              { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
          }
        }
      }
    }

    // Get or create Stripe customer (use admin client to bypass RLS)
    const { data: profile, error: profileError } = await supabaseAdmin
      .from('profiles')
      .select('stripe_customer_id, email, display_name')
      .eq('id', user.id)
      .single()

    console.log('Profile lookup:', {
      userId: user.id,
      stripeCustomerId: profile?.stripe_customer_id || 'NULL',
      profileError: profileError?.message || 'none'
    })

    let customerId = profile?.stripe_customer_id

    if (!customerId) {
      // Create new Stripe customer
      console.log('No existing Stripe customer, creating new one')
      const customer = await stripe.customers.create({
        email: user.email,
        name: profile?.display_name || undefined,
        metadata: {
          supabase_user_id: user.id,
        },
      })
      customerId = customer.id
      console.log('Created new Stripe customer:', customerId)

      // Save customer ID to profile
      await supabaseAdmin
        .from('profiles')
        .update({ stripe_customer_id: customerId })
        .eq('id', user.id)
    } else {
      console.log('Using existing Stripe customer:', customerId)
    }

    // Check how many saved payment methods the customer has
    const savedMethods = await stripe.paymentMethods.list({
      customer: customerId,
      type: 'card',
    })
    console.log(`Customer ${customerId} has ${savedMethods.data.length} saved cards`)

    // Create ephemeral key for the customer
    const ephemeralKey = await stripe.ephemeralKeys.create(
      { customer: customerId },
      { apiVersion: '2023-10-16' }
    )
    console.log('Ephemeral key created, secret length:', ephemeralKey.secret?.length || 0)

    // Compute fee breakdown for metadata
    let fees: ReturnType<typeof calculateFees> | null = null
    if (type === 'primary_purchase' && event.price_in_cents) {
      fees = calculateFees(event.price_in_cents * quantity)
    } else if (type === 'favor_ticket_purchase' && metadata?.offer_id) {
      const { data: offerForFees } = await supabaseAdmin
        .from('ticket_offers')
        .select('price_cents')
        .eq('id', metadata.offer_id)
        .single()
      if (offerForFees && offerForFees.price_cents > 0) {
        fees = calculateFees(offerForFees.price_cents)
      }
    }

    // Generate idempotency key
    const idempotencyKey = `pi_${user.id}_${event_id}_${Date.now()}`

    // Build PaymentIntent metadata (Stripe requires string values)
    const piMetadata: Record<string, string> = {
      event_id,
      user_id: user.id,
      type,
      event_title: event.title,
      quantity: String(quantity),
    }
    if (fees) {
      piMetadata.base_amount_cents = String(fees.base_cents)
      piMetadata.service_fee_cents = String(fees.service_fee_cents)
      piMetadata.platform_fee_cents = String(fees.platform_fee_cents)
      piMetadata.stripe_fee_cents = String(fees.stripe_fee_cents)
    }
    // Spread additional metadata (e.g. offer_id)
    if (metadata) {
      for (const [k, v] of Object.entries(metadata)) {
        piMetadata[k] = String(v)
      }
    }

    // Create PaymentIntent
    const paymentIntent = await stripe.paymentIntents.create({
      amount: amount_cents,
      currency,
      customer: customerId,
      automatic_payment_methods: { enabled: true },
      // Enable saving payment methods for future use
      setup_future_usage: 'off_session',
      metadata: piMetadata,
    }, {
      idempotencyKey,
    })

    // Create pending payment record (use admin client to bypass RLS)
    const { data: payment, error: paymentError } = await supabaseAdmin
      .from('payments')
      .insert({
        user_id: user.id,
        event_id,
        amount_cents,
        currency,
        status: 'pending',
        type,
        stripe_payment_intent_id: paymentIntent.id,
        platform_fee_cents: fees ? fees.service_fee_cents : 0,
        metadata: {
          event_title: event.title,
          ...(fees && { fee_breakdown: fees }),
          ...metadata,
        },
      })
      .select()
      .single()

    if (paymentError) {
      console.error('Failed to create payment record:', paymentError)
      // Continue anyway - webhook will handle the rest
    }

    return new Response(
      JSON.stringify({
        payment_intent_id: paymentIntent.id,
        client_secret: paymentIntent.client_secret,
        customer_id: customerId,
        ephemeral_key: ephemeralKey.secret,
        payment_id: payment?.id,
        ...(fees && { fee_breakdown: fees }),
        _debug: {
          profile_customer_id: profile?.stripe_customer_id || 'NULL',
          profile_error: profileError?.message || 'none',
          used_customer: customerId,
          created_new: !profile?.stripe_customer_id,
          saved_cards: savedMethods.data.length,
        },
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )

  } catch (error) {
    console.error('Error creating payment intent:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
