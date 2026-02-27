import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const ticketmasterKey = Deno.env.get('TICKETMASTER_API_KEY') ?? ''
const seatgeekClientId = Deno.env.get('SEATGEEK_CLIENT_ID') ?? ''

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// ── Tag → API query mapping ──────────────────────────────────

interface TagMapping {
  tagId: string
  tm: { param: string; value: string } // Ticketmaster query param
  sg: { param: string; value: string } // SeatGeek query param
}

const TAG_MAPPINGS: TagMapping[] = [
  {
    tagId: 'live_music',
    tm: { param: 'classificationName', value: 'Music' },
    sg: { param: 'taxonomies.name', value: 'concert' },
  },
  {
    tagId: 'dj',
    tm: { param: 'keyword', value: 'DJ Electronic' },
    sg: { param: 'q', value: 'dj electronic' },
  },
  {
    tagId: 'nightlife',
    tm: { param: 'keyword', value: 'Nightlife Club' },
    sg: { param: 'q', value: 'nightlife club' },
  },
  {
    tagId: 'outdoor',
    tm: { param: 'keyword', value: 'Outdoor Festival' },
    sg: { param: 'q', value: 'outdoor festival' },
  },
  {
    tagId: 'food',
    tm: { param: 'keyword', value: 'Food' },
    sg: { param: 'q', value: 'food' },
  },
  {
    tagId: 'drinks',
    tm: { param: 'keyword', value: 'Drinks Wine Beer' },
    sg: { param: 'q', value: 'drinks' },
  },
  {
    tagId: 'networking',
    tm: { param: 'keyword', value: 'Networking Business Conference' },
    sg: { param: 'q', value: 'networking business' },
  },
  {
    tagId: 'workshop',
    tm: { param: 'keyword', value: 'Workshop Class' },
    sg: { param: 'q', value: 'workshop' },
  },
  {
    tagId: 'family_friendly',
    tm: { param: 'classificationName', value: 'Family' },
    sg: { param: 'taxonomies.name', value: 'family' },
  },
]

// ── Ticketmaster helpers ─────────────────────────────────────

interface SnapshotRow {
  tag_id: string
  source: 'ticketmaster' | 'seatgeek'
  event_count: number | null
  avg_price_cents: number | null
  min_price_cents: number | null
  max_price_cents: number | null
  fetched_at: string
  error_message: string | null
}

const delay = (ms: number) => new Promise((r) => setTimeout(r, ms))

async function fetchTicketmaster(mapping: TagMapping): Promise<SnapshotRow> {
  const now = new Date().toISOString()
  const base: SnapshotRow = {
    tag_id: mapping.tagId,
    source: 'ticketmaster',
    event_count: null,
    avg_price_cents: null,
    min_price_cents: null,
    max_price_cents: null,
    fetched_at: now,
    error_message: null,
  }

  if (!ticketmasterKey) {
    return { ...base, error_message: 'TICKETMASTER_API_KEY not configured' }
  }

  try {
    const url = new URL('https://app.ticketmaster.com/discovery/v2/events.json')
    url.searchParams.set('apikey', ticketmasterKey)
    url.searchParams.set('countryCode', 'US')
    url.searchParams.set('size', '200')
    url.searchParams.set(mapping.tm.param, mapping.tm.value)

    const resp = await fetch(url.toString())
    if (!resp.ok) {
      return { ...base, error_message: `TM HTTP ${resp.status}` }
    }

    const data = await resp.json()
    const totalElements: number = data?.page?.totalElements ?? 0
    base.event_count = totalElements

    // Extract pricing from embedded events
    const events = data?._embedded?.events ?? []
    const prices: number[] = []
    for (const ev of events) {
      for (const pr of ev.priceRanges ?? []) {
        if (pr.min != null) prices.push(pr.min)
        if (pr.max != null) prices.push(pr.max)
      }
    }

    if (prices.length > 0) {
      const sum = prices.reduce((a: number, b: number) => a + b, 0)
      base.avg_price_cents = Math.round((sum / prices.length) * 100)
      base.min_price_cents = Math.round(Math.min(...prices) * 100)
      base.max_price_cents = Math.round(Math.max(...prices) * 100)
    }

    return base
  } catch (err) {
    return { ...base, error_message: `TM error: ${(err as Error).message}` }
  }
}

// ── SeatGeek helpers ─────────────────────────────────────────

async function fetchSeatGeek(mapping: TagMapping): Promise<SnapshotRow> {
  const now = new Date().toISOString()
  const base: SnapshotRow = {
    tag_id: mapping.tagId,
    source: 'seatgeek',
    event_count: null,
    avg_price_cents: null,
    min_price_cents: null,
    max_price_cents: null,
    fetched_at: now,
    error_message: null,
  }

  if (!seatgeekClientId) {
    return { ...base, error_message: 'SEATGEEK_CLIENT_ID not configured' }
  }

  try {
    const url = new URL('https://api.seatgeek.com/2/events')
    url.searchParams.set('client_id', seatgeekClientId)
    url.searchParams.set('per_page', '50')
    url.searchParams.set(mapping.sg.param, mapping.sg.value)

    const resp = await fetch(url.toString())
    if (!resp.ok) {
      return { ...base, error_message: `SG HTTP ${resp.status}` }
    }

    const data = await resp.json()
    base.event_count = data?.meta?.total ?? 0

    // Extract pricing from stats
    const events = data?.events ?? []
    const avgPrices: number[] = []
    const lowPrices: number[] = []
    const highPrices: number[] = []

    for (const ev of events) {
      const stats = ev.stats
      if (!stats) continue
      if (stats.average_price != null && stats.average_price > 0) {
        avgPrices.push(stats.average_price)
      }
      if (stats.lowest_price != null && stats.lowest_price > 0) {
        lowPrices.push(stats.lowest_price)
      }
      if (stats.highest_price != null && stats.highest_price > 0) {
        highPrices.push(stats.highest_price)
      }
    }

    if (avgPrices.length > 0) {
      const sum = avgPrices.reduce((a: number, b: number) => a + b, 0)
      base.avg_price_cents = Math.round((sum / avgPrices.length) * 100)
    }
    if (lowPrices.length > 0) {
      base.min_price_cents = Math.round(Math.min(...lowPrices) * 100)
    }
    if (highPrices.length > 0) {
      base.max_price_cents = Math.round(Math.max(...highPrices) * 100)
    }

    return base
  } catch (err) {
    return { ...base, error_message: `SG error: ${(err as Error).message}` }
  }
}

// ── Main handler ─────────────────────────────────────────────

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createClient(supabaseUrl, supabaseServiceKey)
    const results: SnapshotRow[] = []
    let successCount = 0
    let errorCount = 0

    // ── Ticketmaster: sequential with 600ms delay (rate limit ~2/sec) ──
    for (const mapping of TAG_MAPPINGS) {
      const row = await fetchTicketmaster(mapping)
      results.push(row)
      if (row.error_message) errorCount++; else successCount++
      // Respect rate limit — wait between calls
      await delay(600)
    }

    // ── SeatGeek: batches of 3 in parallel ──
    for (let i = 0; i < TAG_MAPPINGS.length; i += 3) {
      const batch = TAG_MAPPINGS.slice(i, i + 3)
      const batchResults = await Promise.all(
        batch.map((m) => fetchSeatGeek(m))
      )
      for (const row of batchResults) {
        results.push(row)
        if (row.error_message) errorCount++; else successCount++
      }
    }

    // ── UPSERT all rows ──
    const { error: upsertErr } = await supabase
      .from('analytics_market_snapshot')
      .upsert(results, { onConflict: 'tag_id,source' })

    if (upsertErr) {
      console.error('Failed to upsert market snapshots:', upsertErr)
      return new Response(
        JSON.stringify({ error: upsertErr.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // ── Update meta timestamp ──
    await supabase
      .from('analytics_cache_meta')
      .update({ refreshed_at: new Date().toISOString() })
      .eq('key', 'market_last_refresh')

    console.log(`Market analytics refreshed: ${successCount} ok, ${errorCount} errors`)

    return new Response(
      JSON.stringify({
        ok: true,
        refreshed_at: new Date().toISOString(),
        success_count: successCount,
        error_count: errorCount,
        total: results.length,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('Unexpected error in refresh-market-analytics:', err)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
