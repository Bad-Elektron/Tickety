import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const ticketmasterKey = Deno.env.get('TICKETMASTER_API_KEY')!
const supabase = createClient(supabaseUrl, supabaseServiceKey)

const TM_BASE = 'https://app.ticketmaster.com/discovery/v2/events.json'

// Ticketmaster segment -> Tickety category mapping
const CATEGORY_MAP: Record<string, string> = {
  'Music': 'Music',
  'Sports': 'Sports',
  'Arts & Theatre': 'Theater',
  'Film': 'Entertainment',
  'Miscellaneous': 'Entertainment',
}

// Major US cities to sync (lat, lng, radius in miles)
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
    // Optional params to override defaults
    let locations = SYNC_LOCATIONS
    let maxPages = 3
    let radiusMiles = 75

    try {
      const body = await req.json()
      if (body.lat && body.lng) {
        locations = [{ lat: body.lat, lng: body.lng, name: 'custom' }]
      }
      if (body.max_pages) maxPages = Math.min(body.max_pages, 5)
      if (body.radius) radiusMiles = body.radius
    } catch {
      // No body or invalid JSON — use defaults
    }

    let totalAdded = 0
    let totalUpdated = 0

    for (const loc of locations) {
      console.log(`[ticketmaster] Syncing events near ${loc.name} (${loc.lat}, ${loc.lng})`)

      for (let page = 0; page < maxPages; page++) {
        const params = new URLSearchParams({
          apikey: ticketmasterKey,
          latlong: `${loc.lat},${loc.lng}`,
          radius: radiusMiles.toString(),
          unit: 'miles',
          size: '200',
          page: page.toString(),
          sort: 'date,asc',
          startDateTime: new Date().toISOString().replace(/\.\d{3}Z/, 'Z'),
        })

        const res = await fetch(`${TM_BASE}?${params}`)
        if (!res.ok) {
          console.error(`[ticketmaster] API error: ${res.status} ${res.statusText}`)
          break
        }

        const data = await res.json()
        const events = data?._embedded?.events
        if (!events || events.length === 0) {
          console.log(`[ticketmaster] No more events on page ${page} for ${loc.name}`)
          break
        }

        console.log(`[ticketmaster] Processing ${events.length} events from page ${page}`)

        const rows = events.map((e: any) => mapTicketmasterEvent(e)).filter(Boolean)

        if (rows.length > 0) {
          const { data: upserted, error } = await supabase
            .from('external_events')
            .upsert(rows, { onConflict: 'source,external_id', ignoreDuplicates: false })
            .select('id')

          if (error) {
            console.error(`[ticketmaster] Upsert error:`, error.message)
          } else {
            const count = upserted?.length ?? 0
            totalAdded += count
            console.log(`[ticketmaster] Upserted ${count} events from page ${page}`)
          }
        }

        // Respect rate limits
        if (page < maxPages - 1) {
          await new Promise(r => setTimeout(r, 200))
        }

        // If fewer events than page size, no more pages
        if (events.length < 200) break
      }
    }

    // Log sync results
    await supabase.from('external_event_sync_log').insert({
      source: 'ticketmaster',
      events_added: totalAdded,
      events_updated: totalUpdated,
    })

    console.log(`[ticketmaster] Sync complete: ${totalAdded} events upserted`)

    return new Response(
      JSON.stringify({ success: true, events_upserted: totalAdded }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('[ticketmaster] Sync failed:', err)

    await supabase.from('external_event_sync_log').insert({
      source: 'ticketmaster',
      error_message: err.message || String(err),
    })

    return new Response(
      JSON.stringify({ error: 'Sync failed', details: err.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

function mapTicketmasterEvent(e: any): Record<string, any> | null {
  try {
    const id = e.id
    const title = e.name
    if (!id || !title) return null

    const startDate = e.dates?.start?.dateTime
    if (!startDate) return null

    const venue = e._embedded?.venues?.[0]
    const classification = e.classifications?.[0]

    // Pick best image (16:9, highest res)
    let imageUrl: string | null = null
    if (e.images?.length > 0) {
      const wideImages = e.images.filter((img: any) => img.ratio === '16_9')
      const sorted = (wideImages.length > 0 ? wideImages : e.images)
        .sort((a: any, b: any) => (b.width || 0) - (a.width || 0))
      imageUrl = sorted[0]?.url || null
    }

    // Price range
    let priceMin: number | null = null
    let priceMax: number | null = null
    if (e.priceRanges?.length > 0) {
      const pr = e.priceRanges[0]
      if (pr.min) priceMin = Math.round(pr.min * 100)
      if (pr.max) priceMax = Math.round(pr.max * 100)
    }

    // Category mapping
    const segment = classification?.segment?.name
    const category = segment ? (CATEGORY_MAP[segment] || 'Entertainment') : null

    return {
      source: 'ticketmaster',
      external_id: id,
      title,
      description: e.info || e.pleaseNote || null,
      start_date: startDate,
      end_date: e.dates?.end?.dateTime || null,
      venue_name: venue?.name || null,
      venue_address: [
        venue?.address?.line1,
        venue?.city?.name,
        venue?.state?.stateCode,
      ].filter(Boolean).join(', ') || null,
      lat: venue?.location?.latitude ? parseFloat(venue.location.latitude) : null,
      lng: venue?.location?.longitude ? parseFloat(venue.location.longitude) : null,
      image_url: imageUrl,
      category,
      genre: classification?.genre?.name || null,
      price_range_min: priceMin,
      price_range_max: priceMax,
      ticket_url: e.url || `https://www.ticketmaster.com/event/${id}`,
      source_updated_at: new Date().toISOString(),
      is_active: true,
      updated_at: new Date().toISOString(),
    }
  } catch (err) {
    console.error(`[ticketmaster] Failed to map event:`, err)
    return null
  }
}
