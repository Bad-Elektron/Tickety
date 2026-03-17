import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const seatgeekClientId = Deno.env.get('SEATGEEK_CLIENT_ID')!
const supabase = createClient(supabaseUrl, supabaseServiceKey)

const SG_BASE = 'https://api.seatgeek.com/2/events'

const CATEGORY_MAP: Record<string, string> = {
  'concert': 'Music',
  'music_festival': 'Music',
  'sports': 'Sports',
  'nfl': 'Sports',
  'nba': 'Sports',
  'mlb': 'Sports',
  'nhl': 'Sports',
  'mls': 'Sports',
  'ncaa_football': 'Sports',
  'ncaa_basketball': 'Sports',
  'theater': 'Theater',
  'broadway_tickets_national': 'Theater',
  'comedy': 'Entertainment',
  'family': 'Entertainment',
  'cirque_du_soleil': 'Entertainment',
}

const SYNC_LOCATIONS = [
  { lat: 40.7128, lng: -74.0060, name: 'New York' },
  { lat: 34.0522, lng: -118.2437, name: 'Los Angeles' },
  { lat: 41.8781, lng: -87.6298, name: 'Chicago' },
  { lat: 29.7604, lng: -95.3698, name: 'Houston' },
  { lat: 33.4484, lng: -112.0740, name: 'Phoenix' },
]

serve(async (req) => {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }

  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders })
  }

  try {
    let locations = SYNC_LOCATIONS
    let maxPages = 3
    let radiusMiles = 75

    try {
      const body = await req.json()
      if (body.lat && body.lng) locations = [{ lat: body.lat, lng: body.lng, name: 'custom' }]
      if (body.max_pages) maxPages = Math.min(body.max_pages, 5)
      if (body.radius) radiusMiles = body.radius
    } catch { /* defaults */ }

    let totalAdded = 0
    let totalSkipped = 0

    for (const loc of locations) {
      console.log(`[seatgeek] Syncing events near ${loc.name}`)

      for (let page = 1; page <= maxPages; page++) {
        const params = new URLSearchParams({
          client_id: seatgeekClientId,
          lat: loc.lat.toString(),
          lon: loc.lng.toString(),
          range: `${radiusMiles}mi`,
          per_page: '200',
          page: page.toString(),
          sort: 'datetime_utc.asc',
          'datetime_utc.gte': new Date().toISOString(),
        })

        const res = await fetch(`${SG_BASE}?${params}`)
        if (!res.ok) {
          console.error(`[seatgeek] API error: ${res.status}`)
          break
        }

        const data = await res.json()
        const events = data?.events
        if (!events || events.length === 0) break

        console.log(`[seatgeek] Processing ${events.length} events from page ${page}`)

        const rows: Record<string, any>[] = []

        for (const e of events) {
          const mapped = mapSeatGeekEvent(e)
          if (!mapped) continue

          // Deduplication: check if this event exists from another source
          const { data: dup } = await supabase.rpc('find_duplicate_external_event', {
            p_source: 'seatgeek',
            p_title: mapped.title,
            p_venue_name: mapped.venue_name || '',
            p_start_date: mapped.start_date,
          })

          if (dup) {
            totalSkipped++
            continue
          }

          rows.push(mapped)
        }

        if (rows.length > 0) {
          const { data: upserted, error } = await supabase
            .from('external_events')
            .upsert(rows, { onConflict: 'source,external_id', ignoreDuplicates: false })
            .select('id')

          if (error) {
            console.error(`[seatgeek] Upsert error:`, error.message)
          } else {
            totalAdded += upserted?.length ?? 0
          }
        }

        if (events.length < 200) break
        await new Promise(r => setTimeout(r, 200))
      }
    }

    await supabase.from('external_event_sync_log').insert({
      source: 'seatgeek',
      events_added: totalAdded,
      events_removed: totalSkipped,
    })

    console.log(`[seatgeek] Sync complete: ${totalAdded} upserted, ${totalSkipped} deduped`)

    return new Response(
      JSON.stringify({ success: true, events_upserted: totalAdded, events_deduped: totalSkipped }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('[seatgeek] Sync failed:', err)
    await supabase.from('external_event_sync_log').insert({
      source: 'seatgeek',
      error_message: err.message || String(err),
    })
    return new Response(
      JSON.stringify({ error: 'Sync failed' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

function mapSeatGeekEvent(e: any): Record<string, any> | null {
  try {
    const id = e.id?.toString()
    const title = e.title || e.short_title
    if (!id || !title) return null

    const startDate = e.datetime_utc
    if (!startDate) return null

    const venue = e.venue
    const performer = e.performers?.[0]

    // Category mapping
    const sgType = e.type || ''
    let category: string | null = null
    for (const [key, val] of Object.entries(CATEGORY_MAP)) {
      if (sgType.toLowerCase().includes(key)) {
        category = val
        break
      }
    }
    if (!category) category = 'Entertainment'

    // Price
    let priceMin: number | null = null
    let priceMax: number | null = null
    if (e.stats?.lowest_price) priceMin = Math.round(e.stats.lowest_price * 100)
    if (e.stats?.highest_price) priceMax = Math.round(e.stats.highest_price * 100)

    return {
      source: 'seatgeek',
      external_id: id,
      title,
      description: e.description || null,
      start_date: startDate,
      end_date: e.datetime_utc_end || null,
      venue_name: venue?.name || null,
      venue_address: venue?.display_location || venue?.address || null,
      lat: venue?.location?.lat || null,
      lng: venue?.location?.lon || null,
      image_url: performer?.image || e.performers?.[1]?.image || null,
      category,
      genre: e.taxonomies?.[0]?.name || null,
      price_range_min: priceMin,
      price_range_max: priceMax,
      ticket_url: e.url || `https://seatgeek.com/e/${id}`,
      source_updated_at: new Date().toISOString(),
      is_active: true,
      updated_at: new Date().toISOString(),
    }
  } catch {
    return null
  }
}
