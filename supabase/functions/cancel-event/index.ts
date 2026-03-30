import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import Stripe from 'https://esm.sh/stripe@14.21.0'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
})

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface CancelRequest {
  event_id: string
  reason?: string
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(
      authHeader.replace('Bearer ', '')
    )

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid authentication' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const body: CancelRequest = await req.json()
    const { event_id, reason } = body

    if (!event_id) {
      return new Response(
        JSON.stringify({ error: 'Missing event_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify event exists and user is the organizer
    const { data: event, error: eventError } = await supabaseAdmin
      .from('events')
      .select('id, organizer_id, title, deleted_at')
      .eq('id', event_id)
      .single()

    if (eventError || !event) {
      return new Response(
        JSON.stringify({ error: 'Event not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (event.organizer_id !== user.id) {
      return new Response(
        JSON.stringify({ error: 'Only the event organizer can cancel an event' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (event.deleted_at) {
      return new Response(
        JSON.stringify({ error: 'Event is already cancelled' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Find all completed payments for this event that can be refunded
    const { data: payments, error: paymentsError } = await supabaseAdmin
      .from('payments')
      .select('id, user_id, stripe_payment_intent_id, amount_cents, status, ticket_id, type')
      .eq('event_id', event_id)
      .eq('status', 'completed')
      .not('stripe_payment_intent_id', 'is', null)

    if (paymentsError) {
      console.error('Failed to fetch payments:', paymentsError)
    }

    const refundablePayments = payments || []
    const results = {
      total_payments: refundablePayments.length,
      refunded: 0,
      failed: 0,
      skipped: 0,
      errors: [] as string[],
    }

    // Process refunds for each payment
    for (const payment of refundablePayments) {
      try {
        // Skip payments with zero amount (free tickets)
        if (payment.amount_cents <= 0) {
          results.skipped++
          // Still cancel the ticket
          if (payment.ticket_id) {
            await supabaseAdmin
              .from('tickets')
              .update({ status: 'cancelled' })
              .eq('id', payment.ticket_id)
          }
          // Update payment status
          await supabaseAdmin
            .from('payments')
            .update({ status: 'refunded' })
            .eq('id', payment.id)
          continue
        }

        // Issue Stripe refund
        const refund = await stripe.refunds.create({
          payment_intent: payment.stripe_payment_intent_id,
          reason: 'requested_by_customer',
          metadata: {
            payment_id: payment.id,
            event_id,
            reason: 'event_cancelled',
            cancelled_by: user.id,
          },
        })

        // Update payment status
        await supabaseAdmin
          .from('payments')
          .update({
            status: 'refunded',
            metadata: {
              refund_id: refund.id,
              refund_reason: 'event_cancelled',
              refunded_by: user.id,
              refunded_at: new Date().toISOString(),
              cancellation_reason: reason,
            },
          })
          .eq('id', payment.id)

        // Update ticket status
        if (payment.ticket_id) {
          await supabaseAdmin
            .from('tickets')
            .update({ status: 'refunded' })
            .eq('id', payment.ticket_id)
        }

        results.refunded++
      } catch (err: any) {
        console.error('Failed to refund payment ' + payment.id + ':', err.message)
        results.failed++
        results.errors.push(payment.id + ': ' + (err.message || 'Unknown error'))
      }
    }

    // Cancel any remaining valid tickets without payments (e.g., free tickets, comp tickets)
    const { data: remainingTickets } = await supabaseAdmin
      .from('tickets')
      .select('id, user_id, status')
      .eq('event_id', event_id)
      .in('status', ['valid'])

    if (remainingTickets && remainingTickets.length > 0) {
      await supabaseAdmin
        .from('tickets')
        .update({ status: 'cancelled' })
        .eq('event_id', event_id)
        .eq('status', 'valid')
    }

    // ── Notify all affected users ──
    // Collect unique user IDs from refunded payments and cancelled tickets
    const notifiedUsers = new Set<string>()

    // Notify users who got refunds
    for (const payment of refundablePayments) {
      if (payment.amount_cents > 0 && !notifiedUsers.has(payment.user_id)) {
        notifiedUsers.add(payment.user_id)
        await supabaseAdmin.from('notifications').insert({
          user_id: payment.user_id,
          type: 'event_cancelled',
          title: 'Event Cancelled — Refund Issued',
          body: '"' + event.title + '" has been cancelled. Your payment has been refunded to your original payment method.',
          data: { event_id, event_title: event.title },
        })
      }
    }

    // Notify users with free/comp tickets that were cancelled
    if (remainingTickets) {
      for (const ticket of remainingTickets) {
        if (ticket.user_id && !notifiedUsers.has(ticket.user_id)) {
          notifiedUsers.add(ticket.user_id)
          await supabaseAdmin.from('notifications').insert({
            user_id: ticket.user_id,
            type: 'event_cancelled',
            title: 'Event Cancelled',
            body: '"' + event.title + '" has been cancelled. Your ticket has been cancelled.',
            data: { event_id, event_title: event.title },
          })
        }
      }
    }

    // Cancel any pending resale listings
    await supabaseAdmin
      .from('resale_listings')
      .update({ status: 'cancelled' })
      .eq('event_id', event_id)
      .in('status', ['active', 'pending'])

    // Cancel any active waitlist entries
    await supabaseAdmin
      .from('waitlist_entries')
      .update({ status: 'cancelled' })
      .eq('event_id', event_id)
      .eq('status', 'active')

    // Soft-delete the event
    await supabaseAdmin
      .from('events')
      .update({
        deleted_at: new Date().toISOString(),
        status: 'suspended',
        status_reason: reason || 'Event cancelled by organizer',
      })
      .eq('id', event_id)

    console.log(
      'Event ' + event_id + ' cancelled: ' +
      results.refunded + ' refunded, ' +
      results.failed + ' failed, ' +
      results.skipped + ' skipped (free)'
    )

    return new Response(
      JSON.stringify({
        success: true,
        event_title: event.title,
        ...results,
        cancelled_tickets: (remainingTickets?.length || 0),
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )

  } catch (error: any) {
    console.error('Error cancelling event:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Failed to cancel event' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
