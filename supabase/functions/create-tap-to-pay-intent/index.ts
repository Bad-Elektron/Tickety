import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0'
import Stripe from 'https://esm.sh/stripe@14.21.0'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
})

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      },
    })
  }

  try {
    // Get auth token
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'No authorization header' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Create Supabase client with user's auth
    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      global: { headers: { Authorization: authHeader } },
    })

    // Get current user
    const { data: { user }, error: userError } = await supabase.auth.getUser(
      authHeader.replace('Bearer ', '')
    )
    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Parse request body
    const { pending_payment_id, event_id, ticket_type_id, amount_cents } = await req.json()

    if (!pending_payment_id || !event_id || !amount_cents) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Verify the pending payment exists and belongs to this user
    const { data: pendingPayment, error: paymentError } = await supabase
      .from('pending_payments')
      .select('*')
      .eq('id', pending_payment_id)
      .eq('customer_id', user.id)
      .single()

    if (paymentError || !pendingPayment) {
      return new Response(JSON.stringify({ error: 'Pending payment not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Get event details
    const { data: event, error: eventError } = await supabase
      .from('events')
      .select('*, profiles:organizer_id(stripe_account_id)')
      .eq('id', event_id)
      .single()

    if (eventError || !event) {
      return new Response(JSON.stringify({ error: 'Event not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Get or create Stripe customer for the user
    let stripeCustomerId: string | undefined

    const { data: profile } = await supabase
      .from('profiles')
      .select('stripe_customer_id')
      .eq('id', user.id)
      .single()

    if (profile?.stripe_customer_id) {
      stripeCustomerId = profile.stripe_customer_id
    } else {
      // Create new Stripe customer
      const customer = await stripe.customers.create({
        email: user.email,
        metadata: { supabase_user_id: user.id },
      })
      stripeCustomerId = customer.id

      // Save to profile
      await supabase
        .from('profiles')
        .update({ stripe_customer_id: stripeCustomerId })
        .eq('id', user.id)
    }

    // Calculate platform fee (5%)
    const platformFee = Math.round(amount_cents * 0.05)

    // Create payment intent
    const paymentIntentParams: Stripe.PaymentIntentCreateParams = {
      amount: amount_cents,
      currency: 'usd',
      customer: stripeCustomerId,
      metadata: {
        pending_payment_id,
        event_id,
        ticket_type_id: ticket_type_id || '',
        customer_id: user.id,
        vendor_id: pendingPayment.vendor_id,
        type: 'tap_to_pay',
      },
      automatic_payment_methods: {
        enabled: true,
      },
    }

    // If event has a connected Stripe account, use it
    const organizerStripeAccount = event.profiles?.stripe_account_id
    if (organizerStripeAccount) {
      paymentIntentParams.transfer_data = {
        destination: organizerStripeAccount,
      }
      paymentIntentParams.application_fee_amount = platformFee
    }

    const paymentIntent = await stripe.paymentIntents.create(paymentIntentParams)

    // Update pending payment with payment intent ID
    await supabase
      .from('pending_payments')
      .update({ stripe_payment_intent_id: paymentIntent.id })
      .eq('id', pending_payment_id)

    return new Response(
      JSON.stringify({
        client_secret: paymentIntent.client_secret,
        payment_intent_id: paymentIntent.id,
      }),
      {
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      }
    )
  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      {
        status: 500,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      }
    )
  }
})
