import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import Stripe from 'https://esm.sh/stripe@14.21.0'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
})

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

// Platform fee percentage (5%)
const PLATFORM_FEE_PERCENT = 0.05

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ResaleIntentRequest {
  resale_listing_id: string
  amount_cents: number
  currency: string
  user_id: string
}

/**
 * Creates a PaymentIntent for a resale ticket purchase.
 *
 * IMPORTANT FLOW CHANGE:
 * - Previously used transfer_data.destination which transfers funds immediately to seller's bank
 * - Now uses on_behalf_of which keeps funds in seller's Stripe balance (wallet)
 * - Seller can withdraw when they add bank details
 *
 * This allows sellers to list tickets WITHOUT completing full Stripe onboarding.
 * Legal note: Funds are held by Stripe (licensed money transmitter), not Tickety.
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

    const body: ResaleIntentRequest = await req.json()
    const { resale_listing_id, amount_cents, currency = 'usd' } = body

    if (!resale_listing_id || !amount_cents) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: resale_listing_id, amount_cents' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Looking up resale listing: ${resale_listing_id}`)

    // Get the resale listing with ticket and event info
    // Note: seller_id references auth.users, not profiles, so we query profiles separately
    const { data: listing, error: listingError } = await supabaseAdmin
      .from('resale_listings')
      .select(`
        *,
        tickets(*, events(*))
      `)
      .eq('id', resale_listing_id)
      .single()

    console.log(`Listing lookup result:`, { listing: listing?.id, error: listingError?.message })

    if (listingError || !listing) {
      console.error(`Listing not found: ${resale_listing_id}`, listingError)
      return new Response(
        JSON.stringify({ error: 'Listing not found', details: listingError?.message }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get seller's Stripe Connect account from profiles (separate query)
    const { data: sellerProfile } = await supabaseAdmin
      .from('profiles')
      .select('stripe_connect_account_id')
      .eq('id', listing.seller_id)
      .single()

    console.log(`Seller profile lookup:`, { sellerId: listing.seller_id, hasAccount: !!sellerProfile?.stripe_connect_account_id })

    // Verify listing is still active
    if (listing.status !== 'active') {
      return new Response(
        JSON.stringify({ error: 'This listing is no longer available' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify price matches
    if (listing.price_cents !== amount_cents) {
      return new Response(
        JSON.stringify({ error: 'Price mismatch. Please refresh and try again.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get seller's Stripe account - check seller_balances first (new flow), then profiles (legacy)
    const { data: sellerBalance } = await supabaseAdmin
      .from('seller_balances')
      .select('stripe_account_id')
      .eq('user_id', listing.seller_id)
      .single()

    const sellerAccountId = sellerBalance?.stripe_account_id || sellerProfile?.stripe_connect_account_id

    // Verify seller has a Stripe account (no longer require full onboarding!)
    if (!sellerAccountId) {
      return new Response(
        JSON.stringify({ error: 'Seller has not set up their account' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Prevent buying own listing
    if (listing.seller_id === user.id) {
      return new Response(
        JSON.stringify({ error: 'You cannot purchase your own listing' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Calculate platform fee (5%)
    const platformFeeCents = Math.round(amount_cents * PLATFORM_FEE_PERCENT)

    // Get or create Stripe customer for buyer
    const { data: buyerProfile } = await supabaseAdmin
      .from('profiles')
      .select('stripe_customer_id, email, display_name')
      .eq('id', user.id)
      .single()

    let customerId = buyerProfile?.stripe_customer_id

    if (!customerId) {
      const customer = await stripe.customers.create({
        email: user.email,
        name: buyerProfile?.display_name || undefined,
        metadata: { supabase_user_id: user.id },
      })
      customerId = customer.id

      await supabaseAdmin
        .from('profiles')
        .update({ stripe_customer_id: customerId })
        .eq('id', user.id)
    }

    // Create ephemeral key
    const ephemeralKey = await stripe.ephemeralKeys.create(
      { customer: customerId },
      { apiVersion: '2023-10-16' }
    )

    // Create PaymentIntent using on_behalf_of
    // This creates a "direct charge" on the connected account
    // Funds stay in seller's Stripe balance until they withdraw
    // Platform fee is collected separately via application_fee_amount
    const paymentIntent = await stripe.paymentIntents.create({
      amount: amount_cents,
      currency,
      customer: customerId,
      automatic_payment_methods: { enabled: true },
      // Enable saving payment methods for future use
      setup_future_usage: 'off_session',
      // Use application_fee_amount with on_behalf_of for separate charges
      application_fee_amount: platformFeeCents,
      // on_behalf_of creates a direct charge - funds go to seller's Stripe balance
      // NOT their bank account. They can withdraw when they add bank details.
      on_behalf_of: sellerAccountId,
      // Transfer to seller's connected account
      transfer_data: {
        destination: sellerAccountId,
      },
      metadata: {
        resale_listing_id,
        ticket_id: listing.ticket_id,
        event_id: listing.tickets.event_id,
        buyer_id: user.id,
        seller_id: listing.seller_id,
        type: 'resale_purchase',
        event_title: listing.tickets.events?.title,
        platform_fee_cents: platformFeeCents.toString(),
        seller_account_id: sellerAccountId,
      },
      // On successful payment, this will:
      // 1. Charge the buyer
      // 2. Transfer (amount - platform_fee) to seller's Stripe balance (NOT bank)
      // 3. Platform keeps the application_fee_amount
      // 4. Seller can withdraw when they add bank details
    })

    // Create pending payment record
    const { data: payment, error: paymentError } = await supabaseAdmin
      .from('payments')
      .insert({
        user_id: user.id,
        event_id: listing.tickets.event_id,
        ticket_id: listing.ticket_id,
        amount_cents,
        platform_fee_cents: platformFeeCents,
        currency,
        status: 'pending',
        type: 'resale_purchase',
        stripe_payment_intent_id: paymentIntent.id,
        metadata: {
          resale_listing_id,
          seller_id: listing.seller_id,
          event_title: listing.tickets.events?.title,
        },
      })
      .select()
      .single()

    if (paymentError) {
      console.error('Failed to create payment record:', paymentError)
    }

    console.log(`Created resale payment intent ${paymentIntent.id} for listing ${resale_listing_id}`)
    console.log(`Platform fee: ${platformFeeCents} cents, Seller receives: ${amount_cents - platformFeeCents} cents`)

    return new Response(
      JSON.stringify({
        payment_intent_id: paymentIntent.id,
        client_secret: paymentIntent.client_secret,
        customer_id: customerId,
        ephemeral_key: ephemeralKey.secret,
        payment_id: payment?.id,
        platform_fee_cents: platformFeeCents,
        seller_amount_cents: amount_cents - platformFeeCents,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )

  } catch (error) {
    console.error('Error creating resale payment intent:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
