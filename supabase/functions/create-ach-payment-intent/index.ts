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

// Fee constants — must match client-side ACHPurchaseFeeCalculator exactly
const PLATFORM_FEE_RATE = 0.05
const ACH_FEE_RATE = 0.008
const ACH_FEE_CAP_CENTS = 500

function calculateFees(baseCents: number) {
  if (baseCents <= 0) {
    return {
      base_cents: 0,
      platform_fee_cents: 0,
      ach_fee_cents: 0,
      total_cents: 0,
    }
  }

  const platform_fee_cents = Math.ceil(baseCents * PLATFORM_FEE_RATE)
  const subtotal = baseCents + platform_fee_cents
  const ach_fee_cents = Math.min(Math.ceil(subtotal * ACH_FEE_RATE), ACH_FEE_CAP_CENTS)
  const total_cents = subtotal + ach_fee_cents

  return {
    base_cents: baseCents,
    platform_fee_cents,
    ach_fee_cents,
    total_cents,
  }
}

interface ACHPaymentRequest {
  event_id: string
  quantity: number
  payment_method_id: string
  amount_cents: number
  metadata?: Record<string, unknown>
}

const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

serve(async (req) => {
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

    const supabaseClient = createClient(supabaseUrl, supabaseServiceKey, {
      global: { headers: { Authorization: authHeader } }
    })

    const { data: { user }, error: authError } = await supabaseClient.auth.getUser(
      authHeader.replace('Bearer ', '')
    )

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid authentication' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const body: ACHPaymentRequest = await req.json()
    const { event_id, quantity = 1, payment_method_id, amount_cents, metadata } = body

    if (!event_id || !payment_method_id) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: event_id, payment_method_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (quantity < 1 || quantity > 10) {
      return new Response(
        JSON.stringify({ error: 'Quantity must be between 1 and 10' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify event exists and is active
    const { data: event, error: eventError } = await supabaseAdmin
      .from('events')
      .select('id, title, price_in_cents, status, nft_enabled')
      .eq('id', event_id)
      .single()

    if (eventError || !event) {
      return new Response(
        JSON.stringify({ error: 'Event not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (event.status !== 'active') {
      return new Response(
        JSON.stringify({ error: 'Event is not available for purchase' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!event.price_in_cents || event.price_in_cents <= 0) {
      return new Response(
        JSON.stringify({ error: 'Free events do not require payment' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Calculate fees and validate client amount
    const baseCents = event.price_in_cents * quantity
    const fees = calculateFees(baseCents)

    if (amount_cents !== fees.total_cents) {
      console.log(`ACH price mismatch: expected ${fees.total_cents}, got ${amount_cents}`)
      return new Response(
        JSON.stringify({ error: 'Price mismatch. Please refresh and try again.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify bank account belongs to user
    const { data: bankAccount } = await supabaseAdmin
      .from('linked_bank_accounts')
      .select('id, stripe_payment_method_id')
      .eq('user_id', user.id)
      .eq('stripe_payment_method_id', payment_method_id)
      .eq('status', 'active')
      .maybeSingle()

    if (!bankAccount) {
      return new Response(
        JSON.stringify({ error: 'Bank account not found or not active' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get or create Stripe customer
    const { data: profile } = await supabaseAdmin
      .from('profiles')
      .select('stripe_customer_id, email, display_name')
      .eq('id', user.id)
      .single()

    let customerId = profile?.stripe_customer_id

    if (!customerId) {
      const customer = await stripe.customers.create({
        email: user.email,
        name: profile?.display_name || undefined,
        metadata: { supabase_user_id: user.id },
      })
      customerId = customer.id
      await supabaseAdmin
        .from('profiles')
        .update({ stripe_customer_id: customerId })
        .eq('id', user.id)
    }

    // Build PaymentIntent metadata
    const piMetadata: Record<string, string> = {
      event_id,
      user_id: user.id,
      type: 'ach_purchase',
      event_title: event.title,
      quantity: String(quantity),
      base_amount_cents: String(fees.base_cents),
      platform_fee_cents: String(fees.platform_fee_cents),
      ach_fee_cents: String(fees.ach_fee_cents),
    }
    if (metadata) {
      for (const [k, v] of Object.entries(metadata)) {
        piMetadata[k] = String(v)
      }
    }

    // Create and confirm ACH PaymentIntent
    const idempotencyKey = `ach_${user.id}_${event_id}_${Date.now()}`
    const paymentIntent = await stripe.paymentIntents.create({
      amount: fees.total_cents,
      currency: 'usd',
      customer: customerId,
      payment_method: payment_method_id,
      payment_method_types: ['us_bank_account'],
      confirm: true,
      metadata: piMetadata,
    }, {
      idempotencyKey,
    })

    console.log(`ACH PaymentIntent created: ${paymentIntent.id}, status: ${paymentIntent.status}`)

    // Create payment record (status: processing — ACH takes days to settle)
    const { data: payment, error: paymentError } = await supabaseAdmin
      .from('payments')
      .insert({
        user_id: user.id,
        event_id,
        amount_cents: fees.total_cents,
        currency: 'usd',
        status: 'processing',
        type: 'ach_purchase',
        stripe_payment_intent_id: paymentIntent.id,
        platform_fee_cents: fees.platform_fee_cents + fees.ach_fee_cents,
        metadata: {
          event_title: event.title,
          fee_breakdown: fees,
          payment_method: 'ach',
          ...metadata,
        },
      })
      .select()
      .single()

    if (paymentError) {
      console.error('Failed to create payment record:', paymentError)
    }

    // Create tickets immediately — user gets ticket now, ACH settles later
    const { data: ownerProfile } = await supabaseAdmin
      .from('profiles')
      .select('email, display_name')
      .eq('id', user.id)
      .single()

    const { data: authData } = await supabaseAdmin.auth.admin.getUserById(user.id)
    const ownerEmail = ownerProfile?.email || authData?.user?.email || null
    const ownerName = ownerProfile?.display_name || null

    const ticketIds: string[] = []
    for (let i = 0; i < quantity; i++) {
      const timestamp = Date.now().toString().substring(7)
      const random = Math.floor(Math.random() * 9999).toString().padStart(4, '0')
      const ticketNumber = `TKT-${timestamp}-${random}`

      const { data: ticket, error: ticketError } = await supabaseAdmin
        .from('tickets')
        .insert({
          event_id,
          ticket_number: ticketNumber,
          owner_email: ownerEmail,
          owner_name: ownerName,
          price_paid_cents: event.price_in_cents,
          currency: 'USD',
          status: 'valid',
          sold_by: user.id,
        })
        .select()
        .single()

      if (ticketError) {
        console.error(`Failed to create ticket ${i + 1}/${quantity}:`, ticketError)
        continue
      }

      ticketIds.push(ticket.id)
      console.log(`ACH ticket ${i + 1}/${quantity} created: ${ticketNumber}`)
    }

    // Link first ticket to payment
    if (ticketIds.length > 0 && payment) {
      await supabaseAdmin
        .from('payments')
        .update({ ticket_id: ticketIds[0] })
        .eq('id', payment.id)
    }

    // Enqueue NFT minting if enabled (fire-and-forget)
    if (ticketIds.length > 0 && event.nft_enabled) {
      try {
        const { data: buyerWallet } = await supabaseAdmin
          .from('user_wallets')
          .select('cardano_address')
          .eq('user_id', user.id)
          .maybeSingle()

        for (const ticketId of ticketIds) {
          await supabaseAdmin.from('nft_mint_queue').insert({
            ticket_id: ticketId,
            event_id,
            buyer_address: buyerWallet?.cardano_address || 'no_wallet',
            action: 'mint',
            status: buyerWallet?.cardano_address ? 'queued' : 'skipped',
          })
        }

        if (buyerWallet?.cardano_address) {
          // Fire-and-forget mint invocation
          fetch(`${supabaseUrl}/functions/v1/mint-ticket-nft`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${supabaseServiceKey}`,
            },
            body: JSON.stringify({}),
          }).catch(err => console.error('mint-ticket-nft invoke failed:', err.message))
        }
      } catch (err) {
        console.error('NFT enqueue failed (non-blocking):', err.message)
      }
    }

    console.log(`ACH purchase completed: ${ticketIds.length} tickets for user ${user.id}, PI: ${paymentIntent.id}`)

    return new Response(
      JSON.stringify({
        payment_id: payment?.id,
        payment_intent_id: paymentIntent.id,
        ticket_ids: ticketIds,
        tickets_created: ticketIds.length,
        fee_breakdown: fees,
        status: paymentIntent.status,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error creating ACH payment:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
