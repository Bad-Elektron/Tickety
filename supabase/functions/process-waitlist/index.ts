import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import Stripe from 'https://esm.sh/stripe@14.21.0'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
})

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const supabase = createClient(supabaseUrl, supabaseServiceKey)

interface ProcessRequest {
  event_id: string
  // Optional: specific listing that triggered this (resale)
  listing_id?: string
  listing_price_cents?: number
  // Optional: trigger source
  trigger: 'resale_listed' | 'capacity_added' | 'manual'
}

serve(async (req) => {
  try {
    const { event_id, listing_id, listing_price_cents, trigger } =
      (await req.json()) as ProcessRequest

    if (!event_id) {
      return new Response(JSON.stringify({ error: 'event_id required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    console.log(
      `Processing waitlist for event ${event_id}, trigger: ${trigger}`,
    )

    // Get event info
    const { data: event, error: eventError } = await supabase
      .from('events')
      .select('id, title, price_in_cents, date')
      .eq('id', event_id)
      .single()

    if (eventError || !event) {
      console.error('Event not found:', eventError)
      return new Response(JSON.stringify({ error: 'Event not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Don't process waitlists for past events
    if (new Date(event.date) < new Date()) {
      console.log('Event already passed, skipping waitlist processing')
      return new Response(JSON.stringify({ skipped: true, reason: 'event_passed' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Get active waitlist entries in FIFO order
    const { data: queue, error: queueError } = await supabase
      .rpc('get_waitlist_queue', {
        p_event_id: event_id,
        p_limit: 50,
      })

    if (queueError || !queue || queue.length === 0) {
      console.log('No active waitlist entries')
      return new Response(JSON.stringify({ processed: 0 }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    let notifiedCount = 0
    let purchasedCount = 0
    let failedCount = 0

    for (const entry of queue) {
      try {
        if (entry.mode === 'notify') {
          // Send notification
          await notifyUser(entry, event)
          notifiedCount++
        } else if (entry.mode === 'auto_buy') {
          // Determine price to check against max_price
          // For resale triggers, use listing price; for official, use event price
          const availablePriceCents =
            trigger === 'resale_listed' && listing_price_cents
              ? listing_price_cents
              : event.price_in_cents || 0

          // Check if price is within user's max
          if (
            entry.max_price_cents !== null &&
            availablePriceCents > entry.max_price_cents
          ) {
            console.log(
              `Skipping auto-buy for user ${entry.user_id}: price ${availablePriceCents} > max ${entry.max_price_cents}`,
            )
            continue
          }

          // Attempt off-session purchase
          const success = await attemptAutoPurchase(
            entry,
            event,
            availablePriceCents,
            listing_id,
            trigger,
          )

          if (success) {
            purchasedCount++
            // For resale, only one person can buy the listing — stop processing auto_buy
            if (trigger === 'resale_listed' && listing_id) {
              console.log('Resale listing claimed by auto-buy, stopping queue')
              break
            }
          } else {
            failedCount++
          }
        }
      } catch (err) {
        console.error(
          `Error processing waitlist entry ${entry.id}:`,
          err.message,
        )
        failedCount++
      }
    }

    console.log(
      `Waitlist processed: ${notifiedCount} notified, ${purchasedCount} purchased, ${failedCount} failed`,
    )

    return new Response(
      JSON.stringify({
        processed: notifiedCount + purchasedCount,
        notified: notifiedCount,
        purchased: purchasedCount,
        failed: failedCount,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    )
  } catch (error) {
    console.error('process-waitlist error:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})

/**
 * Notify a user that tickets are available.
 */
async function notifyUser(
  entry: { id: string; user_id: string },
  event: { id: string; title: string },
) {
  // Create notification
  const { error: notifError } = await supabase.from('notifications').insert({
    user_id: entry.user_id,
    type: 'waitlist_available',
    title: 'Tickets Available!',
    body: `Tickets are now available for "${event.title}". Get yours before they sell out!`,
    data: { event_id: event.id, event_title: event.title },
  })

  if (notifError) {
    console.error('Failed to create notification:', notifError)
  }

  // Mark entry as notified
  await supabase
    .from('waitlist_entries')
    .update({ status: 'notified' })
    .eq('id', entry.id)

  console.log(`Notified user ${entry.user_id} for event ${event.id}`)
}

/**
 * Attempt an off-session Stripe purchase for an auto-buy waitlist entry.
 */
async function attemptAutoPurchase(
  entry: {
    id: string
    user_id: string
    payment_method_id: string
    stripe_customer_id: string
    max_price_cents: number | null
  },
  event: { id: string; title: string; price_in_cents: number | null },
  priceCents: number,
  listingId: string | undefined,
  trigger: string,
): Promise<boolean> {
  if (!entry.payment_method_id || !entry.stripe_customer_id) {
    console.error(
      `Auto-buy entry ${entry.id} missing payment_method_id or stripe_customer_id`,
    )
    await markEntryFailed(entry.id, 'Missing payment method')
    return false
  }

  // Calculate fees (same as create-payment-intent: 5% platform + 2.9% + $0.30 Stripe + $0.25 mint)
  const platformFeeCents = Math.round(priceCents * 0.05)
  const subtotalBeforeStripe = priceCents + platformFeeCents + 25 // +$0.25 mint
  const stripeFeeCents = Math.round(subtotalBeforeStripe * 0.029) + 30
  const totalCents = subtotalBeforeStripe + stripeFeeCents

  // Double-check against max price (total including fees)
  if (entry.max_price_cents !== null && totalCents > entry.max_price_cents) {
    console.log(
      `Total ${totalCents} exceeds max ${entry.max_price_cents}, skipping`,
    )
    return false
  }

  try {
    // Create off-session PaymentIntent
    const paymentIntent = await stripe.paymentIntents.create({
      amount: totalCents,
      currency: 'usd',
      customer: entry.stripe_customer_id,
      payment_method: entry.payment_method_id,
      off_session: true,
      confirm: true,
      metadata: {
        event_id: event.id,
        user_id: entry.user_id,
        type: 'waitlist_auto_purchase',
        quantity: '1',
        event_title: event.title,
        waitlist_entry_id: entry.id,
        base_amount_cents: String(priceCents),
        service_fee_cents: String(platformFeeCents + stripeFeeCents + 25),
        trigger,
        ...(listingId && { resale_listing_id: listingId }),
      },
    })

    if (
      paymentIntent.status === 'succeeded' ||
      paymentIntent.status === 'processing'
    ) {
      // Create payment record
      const { data: payment } = await supabase
        .from('payments')
        .insert({
          user_id: entry.user_id,
          event_id: event.id,
          amount_cents: totalCents,
          currency: 'usd',
          status:
            paymentIntent.status === 'succeeded' ? 'completed' : 'processing',
          type: 'waitlist_auto_purchase',
          stripe_payment_intent_id: paymentIntent.id,
          platform_fee_cents: platformFeeCents + stripeFeeCents + 25,
          metadata: {
            waitlist_entry_id: entry.id,
            auto_purchased: true,
          },
        })
        .select('id')
        .single()

      // Mark waitlist entry as purchased
      await supabase
        .from('waitlist_entries')
        .update({
          status: 'purchased',
          payment_id: payment?.id,
        })
        .eq('id', entry.id)

      // Notify user of successful auto-purchase
      await supabase.from('notifications').insert({
        user_id: entry.user_id,
        type: 'waitlist_auto_purchased',
        title: 'Ticket Auto-Purchased!',
        body: `A ticket for "${event.title}" was automatically purchased for you at $${(priceCents / 100).toFixed(2)}.`,
        data: {
          event_id: event.id,
          event_title: event.title,
          amount_cents: totalCents,
          payment_id: payment?.id,
        },
      })

      console.log(
        `Auto-purchase succeeded for user ${entry.user_id}: ${paymentIntent.id}`,
      )
      return true
    }

    // Payment requires action (3DS etc.) — can't handle off-session
    console.log(
      `Payment requires action for user ${entry.user_id}: ${paymentIntent.status}`,
    )
    await markEntryFailed(entry.id, 'Payment requires authentication')
    return false
  } catch (err) {
    console.error(
      `Auto-purchase failed for user ${entry.user_id}:`,
      err.message,
    )
    await markEntryFailed(entry.id, err.message)

    // Notify user of failure
    await supabase.from('notifications').insert({
      user_id: entry.user_id,
      type: 'waitlist_available',
      title: 'Auto-Purchase Failed',
      body: `We couldn't automatically purchase a ticket for "${event.title}". Tickets may still be available — check the event page.`,
      data: {
        event_id: event.id,
        event_title: event.title,
        error: 'payment_failed',
      },
    })

    return false
  }
}

async function markEntryFailed(entryId: string, reason: string) {
  await supabase
    .from('waitlist_entries')
    .update({
      status: 'failed',
      // Store failure reason in updated_at isn't ideal, but we don't have a reason column
      // The notification will contain the info
    })
    .eq('id', entryId)
}
