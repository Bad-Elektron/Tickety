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
    // Verify authentication
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Admin client for DB operations
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

    // Verify user
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(
      authHeader.replace('Bearer ', '')
    )

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid authentication' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { offer_id, skip_minting_fee } = await req.json()

    if (!offer_id) {
      return new Response(
        JSON.stringify({ error: 'Missing offer_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Fetch the offer
    const { data: offer, error: offerError } = await supabaseAdmin
      .from('ticket_offers')
      .select('*, events(title)')
      .eq('id', offer_id)
      .single()

    if (offerError || !offer) {
      return new Response(
        JSON.stringify({ error: 'Offer not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify the user is the recipient
    if (offer.recipient_user_id !== user.id && offer.recipient_email !== user.email) {
      return new Response(
        JSON.stringify({ error: 'You are not the recipient of this offer' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check offer status
    if (offer.status !== 'pending') {
      return new Response(
        JSON.stringify({ error: `Offer is already ${offer.status}` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check expiry
    if (offer.expires_at && new Date(offer.expires_at) < new Date()) {
      // Mark as expired
      await supabaseAdmin
        .from('ticket_offers')
        .update({ status: 'expired' })
        .eq('id', offer_id)

      return new Response(
        JSON.stringify({ error: 'This offer has expired' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // For paid offers, this endpoint should NOT be used — they go through Stripe
    if (offer.price_cents > 0) {
      // Exception: free public with skip_minting_fee
      if (!(offer.ticket_mode === 'public' && skip_minting_fee === true)) {
        return new Response(
          JSON.stringify({ error: 'Paid offers must be claimed through the payment flow' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    // Determine final ticket mode
    let finalTicketMode = offer.ticket_mode
    if (offer.ticket_mode === 'public' && skip_minting_fee === true) {
      // Downgrade to private if skipping minting fee
      finalTicketMode = 'private'
    }

    // Get user profile for ticket
    const { data: profile } = await supabaseAdmin
      .from('profiles')
      .select('email, display_name')
      .eq('id', user.id)
      .single()

    // Generate ticket number
    const timestamp = Date.now().toString().substring(7)
    const random = Math.floor(Math.random() * 9999).toString().padStart(4, '0')
    const ticketNumber = `TKT-${timestamp}-${random}`

    // Create the ticket
    const { data: ticket, error: ticketError } = await supabaseAdmin
      .from('tickets')
      .insert({
        event_id: offer.event_id,
        ticket_number: ticketNumber,
        owner_email: profile?.email || user.email,
        owner_name: profile?.display_name || null,
        owner_user_id: user.id,
        price_paid_cents: 0,
        currency: offer.currency,
        status: 'valid',
        sold_by: offer.organizer_id,
        ticket_mode: finalTicketMode,
        offer_id: offer.id,
      })
      .select()
      .single()

    if (ticketError) {
      console.error('Failed to create ticket:', ticketError)
      return new Response(
        JSON.stringify({ error: 'Failed to create ticket' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Update offer status
    const { error: updateError } = await supabaseAdmin
      .from('ticket_offers')
      .update({
        status: 'accepted',
        ticket_id: ticket.id,
        recipient_user_id: user.id,
      })
      .eq('id', offer_id)

    if (updateError) {
      console.error('Failed to update offer status:', updateError)
    }

    console.log(`Favor ticket claimed: offer=${offer_id}, ticket=${ticket.id}, mode=${finalTicketMode}`)

    return new Response(
      JSON.stringify({
        success: true,
        ticket: ticket,
        ticket_mode: finalTicketMode,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error claiming favor offer:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
