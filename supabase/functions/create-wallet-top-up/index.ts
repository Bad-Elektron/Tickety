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

// ACH fee: 0.8% capped at $5
function calculateAchFee(amountCents: number): number {
  return Math.min(Math.ceil(amountCents * 0.008), 500)
}

const MIN_TOP_UP_CENTS = 500  // $5 minimum
const MAX_TOP_UP_CENTS = 200000  // $2,000 maximum

interface TopUpRequest {
  amount_cents: number
  payment_method_id: string
}

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

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)
    const body: TopUpRequest = await req.json()
    const { amount_cents, payment_method_id } = body

    // Validate amount
    if (!amount_cents || amount_cents < MIN_TOP_UP_CENTS) {
      return new Response(
        JSON.stringify({ error: `Minimum top-up is $${(MIN_TOP_UP_CENTS / 100).toFixed(2)}` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (amount_cents > MAX_TOP_UP_CENTS) {
      return new Response(
        JSON.stringify({ error: `Maximum top-up is $${(MAX_TOP_UP_CENTS / 100).toFixed(2)}` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!payment_method_id) {
      return new Response(
        JSON.stringify({ error: 'Missing payment_method_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify the bank account belongs to this user
    const { data: bankAccount } = await supabaseAdmin
      .from('linked_bank_accounts')
      .select('*')
      .eq('user_id', user.id)
      .eq('stripe_payment_method_id', payment_method_id)
      .eq('status', 'active')
      .maybeSingle()

    if (!bankAccount) {
      return new Response(
        JSON.stringify({ error: 'Bank account not found or not active' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Calculate fees
    const achFeeCents = calculateAchFee(amount_cents)
    const totalChargeCents = amount_cents + achFeeCents
    const creditAmountCents = amount_cents  // User gets the full amount they requested

    // Get Stripe customer ID
    const { data: profile } = await supabaseAdmin
      .from('profiles')
      .select('stripe_customer_id')
      .eq('id', user.id)
      .single()

    if (!profile?.stripe_customer_id) {
      return new Response(
        JSON.stringify({ error: 'Stripe customer not found. Please link a bank account first.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Create PaymentIntent for ACH debit
    const paymentIntent = await stripe.paymentIntents.create({
      amount: totalChargeCents,
      currency: 'usd',
      customer: profile.stripe_customer_id,
      payment_method: payment_method_id,
      payment_method_types: ['us_bank_account'],
      confirm: true,
      mandate_data: {
        customer_acceptance: {
          type: 'online',
          online: {
            ip_address: req.headers.get('x-forwarded-for') || '0.0.0.0',
            user_agent: req.headers.get('user-agent') || 'Tickety App',
          },
        },
      },
      metadata: {
        supabase_user_id: user.id,
        type: 'wallet_top_up',
        credit_amount_cents: String(creditAmountCents),
        ach_fee_cents: String(achFeeCents),
      },
    })

    console.log(`ACH top-up PaymentIntent created: ${paymentIntent.id}, status: ${paymentIntent.status}`)

    // Ensure wallet exists
    const { data: existingWallet } = await supabaseAdmin
      .from('wallet_balances')
      .select('id')
      .eq('user_id', user.id)
      .maybeSingle()

    if (!existingWallet) {
      await supabaseAdmin
        .from('wallet_balances')
        .insert({ user_id: user.id })
    }

    // Add to pending_cents (funds are in-flight until ACH settles)
    await supabaseAdmin
      .from('wallet_balances')
      .update({
        pending_cents: supabaseAdmin.rpc ? undefined : 0, // will use raw SQL below
      })
      .eq('user_id', user.id)

    // Use RPC-style update for atomic increment
    await supabaseAdmin.rpc('increment_wallet_pending', {
      p_user_id: user.id,
      p_amount: creditAmountCents,
    }).catch(async () => {
      // Fallback: direct update if RPC doesn't exist yet
      const { data: wallet } = await supabaseAdmin
        .from('wallet_balances')
        .select('pending_cents')
        .eq('user_id', user.id)
        .single()

      await supabaseAdmin
        .from('wallet_balances')
        .update({ pending_cents: (wallet?.pending_cents || 0) + creditAmountCents })
        .eq('user_id', user.id)
    })

    // Create pending wallet transaction
    const { data: wallet } = await supabaseAdmin
      .from('wallet_balances')
      .select('pending_cents')
      .eq('user_id', user.id)
      .single()

    await supabaseAdmin
      .from('wallet_transactions')
      .insert({
        user_id: user.id,
        type: 'ach_top_up_pending',
        amount_cents: creditAmountCents,
        fee_cents: achFeeCents,
        balance_after_cents: 0, // Pending — not yet in available balance
        stripe_payment_intent_id: paymentIntent.id,
        description: `ACH top-up of $${(creditAmountCents / 100).toFixed(2)} (processing)`,
      })

    // Create payment record
    await supabaseAdmin
      .from('payments')
      .insert({
        user_id: user.id,
        amount_cents: totalChargeCents,
        platform_fee_cents: achFeeCents,
        currency: 'usd',
        status: 'processing',
        type: 'wallet_top_up',
        stripe_payment_intent_id: paymentIntent.id,
        metadata: {
          credit_amount_cents: creditAmountCents,
          ach_fee_cents: achFeeCents,
          bank_name: bankAccount.bank_name,
          bank_last4: bankAccount.last4,
        },
      })

    return new Response(
      JSON.stringify({
        payment_intent_id: paymentIntent.id,
        status: paymentIntent.status,
        credit_amount_cents: creditAmountCents,
        ach_fee_cents: achFeeCents,
        total_charge_cents: totalChargeCents,
        pending_cents: wallet?.pending_cents || creditAmountCents,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error creating wallet top-up:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
