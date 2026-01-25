import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import Stripe from 'https://esm.sh/stripe@13.10.0?target=deno'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
})

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const appUrl = Deno.env.get('APP_URL') || 'https://tickety.app'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

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

    // Check if user already has a Connect account
    const { data: profile } = await supabaseAdmin
      .from('profiles')
      .select('stripe_connect_account_id, email, full_name')
      .eq('id', user.id)
      .single()

    let accountId = profile?.stripe_connect_account_id

    if (!accountId) {
      // Create new Stripe Connect Express account
      const account = await stripe.accounts.create({
        type: 'express',
        email: user.email,
        metadata: {
          supabase_user_id: user.id,
        },
        capabilities: {
          card_payments: { requested: true },
          transfers: { requested: true },
        },
        business_type: 'individual',
        business_profile: {
          product_description: 'Ticket resale on Tickety platform',
        },
      })

      accountId = account.id

      // Save Connect account ID to profile
      await supabaseAdmin
        .from('profiles')
        .update({ stripe_connect_account_id: accountId })
        .eq('id', user.id)

      console.log(`Created Connect account ${accountId} for user ${user.id}`)
    }

    // Create account link for onboarding
    const accountLink = await stripe.accountLinks.create({
      account: accountId,
      refresh_url: `${appUrl}/seller/onboarding/refresh`,
      return_url: `${appUrl}/seller/onboarding/complete`,
      type: 'account_onboarding',
    })

    console.log(`Generated onboarding link for account ${accountId}`)

    return new Response(
      JSON.stringify({
        account_id: accountId,
        onboarding_url: accountLink.url,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )

  } catch (error) {
    console.error('Error creating Connect account:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Failed to create seller account' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
