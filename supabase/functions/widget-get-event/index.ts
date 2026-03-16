import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import { createHash } from 'https://deno.land/std@0.177.0/crypto/mod.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const supabase = createClient(supabaseUrl, supabaseServiceKey)

serve(async (req) => {
  // Dynamic CORS — allow any origin, validated later against key's allowed_origins
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
    const { widget_key, event_id } = await req.json()

    if (!widget_key || !event_id) {
      return new Response(
        JSON.stringify({ error: 'Missing widget_key or event_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate widget key
    const keyValidation = await validateWidgetKey(widget_key, event_id, requestOrigin)
    if (!keyValidation.valid) {
      return new Response(
        JSON.stringify({ error: keyValidation.error }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Update CORS to match allowed origins
    if (keyValidation.allowedOrigins && keyValidation.allowedOrigins.length > 0) {
      corsHeaders['Access-Control-Allow-Origin'] = requestOrigin
    }

    // Fetch event data
    const { data: event, error: eventError } = await supabase
      .from('events')
      .select(`
        id, title, description, date,
        location, formatted_address, latitude, longitude,
        image_url, price_in_cents, currency,
        organizer_id, venue_id, event_format,
        venue, city
      `)
      .eq('id', event_id)
      .single()

    if (eventError || !event) {
      return new Response(
        JSON.stringify({ error: 'Event not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify the key's organizer owns this event
    if (event.organizer_id !== keyValidation.organizerId) {
      return new Response(
        JSON.stringify({ error: 'Widget key not authorized for this event' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Fetch active ticket types
    const { data: ticketTypes } = await supabase
      .from('event_ticket_types')
      .select('id, name, description, price_cents, currency, max_quantity, sold_count, is_active, sort_order, category, item_icon, item_description')
      .eq('event_id', event_id)
      .eq('is_active', true)
      .order('sort_order', { ascending: true })

    // Fetch organizer profile
    const { data: organizer } = await supabase
      .from('profiles')
      .select('display_name, avatar_url')
      .eq('id', event.organizer_id)
      .single()

    // Fetch widget config for styling
    const { data: widgetConfig } = await supabase
      .from('widget_configs')
      .select('primary_color, accent_color, font_family, logo_url, button_style, show_powered_by')
      .eq('organizer_id', event.organizer_id)
      .single()

    // Build ticket type response with availability
    const types = (ticketTypes || []).map((t: any) => ({
      id: t.id,
      name: t.name,
      description: t.description,
      price_cents: t.price_cents,
      currency: t.currency || 'usd',
      max_quantity: t.max_quantity,
      remaining: t.max_quantity ? Math.max(0, t.max_quantity - (t.sold_count || 0)) : null,
      is_available: t.max_quantity ? (t.sold_count || 0) < t.max_quantity : true,
      category: t.category || 'entry',
      item_icon: t.item_icon,
      item_description: t.item_description,
      sort_order: t.sort_order,
    }))

    return new Response(
      JSON.stringify({
        event: {
          id: event.id,
          title: event.title,
          description: event.description,
          start_date: event.date,
          location: event.venue || event.city || event.location,
          address: event.formatted_address,
          image_url: event.image_url,
          event_format: event.event_format || 'in_person',
        },
        ticket_types: types,
        organizer: {
          name: organizer?.display_name || 'Event Organizer',
          avatar_url: organizer?.avatar_url,
        },
        widget_config: widgetConfig || {
          primary_color: '#6366F1',
          font_family: 'Inter',
          button_style: 'rounded',
          show_powered_by: true,
        },
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('widget-get-event error:', err)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

async function validateWidgetKey(
  key: string,
  eventId: string,
  origin: string
): Promise<{ valid: boolean; error?: string; organizerId?: string; keyId?: string; allowedOrigins?: string[] }> {
  // Hash the key for lookup
  const encoder = new TextEncoder()
  const data = encoder.encode(key)
  const hashBuffer = await crypto.subtle.digest('SHA-256', data)
  const hashArray = Array.from(new Uint8Array(hashBuffer))
  const keyHash = hashArray.map(b => b.toString(16).padStart(2, '0')).join('')

  const { data: keyRecord, error } = await supabase
    .from('widget_api_keys')
    .select('id, organizer_id, allowed_event_ids, allowed_origins, is_active')
    .eq('key_hash', keyHash)
    .single()

  if (error || !keyRecord) {
    return { valid: false, error: 'Invalid widget key' }
  }

  if (!keyRecord.is_active) {
    return { valid: false, error: 'Widget key is deactivated' }
  }

  // Check event scope
  if (keyRecord.allowed_event_ids && keyRecord.allowed_event_ids.length > 0) {
    if (!keyRecord.allowed_event_ids.includes(eventId)) {
      return { valid: false, error: 'Widget key not authorized for this event' }
    }
  }

  // Check origin
  if (keyRecord.allowed_origins && keyRecord.allowed_origins.length > 0) {
    const originMatch = keyRecord.allowed_origins.some((o: string) => {
      if (o === '*') return true
      return origin === o || origin.endsWith(o.replace('*.', '.'))
    })
    if (!originMatch && origin !== 'null' && origin !== '*') {
      return { valid: false, error: `Origin ${origin} not allowed` }
    }
  }

  // Update last_used_at
  await supabase
    .from('widget_api_keys')
    .update({ last_used_at: new Date().toISOString() })
    .eq('id', keyRecord.id)

  return {
    valid: true,
    organizerId: keyRecord.organizer_id,
    keyId: keyRecord.id,
    allowedOrigins: keyRecord.allowed_origins,
  }
}
