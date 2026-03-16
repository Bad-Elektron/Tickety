import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import Stripe from 'https://esm.sh/stripe@14.21.0'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
})

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const stripePublishableKey = Deno.env.get('STRIPE_PUBLISHABLE_KEY')!
const supabase = createClient(supabaseUrl, supabaseServiceKey)

// Fee constants — must match create-payment-intent exactly
const PLATFORM_FEE_RATE = 0.05
const STRIPE_FEE_RATE = 0.029
const STRIPE_FEE_FIXED_CENTS = 30
const MINT_FEE_CENTS = 25

function calculateFees(baseCents: number) {
  if (baseCents <= 0) {
    return {
      base_cents: 0, platform_fee_cents: 0, mint_fee_cents: 0,
      stripe_fee_cents: 0, service_fee_cents: 0, total_cents: 0,
    }
  }
  const platform_fee_cents = Math.ceil(baseCents * PLATFORM_FEE_RATE)
  const mint_fee_cents = MINT_FEE_CENTS
  const subtotal = baseCents + platform_fee_cents + mint_fee_cents
  const total_cents = Math.ceil((subtotal + STRIPE_FEE_FIXED_CENTS) / (1 - STRIPE_FEE_RATE))
  const stripe_fee_cents = total_cents - subtotal
  const service_fee_cents = platform_fee_cents + stripe_fee_cents + mint_fee_cents
  return { base_cents: baseCents, platform_fee_cents, mint_fee_cents, stripe_fee_cents, service_fee_cents, total_cents }
}

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
    const body = await req.json()
    const { widget_key, event_id, ticket_selections, buyer_email, buyer_name, promo_code } = body

    if (!widget_key || !event_id || !ticket_selections || !buyer_email) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Server-side email validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    if (!emailRegex.test(buyer_email)) {
      return new Response(
        JSON.stringify({ error: 'Invalid email address' }),
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

    // Verify event belongs to this organizer
    const { data: event, error: eventError } = await supabase
      .from('events')
      .select('id, title, organizer_id, price_in_cents')
      .eq('id', event_id)
      .single()

    if (eventError || !event) {
      return new Response(
        JSON.stringify({ error: 'Event not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (event.organizer_id !== keyValidation.organizerId) {
      return new Response(
        JSON.stringify({ error: 'Not authorized for this event' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Fetch ticket type prices and validate availability
    const typeIds = ticket_selections.map((ts: any) => ts.ticket_type_id)
    const { data: dbTypes, error: typesError } = await supabase
      .from('event_ticket_types')
      .select('id, name, price_cents, max_quantity, sold_count, is_active, category, item_icon')
      .in('id', typeIds)

    if (typesError || !dbTypes) {
      return new Response(
        JSON.stringify({ error: 'Failed to fetch ticket types' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const typeMap: Record<string, any> = {}
    for (const dt of dbTypes) {
      typeMap[dt.id] = dt
    }

    // Calculate total and validate availability
    let baseCents = 0
    let totalQuantity = 0
    const validatedItems: any[] = []

    for (const sel of ticket_selections) {
      const dbType = typeMap[sel.ticket_type_id]
      if (!dbType) {
        return new Response(
          JSON.stringify({ error: `Ticket type ${sel.ticket_type_id} not found` }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      if (!dbType.is_active) {
        return new Response(
          JSON.stringify({ error: `${dbType.name} is no longer available` }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      if (dbType.max_quantity && (dbType.sold_count || 0) + sel.quantity > dbType.max_quantity) {
        const remaining = dbType.max_quantity - (dbType.sold_count || 0)
        return new Response(
          JSON.stringify({ error: `Only ${remaining} ${dbType.name} ticket(s) remaining` }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      baseCents += dbType.price_cents * sel.quantity
      totalQuantity += sel.quantity
      validatedItems.push({
        ticket_type_id: sel.ticket_type_id,
        quantity: sel.quantity,
        category: dbType.category || 'entry',
        item_icon: dbType.item_icon,
        name: dbType.name,
        unit_price_cents: dbType.price_cents,
      })
    }

    // Validate promo code if provided
    let promoDiscountCents = 0
    let promoCodeId: string | null = null
    if (promo_code) {
      const { data: promoResult } = await supabase.rpc('validate_promo_code', {
        p_event_id: event_id,
        p_code: promo_code,
        p_user_id: null,  // guest — skip user-specific checks
        p_base_price_cents: baseCents,
        p_ticket_type_id: null,
      })
      if (promoResult?.valid) {
        promoDiscountCents = promoResult.discount_cents
        promoCodeId = promoResult.promo_code_id
      }
    }

    // Calculate fees
    const netBase = Math.max(0, baseCents - promoDiscountCents)
    const fees = calculateFees(netBase)

    // Get or create guest buyer
    let guestBuyer: any
    const { data: existingBuyer } = await supabase
      .from('widget_guest_buyers')
      .select('id, stripe_customer_id')
      .eq('email', buyer_email.toLowerCase())
      .single()

    if (existingBuyer) {
      guestBuyer = existingBuyer
      if (buyer_name) {
        await supabase.from('widget_guest_buyers').update({ name: buyer_name }).eq('id', existingBuyer.id)
      }
    } else {
      const { data: newBuyer, error: buyerError } = await supabase
        .from('widget_guest_buyers')
        .insert({ email: buyer_email.toLowerCase(), name: buyer_name || null })
        .select()
        .single()
      if (buyerError) {
        console.error('Failed to create guest buyer:', buyerError)
        return new Response(
          JSON.stringify({ error: 'Failed to create buyer record' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      guestBuyer = newBuyer
    }

    // Get or create Stripe customer for guest
    let stripeCustomerId = guestBuyer.stripe_customer_id
    if (!stripeCustomerId) {
      const customer = await stripe.customers.create({
        email: buyer_email.toLowerCase(),
        name: buyer_name || undefined,
        metadata: { source: 'widget', guest_buyer_id: guestBuyer.id },
      })
      stripeCustomerId = customer.id
      await supabase
        .from('widget_guest_buyers')
        .update({ stripe_customer_id: customer.id })
        .eq('id', guestBuyer.id)
    }

    // Get or create a Supabase auth user for the guest (enables existing ticket flow)
    // Look up by email in profiles table first (efficient, no full user scan)
    let userId: string
    const { data: existingProfile } = await supabase
      .from('profiles')
      .select('id')
      .eq('email', buyer_email.toLowerCase())
      .maybeSingle()

    if (existingProfile) {
      userId = existingProfile.id
    } else {
      // Try to create a new auth user
      const { data: newUser, error: userError } = await supabase.auth.admin.createUser({
        email: buyer_email.toLowerCase(),
        email_confirm: true,
        user_metadata: { source: 'widget_checkout', display_name: buyer_name || null },
      })

      if (userError) {
        // User might already exist (race condition or profile missing) — look up by email via admin API
        const { data: listResult } = await supabase.auth.admin.listUsers({ filter: `email.eq.${buyer_email.toLowerCase()}` })
        const found = listResult?.users?.[0]
        if (found) {
          userId = found.id
        } else {
          console.error('Failed to create or find auth user:', userError)
          return new Response(
            JSON.stringify({ error: 'Failed to create user account' }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }
      } else {
        userId = newUser.user!.id
      }

      // Create minimal profile
      await supabase.from('profiles').upsert({
        id: userId,
        email: buyer_email.toLowerCase(),
        display_name: buyer_name || buyer_email.split('@')[0],
      })
    }

    // Build ticket_items metadata for the webhook
    const ticketItems = validatedItems.map((item: any) => ({
      ticket_type_id: item.ticket_type_id,
      quantity: item.quantity,
      category: item.category,
      item_icon: item.item_icon,
    }))

    // Create Stripe PaymentIntent
    const paymentIntent = await stripe.paymentIntents.create({
      amount: fees.total_cents,
      currency: 'usd',
      customer: stripeCustomerId,
      metadata: {
        source: 'widget',
        event_id,
        event_title: event.title,
        user_id: userId,
        type: 'primary_purchase',
        quantity: totalQuantity.toString(),
        base_amount_cents: netBase.toString(),
        service_fee_cents: fees.service_fee_cents.toString(),
        ...(promoCodeId && { promo_code_id: promoCodeId }),
      },
    })

    // Create payment record (used by stripe-webhook to get ticket_items)
    const { data: payment } = await supabase
      .from('payments')
      .insert({
        user_id: userId,
        event_id,
        amount_cents: fees.total_cents,
        currency: 'usd',
        status: 'pending',
        type: 'primary_purchase',
        stripe_payment_intent_id: paymentIntent.id,
        platform_fee_cents: fees.platform_fee_cents,
        ...(promoCodeId && { promo_code_id: promoCodeId }),
        metadata: {
          source: 'widget',
          event_title: event.title,
          ticket_items: ticketItems,
          fee_breakdown: fees,
          guest_buyer_id: guestBuyer.id,
          buyer_email: buyer_email.toLowerCase(),
          buyer_name: buyer_name || null,
          ...(promoDiscountCents > 0 && { promo_discount_cents: promoDiscountCents }),
        },
      })
      .select()
      .single()

    // Create checkout session
    const { data: session } = await supabase
      .from('widget_checkout_sessions')
      .insert({
        widget_key_id: keyValidation.keyId,
        event_id,
        guest_buyer_id: guestBuyer.id,
        user_id: userId,
        ticket_selections,
        amount_cents: fees.total_cents,
        currency: 'usd',
        status: 'payment_started',
        stripe_payment_intent_id: paymentIntent.id,
        promo_code_id: promoCodeId,
        promo_discount_cents: promoDiscountCents,
        metadata: { buyer_email: buyer_email.toLowerCase(), buyer_name },
      })
      .select('id')
      .single()

    return new Response(
      JSON.stringify({
        session_id: session?.id,
        client_secret: paymentIntent.client_secret,
        publishable_key: stripePublishableKey,
        payment_intent_id: paymentIntent.id,
        amount_cents: fees.total_cents,
        fee_breakdown: {
          base_cents: netBase,
          platform_fee_cents: fees.platform_fee_cents,
          stripe_fee_cents: fees.stripe_fee_cents,
          mint_fee_cents: fees.mint_fee_cents,
          service_fee_cents: fees.service_fee_cents,
          total_cents: fees.total_cents,
        },
        ...(promoDiscountCents > 0 && { promo_discount_cents: promoDiscountCents }),
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('widget-create-checkout error:', err)
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
): Promise<{ valid: boolean; error?: string; organizerId?: string; keyId?: string }> {
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

  if (error || !keyRecord) return { valid: false, error: 'Invalid widget key' }
  if (!keyRecord.is_active) return { valid: false, error: 'Widget key is deactivated' }

  if (keyRecord.allowed_event_ids?.length > 0 && !keyRecord.allowed_event_ids.includes(eventId)) {
    return { valid: false, error: 'Key not authorized for this event' }
  }

  if (keyRecord.allowed_origins?.length > 0) {
    const match = keyRecord.allowed_origins.some((o: string) =>
      o === '*' || origin === o || origin.endsWith(o.replace('*.', '.'))
    )
    if (!match && origin !== 'null' && origin !== '*') {
      return { valid: false, error: `Origin ${origin} not allowed` }
    }
  }

  // Basic rate limiting: count recent checkout sessions for this key
  const oneMinuteAgo = new Date(Date.now() - 60000).toISOString()
  const { count } = await supabase
    .from('widget_checkout_sessions')
    .select('id', { count: 'exact', head: true })
    .eq('widget_key_id', keyRecord.id)
    .gte('created_at', oneMinuteAgo)

  const limit = keyRecord.rate_limit_per_minute || 100
  if (count !== null && count >= limit) {
    return { valid: false, error: 'Rate limit exceeded. Please try again later.' }
  }

  await supabase
    .from('widget_api_keys')
    .update({ last_used_at: new Date().toISOString() })
    .eq('id', keyRecord.id)

  return { valid: true, organizerId: keyRecord.organizer_id, keyId: keyRecord.id }
}
