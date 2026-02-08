import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import Stripe from 'https://esm.sh/stripe@14.21.0'

const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY')
const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const stripe = stripeSecretKey ? new Stripe(stripeSecretKey, {
  apiVersion: '2023-10-16',
}) : null

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ManageRequest {
  action: 'list' | 'create_setup_intent' | 'delete' | 'set_default'
  payment_method_id?: string
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    if (!stripe) {
      return new Response(
        JSON.stringify({ error: 'Stripe is not configured' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify authentication
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid authentication' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const body: ManageRequest = await req.json()
    const { action } = body

    if (!action || !['list', 'create_setup_intent', 'delete', 'set_default', 'debug'].includes(action)) {
      return new Response(
        JSON.stringify({ error: 'Invalid action. Must be "list", "create_setup_intent", "delete", or "set_default"' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get or create Stripe customer ID from profiles
    const { data: profile, error: profileError } = await supabaseAdmin
      .from('profiles')
      .select('stripe_customer_id')
      .eq('id', user.id)
      .single()

    console.log('Profile lookup for user:', user.id, '→ stripe_customer_id:', profile?.stripe_customer_id || 'NULL', 'error:', profileError?.message || 'none')

    if (profileError) {
      console.error('Failed to fetch profile:', profileError)
      return new Response(
        JSON.stringify({ error: 'Failed to fetch user profile' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // --- DEBUG ---
    if (action === 'debug') {
      const debugInfo: any = {
        user_id: user.id,
        user_email: user.email,
        profile_stripe_customer_id: profile?.stripe_customer_id || null,
      }

      if (profile?.stripe_customer_id) {
        const methods = await stripe.paymentMethods.list({
          customer: profile.stripe_customer_id,
          type: 'card',
        })
        const customer = await stripe.customers.retrieve(profile.stripe_customer_id)
        debugInfo.stripe_card_count = methods.data.length
        debugInfo.stripe_cards = methods.data.map((pm: any) => ({
          id: pm.id,
          brand: pm.card?.brand,
          last4: pm.card?.last4,
        }))
        debugInfo.default_payment_method = (customer as any).invoice_settings?.default_payment_method
      }

      return new Response(
        JSON.stringify(debugInfo),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    let customerId = profile?.stripe_customer_id

    // For create_setup_intent, create a Stripe customer if none exists
    if (!customerId && action === 'create_setup_intent') {
      console.log('Creating Stripe customer for user:', user.id)
      const customer = await stripe.customers.create({
        email: user.email,
        metadata: { supabase_user_id: user.id },
      })
      customerId = customer.id

      // Save to profile
      await supabaseAdmin
        .from('profiles')
        .update({ stripe_customer_id: customerId })
        .eq('id', user.id)

      console.log('Created Stripe customer:', customerId)
    }

    if (!customerId) {
      // No customer = no cards saved
      if (action === 'list') {
        return new Response(
          JSON.stringify({ cards: [], default_payment_method: null }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      return new Response(
        JSON.stringify({ error: 'No Stripe customer found. Add a card first.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // --- LIST ---
    if (action === 'list') {
      console.log('Listing payment methods for customer:', customerId)

      const paymentMethods = await stripe.paymentMethods.list({
        customer: customerId,
        type: 'card',
      })

      const customer = await stripe.customers.retrieve(customerId)
      const defaultPm = (customer as any).invoice_settings?.default_payment_method

      const cards = paymentMethods.data.map((pm: any) => ({
        id: pm.id,
        brand: pm.card?.brand || 'unknown',
        last4: pm.card?.last4 || '****',
        exp_month: pm.card?.exp_month,
        exp_year: pm.card?.exp_year,
        is_default: pm.id === defaultPm,
      }))

      console.log(`Found ${cards.length} cards, default: ${defaultPm || 'none'}`)

      return new Response(
        JSON.stringify({ cards, default_payment_method: defaultPm }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // --- CREATE SETUP INTENT ---
    if (action === 'create_setup_intent') {
      console.log('Creating setup intent for customer:', customerId)

      const setupIntent = await stripe.setupIntents.create({
        customer: customerId,
        payment_method_types: ['card'],
      })

      const ephemeralKey = await stripe.ephemeralKeys.create(
        { customer: customerId },
        { apiVersion: '2023-10-16' }
      )

      console.log('Setup intent created:', setupIntent.id)

      return new Response(
        JSON.stringify({
          client_secret: setupIntent.client_secret,
          ephemeral_key: ephemeralKey.secret,
          customer_id: customerId,
          setup_intent_id: setupIntent.id,
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // --- DELETE ---
    if (action === 'delete') {
      const { payment_method_id } = body

      if (!payment_method_id) {
        return new Response(
          JSON.stringify({ error: 'payment_method_id is required' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      console.log('Detaching payment method:', payment_method_id)

      // Verify the payment method belongs to this customer
      const pm = await stripe.paymentMethods.retrieve(payment_method_id)
      if (pm.customer !== customerId) {
        return new Response(
          JSON.stringify({ error: 'Payment method does not belong to this customer' }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      await stripe.paymentMethods.detach(payment_method_id)

      console.log('Payment method detached:', payment_method_id)

      return new Response(
        JSON.stringify({ success: true }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // --- SET DEFAULT ---
    if (action === 'set_default') {
      const { payment_method_id } = body

      if (!payment_method_id) {
        return new Response(
          JSON.stringify({ error: 'payment_method_id is required' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      console.log('Setting default payment method:', payment_method_id)

      // Verify the payment method belongs to this customer
      const pm = await stripe.paymentMethods.retrieve(payment_method_id)
      if (pm.customer !== customerId) {
        return new Response(
          JSON.stringify({ error: 'Payment method does not belong to this customer' }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      await stripe.customers.update(customerId, {
        invoice_settings: { default_payment_method: payment_method_id },
      })

      console.log('Default payment method updated:', payment_method_id)

      return new Response(
        JSON.stringify({ success: true, default_payment_method: payment_method_id }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({ error: 'Unknown action' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error managing payment methods:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
