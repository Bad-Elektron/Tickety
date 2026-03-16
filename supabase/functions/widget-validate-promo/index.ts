import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const supabase = createClient(supabaseUrl, supabaseServiceKey)

serve(async (req) => {
  const requestOrigin = req.headers.get('origin') || '*'
  const corsHeaders: Record<string, string> = {
    'Access-Control-Allow-Origin': requestOrigin,
    'Access-Control-Allow-Headers': 'content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  }

  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders })
  }

  try {
    const { widget_key, event_id, code, base_price_cents } = await req.json()

    if (!widget_key || !event_id || !code || !base_price_cents) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate widget key
    const encoder = new TextEncoder()
    const data = encoder.encode(widget_key)
    const hashBuffer = await crypto.subtle.digest('SHA-256', data)
    const hashArray = Array.from(new Uint8Array(hashBuffer))
    const keyHash = hashArray.map(b => b.toString(16).padStart(2, '0')).join('')

    const { data: keyRecord } = await supabase
      .from('widget_api_keys')
      .select('id, is_active')
      .eq('key_hash', keyHash)
      .single()

    if (!keyRecord?.is_active) {
      return new Response(
        JSON.stringify({ error: 'Invalid widget key' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate promo code (no user-specific checks for guest checkout)
    const { data: result, error } = await supabase.rpc('validate_promo_code', {
      p_event_id: event_id,
      p_code: code,
      p_user_id: null,
      p_base_price_cents: base_price_cents,
      p_ticket_type_id: null,
    })

    if (error) {
      return new Response(
        JSON.stringify({ valid: false, error: 'Failed to validate code' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({
        valid: result?.valid ?? false,
        discount_cents: result?.discount_cents ?? 0,
        discount_type: result?.discount_type,
        error: result?.error,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('widget-validate-promo error:', err)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
