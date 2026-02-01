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

/**
 * Fetches the seller's balance from Stripe and caches it in the database.
 *
 * Returns:
 * - available_balance_cents: Funds ready for withdrawal
 * - pending_balance_cents: Funds not yet available (in transit)
 * - payouts_enabled: Whether seller can withdraw (has added bank details)
 * - details_submitted: Whether seller has completed full verification
 * - needs_onboarding: Whether seller needs to complete Stripe onboarding to withdraw
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

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

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

    // Get seller's Stripe account ID
    const { data: sellerBalance } = await supabaseAdmin
      .from('seller_balances')
      .select('stripe_account_id')
      .eq('user_id', user.id)
      .single()

    if (!sellerBalance?.stripe_account_id) {
      // User doesn't have a seller account yet
      return new Response(
        JSON.stringify({
          has_account: false,
          available_balance_cents: 0,
          pending_balance_cents: 0,
          payouts_enabled: false,
          details_submitted: false,
          needs_onboarding: true,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    const accountId = sellerBalance.stripe_account_id

    // Fetch the account details and balance from Stripe in parallel
    const [account, balance] = await Promise.all([
      stripe.accounts.retrieve(accountId),
      stripe.balance.retrieve({ stripeAccount: accountId }),
    ])

    // Extract USD balance (or default currency)
    const availableBalance = balance.available.find(b => b.currency === 'usd')
    const pendingBalance = balance.pending.find(b => b.currency === 'usd')

    const availableCents = availableBalance?.amount ?? 0
    const pendingCents = pendingBalance?.amount ?? 0
    const payoutsEnabled = account.payouts_enabled ?? false
    const detailsSubmitted = account.details_submitted ?? false

    // Cache the balance in the database
    const { error: updateError } = await supabaseAdmin
      .from('seller_balances')
      .update({
        available_balance_cents: availableCents,
        pending_balance_cents: pendingCents,
        payouts_enabled: payoutsEnabled,
        details_submitted: detailsSubmitted,
        last_synced_at: new Date().toISOString(),
      })
      .eq('user_id', user.id)

    if (updateError) {
      console.error('Failed to update cached balance:', updateError)
      // Don't fail the request - we still have the data from Stripe
    }

    // Also update the legacy profiles flag for backwards compatibility
    if (payoutsEnabled && account.charges_enabled) {
      await supabaseAdmin
        .from('profiles')
        .update({ stripe_connect_onboarded: true })
        .eq('id', user.id)
    }

    console.log(`Fetched balance for user ${user.id}: available=${availableCents}, pending=${pendingCents}`)

    return new Response(
      JSON.stringify({
        has_account: true,
        available_balance_cents: availableCents,
        pending_balance_cents: pendingCents,
        payouts_enabled: payoutsEnabled,
        details_submitted: detailsSubmitted,
        needs_onboarding: !payoutsEnabled,
        currency: 'usd',
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )

  } catch (error) {
    console.error('Error fetching seller balance:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Failed to fetch balance' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
