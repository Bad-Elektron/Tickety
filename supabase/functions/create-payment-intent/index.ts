import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import Stripe from 'https://esm.sh/stripe@13.10.0?target=deno'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
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
  type: 'primary_purchase' | 'resale_purchase' | 'vendor_pos'
  user_id: string
  ticket_id?: string
  quantity?: number
  metadata?: Record<string, unknown>
}

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

    // Create Supabase client with user's JWT
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

      // For primary purchases, validate total = quantity × unit price
      if (type === 'primary_purchase' && event.price_in_cents) {
        const expectedTotal = event.price_in_cents * quantity
        if (amount_cents !== expectedTotal) {
          console.log(`Price mismatch: expected ${expectedTotal} (${quantity} × ${event.price_in_cents}), got ${amount_cents}`)
          return new Response(
            JSON.stringify({ error: 'Price mismatch. Please refresh and try again.' }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }
      }
    }

    // Get or create Stripe customer
    const { data: profile } = await supabaseClient
      .from('profiles')
      .select('stripe_customer_id, email, full_name')
      .eq('id', user.id)
      .single()

    let customerId = profile?.stripe_customer_id

    if (!customerId) {
      // Create new Stripe customer
      const customer = await stripe.customers.create({
        email: user.email,
        name: profile?.full_name || undefined,
        metadata: {
          supabase_user_id: user.id,
        },
      })
      customerId = customer.id

      // Save customer ID to profile
      await supabaseClient
        .from('profiles')
        .update({ stripe_customer_id: customerId })
        .eq('id', user.id)
    }

    // Create ephemeral key for the customer
    const ephemeralKey = await stripe.ephemeralKeys.create(
      { customer: customerId },
      { apiVersion: '2023-10-16' }
    )

    // Generate idempotency key
    const idempotencyKey = `pi_${user.id}_${event_id}_${Date.now()}`

    // Create PaymentIntent
    const paymentIntent = await stripe.paymentIntents.create({
      amount: amount_cents,
      currency,
      customer: customerId,
      automatic_payment_methods: { enabled: true },
      metadata: {
        event_id,
        user_id: user.id,
        type,
        event_title: event.title,
        quantity: String(quantity),
        ...metadata,
      },
    }, {
      idempotencyKey,
    })

    // Create pending payment record
    const { data: payment, error: paymentError } = await supabaseClient
      .from('payments')
      .insert({
        user_id: user.id,
        event_id,
        amount_cents,
        currency,
        status: 'pending',
        type,
        stripe_payment_intent_id: paymentIntent.id,
        metadata: {
          event_title: event.title,
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
