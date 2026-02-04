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

interface EnableCashSalesRequest {
  event_id: string
}

/**
 * Enable cash sales for an event.
 *
 * This function checks if the organizer already has a payment method on file.
 * If yes, it enables cash sales immediately.
 * If no, it returns a SetupIntent for adding a card.
 */
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

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    })

    // Verify the user is authenticated
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(
      authHeader.replace('Bearer ', '')
    )

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid authentication' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const body: EnableCashSalesRequest = await req.json()
    const { event_id } = body

    if (!event_id) {
      return new Response(
        JSON.stringify({ error: 'Missing required field: event_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Enabling cash sales for event ${event_id} by user ${user.id}`)

    // Verify user is the organizer of this event
    const { data: event, error: eventError } = await supabaseAdmin
      .from('events')
      .select('id, organizer_id, title, organizer_stripe_customer_id, organizer_payment_method_id, cash_sales_enabled')
      .eq('id', event_id)
      .single()

    if (eventError || !event) {
      console.error('Event not found:', event_id, eventError)
      return new Response(
        JSON.stringify({ error: 'Event not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (event.organizer_id !== user.id) {
      return new Response(
        JSON.stringify({ error: 'You are not the organizer of this event' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check if already enabled
    if (event.cash_sales_enabled) {
      return new Response(
        JSON.stringify({
          success: true,
          already_enabled: true,
          message: 'Cash sales are already enabled for this event',
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get or create Stripe customer for organizer
    let customerId = event.organizer_stripe_customer_id

    if (!customerId) {
      // Check if organizer has a customer ID in their profile
      const { data: profile } = await supabaseAdmin
        .from('profiles')
        .select('stripe_customer_id, email, full_name')
        .eq('id', user.id)
        .single()

      customerId = profile?.stripe_customer_id

      if (!customerId) {
        // Create new Stripe customer
        console.log('Creating Stripe customer for organizer')
        const customer = await stripe.customers.create({
          email: user.email,
          name: profile?.full_name || undefined,
          metadata: {
            supabase_user_id: user.id,
            type: 'organizer',
          },
        })
        customerId = customer.id

        // Save to profile
        await supabaseAdmin
          .from('profiles')
          .update({ stripe_customer_id: customerId })
          .eq('id', user.id)
      }

      // Update event with customer ID
      await supabaseAdmin
        .from('events')
        .update({ organizer_stripe_customer_id: customerId })
        .eq('id', event_id)
    }

    console.log(`Using Stripe customer: ${customerId}`)

    // Check if customer already has a payment method
    const paymentMethods = await stripe.paymentMethods.list({
      customer: customerId,
      type: 'card',
      limit: 1,
    })

    if (paymentMethods.data.length > 0) {
      // Customer already has a payment method - enable cash sales immediately
      const paymentMethod = paymentMethods.data[0]
      console.log(`Found existing payment method: ${paymentMethod.id}`)

      // Update event to enable cash sales
      const { error: updateError } = await supabaseAdmin
        .from('events')
        .update({
          cash_sales_enabled: true,
          organizer_payment_method_id: paymentMethod.id,
        })
        .eq('id', event_id)

      if (updateError) {
        console.error('Failed to update event:', updateError)
        return new Response(
          JSON.stringify({ error: 'Failed to enable cash sales' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      console.log(`Cash sales enabled for event ${event_id} using existing payment method`)

      // Build response with card info
      const cardInfo = paymentMethod.card
        ? {
            brand: paymentMethod.card.brand,
            last4: paymentMethod.card.last4,
            exp_month: paymentMethod.card.exp_month,
            exp_year: paymentMethod.card.exp_year,
          }
        : null

      return new Response(
        JSON.stringify({
          success: true,
          cash_sales_enabled: true,
          used_existing_payment_method: true,
          payment_method_id: paymentMethod.id,
          card: cardInfo,
          message: 'Cash sales enabled using your existing payment method',
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // No existing payment method - create SetupIntent for adding a card
    console.log('No existing payment method found, creating SetupIntent')

    const setupIntent = await stripe.setupIntents.create({
      customer: customerId,
      usage: 'off_session', // We'll charge this card without the user present
      automatic_payment_methods: {
        enabled: true,
      },
      metadata: {
        event_id,
        event_title: event.title,
        user_id: user.id,
        purpose: 'cash_sales_fee',
      },
    })

    console.log(`Created SetupIntent: ${setupIntent.id}`)

    // Create ephemeral key for the customer
    const ephemeralKey = await stripe.ephemeralKeys.create(
      { customer: customerId },
      { apiVersion: '2023-10-16' }
    )

    return new Response(
      JSON.stringify({
        success: true,
        needs_payment_method: true,
        setup_intent_id: setupIntent.id,
        client_secret: setupIntent.client_secret,
        customer_id: customerId,
        ephemeral_key: ephemeralKey.secret,
        publishable_key: Deno.env.get('STRIPE_PUBLISHABLE_KEY'),
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error: unknown) {
    console.error('Error enabling cash sales:', error)
    const errorMessage = error instanceof Error ? error.message : 'Internal server error'
    return new Response(
      JSON.stringify({ error: errorMessage }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
