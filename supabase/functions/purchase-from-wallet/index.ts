import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Wallet fee: 5% platform fee only (no Stripe processing fee)
const WALLET_PLATFORM_FEE_RATE = 0.05

interface WalletPurchaseRequest {
  event_id: string
  quantity: number
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
    const body: WalletPurchaseRequest = await req.json()
    const { event_id, quantity = 1 } = body

    if (!event_id) {
      return new Response(
        JSON.stringify({ error: 'Missing event_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (quantity < 1 || quantity > 10) {
      return new Response(
        JSON.stringify({ error: 'Quantity must be between 1 and 10' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify event exists and is active
    const { data: event, error: eventError } = await supabaseAdmin
      .from('events')
      .select('id, title, price_in_cents, status')
      .eq('id', event_id)
      .single()

    if (eventError || !event) {
      return new Response(
        JSON.stringify({ error: 'Event not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (event.status !== 'active') {
      return new Response(
        JSON.stringify({ error: 'Event is not available for purchase' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!event.price_in_cents || event.price_in_cents <= 0) {
      return new Response(
        JSON.stringify({ error: 'Free events do not require wallet payment' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Calculate fees: 5% platform fee only
    const baseCents = event.price_in_cents * quantity
    const platformFeeCents = Math.ceil(baseCents * WALLET_PLATFORM_FEE_RATE)
    const totalDebitCents = baseCents + platformFeeCents

    // Call atomic purchase function
    const { data: result, error: purchaseError } = await supabaseAdmin.rpc(
      'purchase_from_wallet',
      {
        p_user_id: user.id,
        p_event_id: event_id,
        p_quantity: quantity,
        p_unit_price_cents: event.price_in_cents,
        p_platform_fee_cents: platformFeeCents,
        p_total_debit_cents: totalDebitCents,
        p_event_title: event.title,
      }
    )

    if (purchaseError) {
      console.error('Wallet purchase failed:', purchaseError)

      // Parse known error messages
      const msg = purchaseError.message || ''
      if (msg.includes('Insufficient wallet balance')) {
        return new Response(
          JSON.stringify({ error: 'Insufficient wallet balance' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      if (msg.includes('Wallet not found')) {
        return new Response(
          JSON.stringify({ error: 'Wallet not found. Please add funds first.' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      return new Response(
        JSON.stringify({ error: 'Purchase failed. Please try again.' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Wallet purchase completed for user ${user.id}:`, result)

    return new Response(
      JSON.stringify({
        payment_id: result.payment_id,
        ticket_ids: result.ticket_ids,
        new_balance_cents: result.new_balance_cents,
        tickets_created: result.tickets_created,
        total_charged_cents: totalDebitCents,
        platform_fee_cents: platformFeeCents,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error processing wallet purchase:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
