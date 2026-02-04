import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ClaimTicketRequest {
  transfer_token: string
}

/**
 * Claim a ticket transfer via NFC.
 *
 * This function:
 * 1. Verifies the transfer token is valid and not expired
 * 2. Verifies the ticket hasn't already been transferred
 * 3. Updates the ticket ownership to the claiming user
 * 4. Clears the transfer token
 */
serve(async (req) => {
  // Handle CORS preflight
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

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    })

    // Verify the user is authenticated
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(
      authHeader.replace('Bearer ', '')
    )

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid authentication' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const body: ClaimTicketRequest = await req.json()
    const { transfer_token } = body

    if (!transfer_token) {
      return new Response(
        JSON.stringify({ error: 'Missing required field: transfer_token' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`User ${user.id} attempting to claim ticket with token: ${transfer_token.substring(0, 8)}...`)

    // Find the ticket with this transfer token
    const { data: ticket, error: ticketError } = await supabaseAdmin
      .from('tickets')
      .select(`
        id,
        ticket_number,
        event_id,
        owner_email,
        transfer_token,
        transfer_token_expires_at,
        events:event_id (
          id,
          title,
          date,
          venue,
          city
        )
      `)
      .eq('transfer_token', transfer_token)
      .single()

    if (ticketError || !ticket) {
      console.error('Ticket not found with transfer token:', ticketError)
      return new Response(
        JSON.stringify({ error: 'Invalid transfer token' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check if token has expired
    const expiresAt = new Date(ticket.transfer_token_expires_at)
    if (expiresAt < new Date()) {
      console.log(`Transfer token expired at ${expiresAt.toISOString()}`)
      return new Response(
        JSON.stringify({ error: 'Transfer token has expired' }),
        { status: 410, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check if ticket already has an owner email that doesn't match
    if (ticket.owner_email && ticket.owner_email !== user.email) {
      console.log(`Ticket already owned by: ${ticket.owner_email}`)
      return new Response(
        JSON.stringify({ error: 'Ticket has already been claimed' }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get user's email for the ticket
    const userEmail = user.email || ''

    // Update the ticket ownership
    const { error: updateError } = await supabaseAdmin
      .from('tickets')
      .update({
        owner_email: userEmail,
        transfer_token: null,
        transfer_token_expires_at: null,
      })
      .eq('id', ticket.id)

    if (updateError) {
      console.error('Failed to update ticket:', updateError)
      return new Response(
        JSON.stringify({ error: 'Failed to claim ticket' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Ticket ${ticket.id} successfully transferred to user ${user.id}`)

    // Update the cash transaction status if there is one
    await supabaseAdmin
      .from('cash_transactions')
      .update({ status: 'collected' })
      .eq('ticket_id', ticket.id)

    // Build response with ticket details
    const event = ticket.events as any
    return new Response(
      JSON.stringify({
        success: true,
        ticket: {
          id: ticket.id,
          ticket_number: ticket.ticket_number,
          event_id: ticket.event_id,
          event_title: event?.title || 'Unknown Event',
          event_date: event?.date,
          event_venue: event?.venue,
          event_city: event?.city,
        },
        message: 'Ticket successfully claimed!',
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error: unknown) {
    console.error('Error claiming ticket transfer:', error)
    const errorMessage = error instanceof Error ? error.message : 'Internal server error'
    return new Response(
      JSON.stringify({ error: errorMessage }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
