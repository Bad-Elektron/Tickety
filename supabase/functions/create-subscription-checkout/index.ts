import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import Stripe from 'https://esm.sh/stripe@13.10.0?target=deno'

// Log environment variable status at startup
const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY')
const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const proPriceId = Deno.env.get('STRIPE_PRO_PRICE_ID')
const enterprisePriceId = Deno.env.get('STRIPE_ENTERPRISE_PRICE_ID')

console.log('=== Environment Check ===')
console.log('STRIPE_SECRET_KEY set:', !!stripeSecretKey, stripeSecretKey ? `(${stripeSecretKey.substring(0, 7)}...)` : '')
console.log('STRIPE_PRO_PRICE_ID:', proPriceId || 'NOT SET - using fallback')
console.log('STRIPE_ENTERPRISE_PRICE_ID:', enterprisePriceId || 'NOT SET - using fallback')

const stripe = stripeSecretKey ? new Stripe(stripeSecretKey, {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
}) : null

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Stripe Price IDs for each tier
// These should be configured in your Stripe dashboard
const TIER_PRICES: Record<string, string> = {
  pro: proPriceId || 'price_pro_monthly',
  enterprise: enterprisePriceId || 'price_enterprise_monthly',
}

interface CheckoutRequest {
  tier: 'pro' | 'enterprise'
  user_id: string
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    console.log('=== Request Started ===')

    // Check if Stripe is configured
    if (!stripe) {
      console.error('STRIPE_SECRET_KEY not configured!')
      return new Response(
        JSON.stringify({ error: 'Stripe is not configured. Please set STRIPE_SECRET_KEY.' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify authentication
    const authHeader = req.headers.get('Authorization')
    console.log('Auth header present:', !!authHeader)
    console.log('Auth header prefix:', authHeader?.substring(0, 20))

    if (!authHeader) {
      console.log('ERROR: No auth header')
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Create Supabase admin client
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

    // Verify the user is authenticated
    const token = authHeader.replace('Bearer ', '')
    console.log('Token length:', token.length)

    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)

    console.log('Auth result - user:', user?.id, 'error:', authError?.message)

    if (authError || !user) {
      console.log('ERROR: Auth failed -', authError?.message || 'no user')
      return new Response(
        JSON.stringify({ error: `Invalid authentication: ${authError?.message || 'no user'}` }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const body: CheckoutRequest = await req.json()
    const { tier } = body

    // Validate tier
    if (!tier || !['pro', 'enterprise'].includes(tier)) {
      return new Response(
        JSON.stringify({ error: 'Invalid tier. Must be "pro" or "enterprise"' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const priceId = TIER_PRICES[tier]
    console.log('Using price ID:', priceId, 'for tier:', tier)

    if (!priceId) {
      return new Response(
        JSON.stringify({ error: 'Price not configured for this tier' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get or create Stripe customer
    console.log('Step 1: Fetching profile...')
    const { data: profile, error: profileError } = await supabaseAdmin
      .from('profiles')
      .select('stripe_customer_id, email, full_name')
      .eq('id', user.id)
      .single()

    if (profileError) {
      console.error('Profile fetch error:', profileError)
    }
    console.log('Profile found:', !!profile, 'stripe_customer_id:', profile?.stripe_customer_id)

    let customerId = profile?.stripe_customer_id

    if (!customerId) {
      console.log('Step 2: Creating Stripe customer...')
      try {
        const customer = await stripe.customers.create({
          email: user.email,
          name: profile?.full_name || undefined,
          metadata: {
            supabase_user_id: user.id,
          },
        })
        customerId = customer.id
        console.log('Stripe customer created:', customerId)

        // Save customer ID to profile
        const { error: updateError } = await supabaseAdmin
          .from('profiles')
          .update({ stripe_customer_id: customerId })
          .eq('id', user.id)

        if (updateError) {
          console.error('Failed to save customer ID:', updateError)
        }
      } catch (stripeError) {
        console.error('Stripe customer creation failed:', stripeError)
        throw stripeError
      }
    } else {
      console.log('Step 2: Using existing Stripe customer:', customerId)
    }

    // Check if user already has an active subscription
    console.log('Step 3: Checking for existing subscription...')
    const { data: existingSub } = await supabaseAdmin
      .from('subscriptions')
      .select('stripe_subscription_id, tier, status')
      .eq('user_id', user.id)
      .single()

    console.log('Existing subscription:', existingSub)

    if (existingSub?.stripe_subscription_id && existingSub.status === 'active') {
      console.log('User already has active subscription')
      return new Response(
        JSON.stringify({
          error: 'You already have an active subscription. Please use the billing portal to change plans.'
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Create ephemeral key for the customer
    console.log('Step 4: Creating ephemeral key...')
    let ephemeralKey
    try {
      ephemeralKey = await stripe.ephemeralKeys.create(
        { customer: customerId },
        { apiVersion: '2023-10-16' }
      )
      console.log('Ephemeral key created')
    } catch (keyError) {
      console.error('Ephemeral key creation failed:', keyError)
      throw keyError
    }

    // Create subscription with incomplete status
    // This allows us to collect payment info via the mobile SDK
    console.log('Step 5: Creating Stripe subscription with price:', priceId)
    let subscription
    try {
      subscription = await stripe.subscriptions.create({
        customer: customerId,
        items: [{ price: priceId }],
        payment_behavior: 'default_incomplete',
        payment_settings: {
          save_default_payment_method: 'on_subscription',
        },
        expand: ['latest_invoice.payment_intent'],
        metadata: {
          supabase_user_id: user.id,
          tier: tier,
        },
      })
      console.log('Subscription created:', subscription.id)
    } catch (subError) {
      console.error('Subscription creation failed:', subError)
      throw subError
    }

    // Get the client secret from the payment intent
    const invoice = subscription.latest_invoice as Stripe.Invoice
    const paymentIntent = invoice.payment_intent as Stripe.PaymentIntent

    if (!paymentIntent?.client_secret) {
      console.error('No client secret in payment intent')
      return new Response(
        JSON.stringify({ error: 'Failed to create payment session' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Subscription checkout created: ${subscription.id} for tier ${tier}`)

    // Step 6: Insert/update subscription record in database
    // This creates the record immediately so the app can see it
    // The webhook will update the status when payment completes
    console.log('Step 6: Upserting subscription record in database...')
    const { error: upsertError } = await supabaseAdmin
      .from('subscriptions')
      .upsert({
        user_id: user.id,
        tier: tier,
        status: 'incomplete', // Will be updated to 'active' when payment succeeds
        stripe_subscription_id: subscription.id,
        stripe_price_id: priceId,
        current_period_start: new Date(subscription.current_period_start * 1000).toISOString(),
        current_period_end: new Date(subscription.current_period_end * 1000).toISOString(),
        cancel_at_period_end: false,
      }, {
        onConflict: 'user_id',
      })

    if (upsertError) {
      console.error('Failed to upsert subscription record:', upsertError)
      // Don't fail the checkout - just log the error
    } else {
      console.log('Subscription record created/updated in database')
    }

    return new Response(
      JSON.stringify({
        client_secret: paymentIntent.client_secret,
        customer_id: customerId,
        ephemeral_key: ephemeralKey.secret,
        subscription_id: subscription.id,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )

  } catch (error) {
    console.error('Error creating subscription checkout:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
