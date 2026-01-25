import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import Stripe from 'https://esm.sh/stripe@13.10.0?target=deno'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
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

// Polyfill for padLeft
declare global {
  interface String {
    padLeft(length: number, char: string): string
  }
}

String.prototype.padLeft = function(length: number, char: string): string {
  return char.repeat(Math.max(0, length - this.length)) + this
}
