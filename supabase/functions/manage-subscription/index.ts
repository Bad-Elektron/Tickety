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
  action: 'cancel' | 'resume'
  user_id: string
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

    if (!action || !['cancel', 'resume'].includes(action)) {
      return new Response(
        JSON.stringify({ error: 'Invalid action. Must be "cancel" or "resume"' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get the user's subscription
    const { data: subscription, error: subError } = await supabaseAdmin
      .from('subscriptions')
      .select('*')
      .eq('user_id', user.id)
      .single()

    if (subError || !subscription) {
      return new Response(
        JSON.stringify({ error: 'No subscription found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!subscription.stripe_subscription_id) {
      return new Response(
        JSON.stringify({ error: 'No Stripe subscription linked' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (action === 'cancel') {
      console.log('Canceling subscription:', subscription.stripe_subscription_id)

      // Cancel at period end (don't immediately revoke access)
      const updated = await stripe.subscriptions.update(
        subscription.stripe_subscription_id,
        { cancel_at_period_end: true }
      )

      // Update database
      const { error: updateError } = await supabaseAdmin
        .from('subscriptions')
        .update({
          cancel_at_period_end: true,
          updated_at: new Date().toISOString(),
        })
        .eq('user_id', user.id)

      if (updateError) {
        console.error('Failed to update subscription in DB:', updateError)
      }

      // Return updated subscription
      const { data: updatedSub } = await supabaseAdmin
        .from('subscriptions')
        .select('*')
        .eq('user_id', user.id)
        .single()

      console.log('Subscription canceled at period end')

      return new Response(
        JSON.stringify({ subscription: updatedSub }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )

    } else if (action === 'resume') {
      console.log('Resuming subscription:', subscription.stripe_subscription_id)

      // Remove cancel_at_period_end
      const updated = await stripe.subscriptions.update(
        subscription.stripe_subscription_id,
        { cancel_at_period_end: false }
      )

      // Update database
      const { error: updateError } = await supabaseAdmin
        .from('subscriptions')
        .update({
          cancel_at_period_end: false,
          updated_at: new Date().toISOString(),
        })
        .eq('user_id', user.id)

      if (updateError) {
        console.error('Failed to update subscription in DB:', updateError)
      }

      // Return updated subscription
      const { data: updatedSub } = await supabaseAdmin
        .from('subscriptions')
        .select('*')
        .eq('user_id', user.id)
        .single()

      console.log('Subscription resumed')

      return new Response(
        JSON.stringify({ subscription: updatedSub }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({ error: 'Unknown action' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error managing subscription:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
