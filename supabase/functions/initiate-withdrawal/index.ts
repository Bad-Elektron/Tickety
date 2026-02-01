import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import Stripe from 'https://esm.sh/stripe@14.21.0'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
})

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
// For development, use a placeholder URL that Stripe accepts
// In production, set APP_URL to your actual app domain
const appUrl = Deno.env.get('APP_URL') || 'https://tickety.app'
const isDevMode = !Deno.env.get('APP_URL')

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface WithdrawalRequest {
  amount_cents?: number // Optional: if not provided, withdraw full available balance
}

/**
 * Initiates a payout from the seller's Stripe balance to their bank account.
 *
 * If the seller hasn't added bank details yet, returns an onboarding URL
 * for them to complete their Stripe setup.
 *
 * Returns:
 * - success: true if payout was initiated
 * - needs_onboarding: true if seller needs to add bank details first
 * - onboarding_url: URL to redirect to for adding bank details
 * - payout_id: Stripe payout ID if successful
 * - amount_cents: Amount being withdrawn
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

    // Parse request body
    const body: WithdrawalRequest = await req.json().catch(() => ({}))

    // Get seller's Stripe account ID
    const { data: sellerBalance } = await supabaseAdmin
      .from('seller_balances')
      .select('stripe_account_id')
      .eq('user_id', user.id)
      .single()

    if (!sellerBalance?.stripe_account_id) {
      return new Response(
        JSON.stringify({ error: 'No seller account found. Please create a seller account first.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const accountId = sellerBalance.stripe_account_id

    // Fetch the account details
    const account = await stripe.accounts.retrieve(accountId)

    // Check if payouts are enabled (bank details added)
    if (!account.payouts_enabled) {
      console.log(`User ${user.id} needs to complete onboarding to withdraw`)

      try {
        // Generate an account link for the user to add bank details
        const accountLink = await stripe.accountLinks.create({
          account: accountId,
          refresh_url: `${appUrl}/wallet/setup/refresh`,
          return_url: `${appUrl}/wallet/setup/complete`,
          type: 'account_onboarding',
          collect: 'eventually_due', // Only collect what's needed for payouts
        })

        return new Response(
          JSON.stringify({
            success: false,
            needs_onboarding: true,
            onboarding_url: accountLink.url,
            message: 'Please complete your account setup to enable withdrawals.',
          }),
          {
            status: 200,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        )
      } catch (linkError) {
        console.error('Failed to create account link:', linkError)

        // Fallback: Create a login link to Stripe Express dashboard
        // This works in test mode and allows users to manage their account
        const loginLink = await stripe.accounts.createLoginLink(accountId)

        return new Response(
          JSON.stringify({
            success: false,
            needs_onboarding: true,
            onboarding_url: loginLink.url,
            message: 'Please complete your account setup in Stripe to enable withdrawals.',
          }),
          {
            status: 200,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        )
      }
    }

    // Fetch the current balance
    const balance = await stripe.balance.retrieve({ stripeAccount: accountId })
    const availableBalance = balance.available.find(b => b.currency === 'usd')
    const availableCents = availableBalance?.amount ?? 0

    if (availableCents <= 0) {
      return new Response(
        JSON.stringify({ error: 'No funds available for withdrawal.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Determine withdrawal amount
    const withdrawAmount = body.amount_cents
      ? Math.min(body.amount_cents, availableCents)
      : availableCents

    if (withdrawAmount <= 0) {
      return new Response(
        JSON.stringify({ error: 'Invalid withdrawal amount.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Create the payout
    const payout = await stripe.payouts.create(
      {
        amount: withdrawAmount,
        currency: 'usd',
        description: 'Tickety earnings withdrawal',
        metadata: {
          supabase_user_id: user.id,
          platform: 'tickety',
        },
      },
      {
        stripeAccount: accountId,
      }
    )

    console.log(`Initiated payout ${payout.id} for user ${user.id}: ${withdrawAmount} cents`)

    // Update the cached balance
    const newAvailableCents = availableCents - withdrawAmount
    await supabaseAdmin
      .from('seller_balances')
      .update({
        available_balance_cents: newAvailableCents,
        last_synced_at: new Date().toISOString(),
      })
      .eq('user_id', user.id)

    return new Response(
      JSON.stringify({
        success: true,
        needs_onboarding: false,
        payout_id: payout.id,
        amount_cents: withdrawAmount,
        estimated_arrival: payout.arrival_date
          ? new Date(payout.arrival_date * 1000).toISOString()
          : null,
        remaining_balance_cents: newAvailableCents,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )

  } catch (error) {
    console.error('Error initiating withdrawal:', error)

    // Handle specific Stripe errors
    if (error.type === 'StripeInvalidRequestError') {
      return new Response(
        JSON.stringify({ error: 'Unable to process withdrawal. Please try again later.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({ error: error.message || 'Failed to initiate withdrawal' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
