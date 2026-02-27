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
    // Use service role key to bypass RLS — the function is SECURITY DEFINER
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    const { error } = await supabase.rpc('refresh_analytics_cache')

    if (error) {
      console.error('Failed to refresh analytics cache:', error)
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log('Analytics cache refreshed successfully')

    // Fire-and-forget: chain-call market analytics refresh
    try {
      const marketUrl = `${supabaseUrl}/functions/v1/refresh-market-analytics`
      fetch(marketUrl, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${supabaseServiceKey}`,
          'Content-Type': 'application/json',
        },
      }).then((res) => {
        console.log(`Market analytics refresh triggered: ${res.status}`)
      }).catch((err) => {
        console.error('Failed to trigger market analytics refresh:', err)
      })
    } catch (err) {
      console.error('Error triggering market analytics refresh:', err)
    }

    return new Response(
      JSON.stringify({ ok: true, refreshed_at: new Date().toISOString() }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('Unexpected error refreshing analytics cache:', err)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
