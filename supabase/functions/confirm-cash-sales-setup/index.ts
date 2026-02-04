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

interface ConfirmSetupRequest {
  event_id: string
  setup_intent_id: string
}

/**
 * Confirms cash sales setup after the organizer has added a payment method.
 *
 * This function:
 * 1. Verifies the SetupIntent succeeded
 * 2. Gets the payment method from the SetupIntent
 * 3. Updates the event with the payment method and enables cash sales
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

    const body: ConfirmSetupRequest = await req.json()
    const { event_id, setup_intent_id } = body

    if (!event_id || !setup_intent_id) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: event_id, setup_intent_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Confirming cash sales setup for event ${event_id}, SI: ${setup_intent_id}`)

    // Verify user is the organizer of this event
    const { data: event, error: eventError } = await supabaseAdmin
      .from('events')
      .select('id, organizer_id, organizer_stripe_customer_id')
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

    // Retrieve the SetupIntent from Stripe
    const setupIntent = await stripe.setupIntents.retrieve(setup_intent_id)

    console.log(`SetupIntent status: ${setupIntent.status}`)

    // Verify the SetupIntent succeeded
    if (setupIntent.status !== 'succeeded') {
      return new Response(
        JSON.stringify({
          error: 'Payment method setup was not successful',
          status: setupIntent.status,
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify the SetupIntent is for this event
    if (setupIntent.metadata?.event_id !== event_id) {
      return new Response(
        JSON.stringify({ error: 'SetupIntent does not match this event' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get the payment method
    const paymentMethodId = setupIntent.payment_method as string

    if (!paymentMethodId) {
      return new Response(
        JSON.stringify({ error: 'No payment method found on SetupIntent' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Payment method: ${paymentMethodId}`)

    // Get payment method details for display
    const paymentMethod = await stripe.paymentMethods.retrieve(paymentMethodId)

    // Update event to enable cash sales
    const { error: updateError } = await supabaseAdmin
      .from('events')
      .update({
        cash_sales_enabled: true,
        organizer_payment_method_id: paymentMethodId,
      })
      .eq('id', event_id)

    if (updateError) {
      console.error('Failed to update event:', updateError)
      return new Response(
        JSON.stringify({ error: 'Failed to enable cash sales' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Cash sales enabled for event ${event_id}`)

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
        payment_method_id: paymentMethodId,
        card: cardInfo,
        message: 'Cash sales have been enabled for this event',
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error: unknown) {
    console.error('Error confirming cash sales setup:', error)
    const errorMessage = error instanceof Error ? error.message : 'Internal server error'
    return new Response(
      JSON.stringify({ error: errorMessage }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
