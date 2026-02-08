import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const devMode = Deno.env.get('DEV_MODE')

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface OverrideRequest {
  tier: 'base' | 'pro' | 'enterprise'
  status?: string
  cancel_at_period_end?: boolean
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Guard: only available when DEV_MODE is explicitly enabled
    if (devMode !== 'true') {
      return new Response(
        JSON.stringify({ error: 'Dev mode is not enabled' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
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

    const body: OverrideRequest = await req.json()
    const { tier, status, cancel_at_period_end } = body

    if (!tier || !['base', 'pro', 'enterprise'].includes(tier)) {
      return new Response(
        JSON.stringify({ error: 'Invalid tier. Must be "base", "pro", or "enterprise"' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`[DEV] Overriding subscription for user ${user.id} to tier: ${tier}`)

    // Build the update payload
    const updateData: Record<string, unknown> = {
      tier,
      status: status || 'active',
      cancel_at_period_end: cancel_at_period_end ?? false,
      updated_at: new Date().toISOString(),
    }

    // Clear Stripe fields when switching to base (no real subscription)
    if (tier === 'base') {
      updateData.stripe_subscription_id = null
      updateData.stripe_price_id = null
    }

    // Upsert: update if exists, insert if not
    const { data: existing } = await supabaseAdmin
      .from('subscriptions')
      .select('id')
      .eq('user_id', user.id)
      .maybeSingle()

    let result
    if (existing) {
      // Update existing subscription
      const { data, error } = await supabaseAdmin
        .from('subscriptions')
        .update(updateData)
        .eq('user_id', user.id)
        .select()
        .single()

      if (error) {
        console.error('Failed to update subscription:', error)
        return new Response(
          JSON.stringify({ error: `Failed to update subscription: ${error.message}` }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      result = data
    } else {
      // Insert new subscription
      const { data, error } = await supabaseAdmin
        .from('subscriptions')
        .insert({
          user_id: user.id,
          ...updateData,
          created_at: new Date().toISOString(),
        })
        .select()
        .single()

      if (error) {
        console.error('Failed to create subscription:', error)
        return new Response(
          JSON.stringify({ error: `Failed to create subscription: ${error.message}` }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      result = data
    }

    console.log(`[DEV] Subscription overridden successfully:`, result)

    return new Response(
      JSON.stringify({ subscription: result }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error in dev-override-subscription:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
