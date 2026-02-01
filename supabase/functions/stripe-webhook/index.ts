import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import Stripe from 'https://esm.sh/stripe@14.21.0'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
})

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET')!

// Use service role for webhook operations
const supabase = createClient(supabaseUrl, supabaseServiceKey)

serve(async (req) => {
  const signature = req.headers.get('stripe-signature')
  if (!signature) {
    return new Response('Missing stripe-signature header', { status: 400 })
  }

  const body = await req.text()

  let event: Stripe.Event

  try {
    event = await stripe.webhooks.constructEventAsync(body, signature, webhookSecret)
  } catch (err) {
    console.error('Webhook signature verification failed:', err.message)
    return new Response(`Webhook Error: ${err.message}`, { status: 400 })
  }

  console.log(`Processing webhook event: ${event.type}`)

  try {
    switch (event.type) {
      case 'payment_intent.succeeded':
        await handlePaymentSucceeded(event.data.object as Stripe.PaymentIntent)
        break

      case 'payment_intent.payment_failed':
        await handlePaymentFailed(event.data.object as Stripe.PaymentIntent)
        break

      case 'charge.refunded':
        await handleChargeRefunded(event.data.object as Stripe.Charge)
        break

      // Subscription events
      case 'customer.subscription.created':
        await handleSubscriptionCreated(event.data.object as Stripe.Subscription)
        break

      case 'customer.subscription.updated':
        await handleSubscriptionUpdated(event.data.object as Stripe.Subscription)
        break

      case 'customer.subscription.deleted':
        await handleSubscriptionDeleted(event.data.object as Stripe.Subscription)
        break

      default:
        console.log(`Unhandled event type: ${event.type}`)
    }

    return new Response(JSON.stringify({ received: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })

  } catch (error) {
    console.error('Error processing webhook:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    })
  }
})

async function handlePaymentSucceeded(paymentIntent: Stripe.PaymentIntent) {
  const { event_id, user_id, type, quantity: quantityStr } = paymentIntent.metadata
  const quantity = parseInt(quantityStr || '1', 10)

  console.log(`Payment succeeded: ${paymentIntent.id} for event ${event_id}, quantity: ${quantity}`)

  // Update payment record
  const { error: updateError } = await supabase
    .from('payments')
    .update({
      status: 'completed',
      stripe_charge_id: paymentIntent.latest_charge as string,
    })
    .eq('stripe_payment_intent_id', paymentIntent.id)

  if (updateError) {
    console.error('Failed to update payment record:', updateError)
  }

  // Skip ticket creation for test events (non-UUID event IDs)
  const isTestEvent = event_id?.startsWith('test-')
  if (isTestEvent) {
    console.log('Skipping ticket creation for test event')
    return
  }

  // Create tickets for the user
  if (type === 'primary_purchase' || type === 'vendor_pos') {
    // Get user info for ticket
    const { data: profile } = await supabase
      .from('profiles')
      .select('email, full_name')
      .eq('id', user_id)
      .single()

    // Get user's auth email as fallback
    const { data: authData } = await supabase.auth.admin.getUserById(user_id)
    const ownerEmail = profile?.email || authData?.user?.email || null
    const ownerName = profile?.full_name || null

    // Calculate price per ticket
    const pricePerTicket = Math.round(paymentIntent.amount / quantity)

    // Create tickets for each quantity
    const ticketIds: string[] = []
    for (let i = 0; i < quantity; i++) {
      // Generate unique ticket number
      const timestamp = Date.now().toString().substring(7)
      const random = Math.floor(Math.random() * 9999).toString().padLeft(4, '0')
      const ticketNumber = `TKT-${timestamp}-${random}`

      const { data: ticket, error: ticketError } = await supabase
        .from('tickets')
        .insert({
          event_id,
          ticket_number: ticketNumber,
          owner_email: ownerEmail,
          owner_name: ownerName,
          price_paid_cents: pricePerTicket,
          currency: paymentIntent.currency.toUpperCase(),
          status: 'valid',
          sold_by: user_id,
        })
        .select()
        .single()

      if (ticketError) {
        console.error(`Failed to create ticket ${i + 1}/${quantity}:`, ticketError)
        continue
      }

      ticketIds.push(ticket.id)
      console.log(`Ticket ${i + 1}/${quantity} created: ${ticketNumber}`)
    }

    // Link first ticket to payment (for reference)
    if (ticketIds.length > 0) {
      await supabase
        .from('payments')
        .update({ ticket_id: ticketIds[0] })
        .eq('stripe_payment_intent_id', paymentIntent.id)
    }

    console.log(`Created ${ticketIds.length} tickets for payment ${paymentIntent.id}`)
  }

  // For resale purchases, transfer ticket ownership is handled by create-resale-intent
}

async function handlePaymentFailed(paymentIntent: Stripe.PaymentIntent) {
  console.log(`Payment failed: ${paymentIntent.id}`)

  const { error } = await supabase
    .from('payments')
    .update({ status: 'failed' })
    .eq('stripe_payment_intent_id', paymentIntent.id)

  if (error) {
    console.error('Failed to update payment status:', error)
  }
}

async function handleChargeRefunded(charge: Stripe.Charge) {
  console.log(`Charge refunded: ${charge.id}`)

  // Find the payment by charge ID
  const { data: payment, error: findError } = await supabase
    .from('payments')
    .select('id, ticket_id')
    .eq('stripe_charge_id', charge.id)
    .single()

  if (findError || !payment) {
    console.error('Payment not found for refunded charge:', charge.id)
    return
  }

  // Update payment status
  const { error: updateError } = await supabase
    .from('payments')
    .update({ status: 'refunded' })
    .eq('id', payment.id)

  if (updateError) {
    console.error('Failed to update payment status:', updateError)
  }

  // If there's an associated ticket, update its status
  if (payment.ticket_id) {
    const { error: ticketError } = await supabase
      .from('tickets')
      .update({ status: 'refunded' })
      .eq('id', payment.ticket_id)

    if (ticketError) {
      console.error('Failed to update ticket status:', ticketError)
    }
  }

  console.log(`Refund processed for payment: ${payment.id}`)
}

// ============================================================
// SUBSCRIPTION EVENT HANDLERS
// ============================================================

// Map Stripe price IDs to tier names
const PRICE_TO_TIER: Record<string, string> = {
  [Deno.env.get('STRIPE_PRO_PRICE_ID') || 'price_pro_monthly']: 'pro',
  [Deno.env.get('STRIPE_ENTERPRISE_PRICE_ID') || 'price_enterprise_monthly']: 'enterprise',
}

function getTierFromPriceId(priceId: string): string {
  return PRICE_TO_TIER[priceId] || 'base'
}

function mapSubscriptionStatus(stripeStatus: string): string {
  switch (stripeStatus) {
    case 'active':
      return 'active'
    case 'canceled':
      return 'canceled'
    case 'past_due':
      return 'past_due'
    case 'trialing':
      return 'trialing'
    case 'paused':
      return 'paused'
    case 'incomplete':
    case 'incomplete_expired':
    case 'unpaid':
    default:
      return 'canceled'
  }
}

async function handleSubscriptionCreated(subscription: Stripe.Subscription) {
  const userId = subscription.metadata?.supabase_user_id
  if (!userId) {
    console.error('No supabase_user_id in subscription metadata:', subscription.id)
    return
  }

  const priceId = subscription.items.data[0]?.price?.id
  const tier = subscription.metadata?.tier || getTierFromPriceId(priceId || '')
  const status = mapSubscriptionStatus(subscription.status)

  console.log(`Subscription created: ${subscription.id} for user ${userId}, tier: ${tier}, status: ${status}`)

  const { error } = await supabase
    .from('subscriptions')
    .upsert({
      user_id: userId,
      tier: tier,
      status: status,
      stripe_subscription_id: subscription.id,
      stripe_price_id: priceId,
      current_period_start: new Date(subscription.current_period_start * 1000).toISOString(),
      current_period_end: new Date(subscription.current_period_end * 1000).toISOString(),
      cancel_at_period_end: subscription.cancel_at_period_end,
    }, {
      onConflict: 'user_id',
    })

  if (error) {
    console.error('Failed to upsert subscription:', error)
  } else {
    console.log(`Subscription record created/updated for user ${userId}`)
  }
}

async function handleSubscriptionUpdated(subscription: Stripe.Subscription) {
  const userId = subscription.metadata?.supabase_user_id

  // If no user ID in metadata, try to find by subscription ID
  let targetUserId = userId
  if (!targetUserId) {
    const { data: existingSub } = await supabase
      .from('subscriptions')
      .select('user_id')
      .eq('stripe_subscription_id', subscription.id)
      .single()

    if (existingSub) {
      targetUserId = existingSub.user_id
    }
  }

  if (!targetUserId) {
    console.error('Cannot find user for subscription:', subscription.id)
    return
  }

  const priceId = subscription.items.data[0]?.price?.id
  const tier = subscription.metadata?.tier || getTierFromPriceId(priceId || '')
  const status = mapSubscriptionStatus(subscription.status)

  console.log(`Subscription updated: ${subscription.id} for user ${targetUserId}, tier: ${tier}, status: ${status}`)

  const { error } = await supabase
    .from('subscriptions')
    .update({
      tier: tier,
      status: status,
      stripe_price_id: priceId,
      current_period_start: new Date(subscription.current_period_start * 1000).toISOString(),
      current_period_end: new Date(subscription.current_period_end * 1000).toISOString(),
      cancel_at_period_end: subscription.cancel_at_period_end,
    })
    .eq('user_id', targetUserId)

  if (error) {
    console.error('Failed to update subscription:', error)
  } else {
    console.log(`Subscription record updated for user ${targetUserId}`)
  }
}

async function handleSubscriptionDeleted(subscription: Stripe.Subscription) {
  const userId = subscription.metadata?.supabase_user_id

  // If no user ID in metadata, try to find by subscription ID
  let targetUserId = userId
  if (!targetUserId) {
    const { data: existingSub } = await supabase
      .from('subscriptions')
      .select('user_id')
      .eq('stripe_subscription_id', subscription.id)
      .single()

    if (existingSub) {
      targetUserId = existingSub.user_id
    }
  }

  if (!targetUserId) {
    console.error('Cannot find user for deleted subscription:', subscription.id)
    return
  }

  console.log(`Subscription deleted: ${subscription.id} for user ${targetUserId}`)

  // Reset user to base tier
  const { error } = await supabase
    .from('subscriptions')
    .update({
      tier: 'base',
      status: 'canceled',
      stripe_subscription_id: null,
      stripe_price_id: null,
      current_period_start: null,
      current_period_end: null,
      cancel_at_period_end: false,
    })
    .eq('user_id', targetUserId)

  if (error) {
    console.error('Failed to reset subscription to base:', error)
  } else {
    console.log(`User ${targetUserId} reset to base tier`)
  }
}

// Polyfill for padLeft
declare global {
  interface String {
    padLeft(length: number, char: string): string
  }
}

String.prototype.padLeft = function(length: number, char: string): string {
  return char.repeat(Math.max(0, length - this.length)) + this
}
