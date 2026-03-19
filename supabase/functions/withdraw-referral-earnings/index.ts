import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import Stripe from 'https://esm.sh/stripe@14.21.0'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
})

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const appUrl = Deno.env.get('APP_URL') || 'https://tickety.app'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/**
 * Withdraws referral earnings to the user's Stripe Express account.
 *
 * Reuses the seller payout pattern:
 * - Check/create Stripe Express account via seller_balances
 * - If payouts_enabled → create Stripe Transfer → mark earnings paid via FIFO
 * - If not → return needs_onboarding with account link URL
 */
serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(
      authHeader.replace('Bearer ', '')
    )

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid authentication' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get withdrawable balance
    const { data: balanceData, error: balanceError } = await supabaseAdmin.rpc(
      'get_referral_balance',
      { p_user_id: user.id }
    )

    if (balanceError) {
      console.error('Failed to get referral balance:', balanceError)
      return new Response(
        JSON.stringify({ error: 'Failed to fetch balance' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const balance = balanceData?.[0] || balanceData
    const withdrawableCents = Number(balance?.withdrawable_cents || 0)

    if (withdrawableCents <= 0) {
      return new Response(
        JSON.stringify({
          error: 'No withdrawable earnings. Earnings require a 7-day hold period before withdrawal.',
          total_cents: Number(balance?.total_cents || 0),
          pending_cents: Number(balance?.pending_cents || 0),
          paid_cents: Number(balance?.paid_cents || 0),
          withdrawable_cents: 0,
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get or check Stripe Express account (reuse seller_balances table)
    let { data: sellerBalance } = await supabaseAdmin
      .from('seller_balances')
      .select('stripe_account_id')
      .eq('user_id', user.id)
      .maybeSingle()

    let accountId = sellerBalance?.stripe_account_id

    // Create Stripe Express account if none exists
    if (!accountId) {
      const account = await stripe.accounts.create({
        type: 'express',
        email: user.email,
        metadata: {
          supabase_user_id: user.id,
          platform: 'tickety',
          purpose: 'referral_earnings',
        },
        capabilities: {
          card_payments: { requested: true },
          transfers: { requested: true },
        },
        business_type: 'individual',
        business_profile: {
          product_description: 'Referral earnings on Tickety',
          mcc: '7922',
        },
        settings: {
          payouts: {
            schedule: { interval: 'manual' },
          },
        },
      })

      accountId = account.id
      console.log(`Created Stripe Express account ${accountId} for referral user ${user.id}`)

      const { error: insertError } = await supabaseAdmin
        .from('seller_balances')
        .upsert({
          user_id: user.id,
          stripe_account_id: accountId,
          available_balance_cents: 0,
          pending_balance_cents: 0,
          payouts_enabled: false,
          details_submitted: false,
        }, { onConflict: 'user_id' })

      if (insertError) {
        console.error('Failed to create seller_balances record:', insertError)
      }
    }

    // Check if payouts are enabled
    const account = await stripe.accounts.retrieve(accountId)

    if (!account.payouts_enabled) {
      console.log(`User ${user.id} needs to complete onboarding to withdraw referral earnings`)

      try {
        const accountLink = await stripe.accountLinks.create({
          account: accountId,
          refresh_url: `${appUrl}/wallet/setup/refresh`,
          return_url: `${appUrl}/wallet/setup/complete`,
          type: 'account_onboarding',
          collect: 'eventually_due',
        })

        return new Response(
          JSON.stringify({
            success: false,
            needs_onboarding: true,
            onboarding_url: accountLink.url,
            message: 'Please complete your account setup to enable withdrawals.',
            withdrawable_cents: withdrawableCents,
          }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      } catch (linkError) {
        console.error('Failed to create account link:', linkError)

        const loginLink = await stripe.accounts.createLoginLink(accountId)
        return new Response(
          JSON.stringify({
            success: false,
            needs_onboarding: true,
            onboarding_url: loginLink.url,
            message: 'Please complete your account setup in Stripe to enable withdrawals.',
            withdrawable_cents: withdrawableCents,
          }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    // Create transfer from platform to user's Express account
    const transfer = await stripe.transfers.create({
      amount: withdrawableCents,
      currency: 'usd',
      destination: accountId,
      description: 'Tickety referral earnings withdrawal',
      metadata: {
        supabase_user_id: user.id,
        platform: 'tickety',
        type: 'referral_earnings',
      },
    })

    console.log(`Created transfer ${transfer.id} for user ${user.id}: ${withdrawableCents} cents`)

    // Mark earnings as paid (FIFO)
    const { data: rowsUpdated, error: markError } = await supabaseAdmin.rpc(
      'mark_referral_earnings_paid',
      { p_user_id: user.id, p_amount_cents: withdrawableCents }
    )

    if (markError) {
      console.error('Failed to mark earnings as paid:', markError)
      // Transfer already succeeded — log but don't fail
    } else {
      console.log(`Marked ${rowsUpdated} referral earning rows as paid`)
    }

    // Fetch updated balance
    const { data: newBalance } = await supabaseAdmin.rpc(
      'get_referral_balance',
      { p_user_id: user.id }
    )
    const updated = newBalance?.[0] || newBalance

    return new Response(
      JSON.stringify({
        success: true,
        needs_onboarding: false,
        transfer_id: transfer.id,
        amount_cents: withdrawableCents,
        remaining_withdrawable_cents: Number(updated?.withdrawable_cents || 0),
        total_cents: Number(updated?.total_cents || 0),
        paid_cents: Number(updated?.paid_cents || 0),
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error withdrawing referral earnings:', error)

    if (error.type === 'StripeInvalidRequestError') {
      return new Response(
        JSON.stringify({ error: 'Unable to process withdrawal. Please try again later.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({ error: error.message || 'Failed to withdraw earnings' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
