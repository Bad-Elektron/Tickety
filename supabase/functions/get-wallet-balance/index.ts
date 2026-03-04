import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
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

    // Get or create wallet balance
    let { data: wallet } = await supabaseAdmin
      .from('wallet_balances')
      .select('*')
      .eq('user_id', user.id)
      .maybeSingle()

    if (!wallet) {
      // Create wallet on first access
      const { data: newWallet, error: createError } = await supabaseAdmin
        .from('wallet_balances')
        .insert({ user_id: user.id })
        .select()
        .single()

      if (createError) {
        console.error('Failed to create wallet:', createError)
        return new Response(
          JSON.stringify({ error: 'Failed to create wallet' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      wallet = newWallet
    }

    // Get linked bank accounts
    const { data: bankAccounts } = await supabaseAdmin
      .from('linked_bank_accounts')
      .select('*')
      .eq('user_id', user.id)
      .eq('status', 'active')
      .order('is_default', { ascending: false })
      .order('created_at', { ascending: false })

    return new Response(
      JSON.stringify({
        available_cents: wallet.available_cents,
        pending_cents: wallet.pending_cents,
        currency: wallet.currency,
        bank_accounts: bankAccounts || [],
        has_linked_bank: (bankAccounts?.length || 0) > 0,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error getting wallet balance:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
