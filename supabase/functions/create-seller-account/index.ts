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
 * Creates a minimal Stripe Express account for sellers.
 *
 * This allows sellers to list tickets WITHOUT completing full Stripe onboarding.
 * Funds from sales are held in their Stripe Express account balance.
 * When they want to withdraw, they complete bank setup at that time.
 *
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

    // Check if user already has a seller balance record
    const { data: existingBalance } = await supabaseAdmin
      .from('seller_balances')
      .select('stripe_account_id')
      .eq('user_id', user.id)
      .single()

    if (existingBalance?.stripe_account_id) {
      console.log(`User ${user.id} already has seller account: ${existingBalance.stripe_account_id}`)

      // Return existing account info
      return new Response(
        JSON.stringify({
          account_id: existingBalance.stripe_account_id,
          already_exists: true,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    // Also check the legacy field in profiles (from old flow)
    const { data: profile } = await supabaseAdmin
      .from('profiles')
      .select('stripe_connect_account_id, email, display_name')
      .eq('id', user.id)
      .single()

    if (profile?.stripe_connect_account_id) {
      console.log(`User ${user.id} has legacy Connect account: ${profile.stripe_connect_account_id}`)

      // Migrate to seller_balances table
      const { error: insertError } = await supabaseAdmin
        .from('seller_balances')
        .insert({
          user_id: user.id,
          stripe_account_id: profile.stripe_connect_account_id,
          payouts_enabled: false, // Will be updated on next balance fetch
          details_submitted: false,
        })

      if (insertError && insertError.code !== '23505') { // Ignore duplicate key errors
        console.error('Failed to migrate legacy account:', insertError)
      }

      return new Response(
        JSON.stringify({
          account_id: profile.stripe_connect_account_id,
          already_exists: true,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    // Create new Stripe Connect Express account with minimal requirements
    // Stripe Express accounts can receive payments immediately, but need
    // identity verification and bank details to withdraw
    const account = await stripe.accounts.create({
      type: 'express',
      email: user.email,
      metadata: {
        supabase_user_id: user.id,
        platform: 'tickety',
      },
      capabilities: {
        card_payments: { requested: true },
        transfers: { requested: true },
      },
      business_type: 'individual',
      business_profile: {
        product_description: 'Ticket resale on Tickety marketplace',
        mcc: '7922', // Theatrical producers and ticket agencies
      },
      settings: {
        payouts: {
          // Disable automatic payouts - seller must request withdrawal
          schedule: {
            interval: 'manual',
          },
        },
      },
    })

    console.log(`Created Stripe Express account ${account.id} for user ${user.id}`)

    // Create seller_balances record
    const { error: insertError } = await supabaseAdmin
      .from('seller_balances')
      .insert({
        user_id: user.id,
        stripe_account_id: account.id,
        available_balance_cents: 0,
        pending_balance_cents: 0,
        payouts_enabled: false,
        details_submitted: false,
      })

    if (insertError) {
      console.error('Failed to create seller_balances record:', insertError)
      // Don't fail the request - the Stripe account was created successfully
    }

    // Also update the legacy profiles field for backwards compatibility
    await supabaseAdmin
      .from('profiles')
      .update({ stripe_connect_account_id: account.id })
      .eq('id', user.id)

    return new Response(
      JSON.stringify({
        account_id: account.id,
        already_exists: false,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )

  } catch (error) {
    console.error('Error creating seller account:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Failed to create seller account' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
