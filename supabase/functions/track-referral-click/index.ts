import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Simple in-memory rate limit (per IP, 10 clicks/min)
const rateLimitMap = new Map<string, { count: number; resetAt: number }>()

function checkRateLimit(ip: string): boolean {
  const now = Date.now()
  const entry = rateLimitMap.get(ip)

  if (!entry || now > entry.resetAt) {
    rateLimitMap.set(ip, { count: 1, resetAt: now + 60_000 })
    return true
  }

  if (entry.count >= 10) {
    return false
  }

  entry.count++
  return true
}

/**
 * Tracks a referral link click. Public endpoint (no auth required).
 *
 * Body: { referral_code: string, channel: string }
 *
 * Upserts referral_channels and increments click_count.
 * Rate-limited by IP (10 clicks/minute).
 */
serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Rate limit by IP
    const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()
      || req.headers.get('cf-connecting-ip')
      || 'unknown'

    if (!checkRateLimit(ip)) {
      return new Response(
        JSON.stringify({ error: 'Rate limited. Please try again later.' }),
        { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const body = await req.json()
    const { referral_code, channel } = body

    if (!referral_code || typeof referral_code !== 'string') {
      return new Response(
        JSON.stringify({ error: 'referral_code is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!channel || typeof channel !== 'string') {
      return new Response(
        JSON.stringify({ error: 'channel is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const validChannels = ['instagram', 'youtube', 'tiktok', 'twitter', 'email', 'website', 'other']
    const normalizedChannel = channel.toLowerCase().trim()

    if (!validChannels.includes(normalizedChannel)) {
      return new Response(
        JSON.stringify({ error: 'Invalid channel. Valid: ' + validChannels.join(', ') }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

    // Look up the referrer by code
    const { data: profile, error: profileError } = await supabaseAdmin
      .from('profiles')
      .select('id')
      .eq('referral_code', referral_code.toUpperCase())
      .maybeSingle()

    if (profileError || !profile) {
      return new Response(
        JSON.stringify({ error: 'Invalid referral code' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Upsert channel record and increment click_count via RPC
    const { error: rpcError } = await supabaseAdmin.rpc('increment_referral_click', {
      p_user_id: profile.id,
      p_channel: normalizedChannel,
    })

    if (rpcError) {
      console.error('Failed to increment referral click:', rpcError)
      return new Response(
        JSON.stringify({ error: 'Failed to record click' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Tracked referral click: code=${referral_code}, channel=${normalizedChannel}`)

    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error tracking referral click:', error)
    return new Response(
      JSON.stringify({ error: 'Failed to track click' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
