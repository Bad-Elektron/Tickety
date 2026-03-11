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

    // Chain: refresh engagement cache (runs after main analytics)
    try {
      const { error: engErr } = await supabase.rpc('refresh_engagement_cache')
      if (engErr) {
        console.error('Failed to refresh engagement cache:', engErr)
      } else {
        console.log('Engagement cache refreshed successfully')
      }
    } catch (err) {
      console.error('Error refreshing engagement cache:', err)
    }

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

    // Fire-and-forget: process any queued NFT burns (enqueued by daily pg_cron)
    try {
      fetch(`${supabaseUrl}/functions/v1/burn-expired-nfts`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${supabaseServiceKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ enqueue: true }),
      }).then((res) => {
        console.log(`NFT burn processing triggered: ${res.status}`)
      }).catch((err) => {
        console.error('Failed to trigger NFT burn processing:', err)
      })
    } catch (err) {
      console.error('Error triggering NFT burn processing:', err)
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
