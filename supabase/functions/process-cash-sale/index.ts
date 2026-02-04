import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import Stripe from 'https://esm.sh/stripe@14.21.0'
import { crypto } from 'https://deno.land/std@0.177.0/crypto/mod.ts'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
})

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

// Platform fee percentage (5%) - same as resale
const PLATFORM_FEE_PERCENT = 0.05

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface CashSaleRequest {
  event_id: string
  ticket_type_id?: string
  amount_cents: number
  customer_name?: string
  customer_email?: string
  delivery_method: 'nfc' | 'email' | 'in_person'
}

/**
 * Process a cash sale at an event.
 *
 * Flow:
 * 1. Verify staff has permission for event
 * 2. Verify cash_sales_enabled = true and organizer has payment method
 * 3. Create ticket with payment_method: 'cash'
 * 4. Create cash_transactions record
 * 5. Charge organizer's card for 5% platform fee
 * 6. If NFC delivery, generate transfer token
 * 7. Return ticket data for delivery
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

    const body: CashSaleRequest = await req.json()
    const {
      event_id,
      ticket_type_id,
      amount_cents,
      customer_name,
      customer_email,
      delivery_method,
    } = body

    // Validate required fields
    if (!event_id || amount_cents === undefined || !delivery_method) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: event_id, amount_cents, delivery_method' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!['nfc', 'email', 'in_person'].includes(delivery_method)) {
      return new Response(
        JSON.stringify({ error: 'Invalid delivery_method. Must be: nfc, email, or in_person' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Processing cash sale for event ${event_id} by user ${user.id}`)

    // 1. Get event and verify cash sales are enabled
    const { data: event, error: eventError } = await supabaseAdmin
      .from('events')
      .select('id, title, organizer_id, cash_sales_enabled, organizer_stripe_customer_id, organizer_payment_method_id, price_in_cents')
      .eq('id', event_id)
      .single()

    if (eventError || !event) {
      console.error('Event not found:', event_id, eventError)
      return new Response(
        JSON.stringify({ error: 'Event not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check if cash sales are enabled
    if (!event.cash_sales_enabled) {
      return new Response(
        JSON.stringify({ error: 'Cash sales are not enabled for this event' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check if organizer has payment method
    if (!event.organizer_stripe_customer_id || !event.organizer_payment_method_id) {
      return new Response(
        JSON.stringify({ error: 'Organizer has not set up payment method for cash sales' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 2. Verify staff has permission for this event
    const { data: staffRole, error: staffError } = await supabaseAdmin
      .from('event_staff')
      .select('role')
      .eq('event_id', event_id)
      .eq('user_id', user.id)
      .single()

    // Also allow organizer to sell tickets
    const isOrganizer = event.organizer_id === user.id
    const isStaff = !staffError && staffRole

    if (!isOrganizer && !isStaff) {
      console.error('User not authorized for this event:', user.id)
      return new Response(
        JSON.stringify({ error: 'You do not have permission to sell tickets for this event' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 3. Get ticket type info if specified
    let ticketTypeName: string | null = null
    if (ticket_type_id) {
      const { data: ticketType } = await supabaseAdmin
        .from('event_ticket_types')
        .select('name, price_in_cents, quantity_limit, quantity_sold')
        .eq('id', ticket_type_id)
        .single()

      if (ticketType) {
        ticketTypeName = ticketType.name

        // Verify price matches
        if (ticketType.price_in_cents !== amount_cents) {
          console.log(`Price mismatch: type=${ticketType.price_in_cents}, request=${amount_cents}`)
          return new Response(
            JSON.stringify({ error: 'Price mismatch. Please refresh and try again.' }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }

        // Check availability
        if (ticketType.quantity_limit !== null &&
            ticketType.quantity_sold >= ticketType.quantity_limit) {
          return new Response(
            JSON.stringify({ error: `${ticketType.name} tickets are sold out` }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }
      }
    }

    // Calculate platform fee (5%)
    const platformFeeCents = Math.round(amount_cents * PLATFORM_FEE_PERCENT)

    // Generate ticket number
    const ticketNumber = generateTicketNumber()

    // Generate transfer token for NFC delivery
    let transferToken: string | null = null
    let transferTokenExpiresAt: string | null = null
    if (delivery_method === 'nfc') {
      transferToken = generateTransferToken()
      // Token expires in 5 minutes
      transferTokenExpiresAt = new Date(Date.now() + 5 * 60 * 1000).toISOString()
    }

    // 4. Create ticket
    const { data: ticket, error: ticketError } = await supabaseAdmin
      .from('tickets')
      .insert({
        event_id,
        ticket_number: ticketNumber,
        owner_email: customer_email || null,
        owner_name: customer_name || null,
        price_paid_cents: amount_cents,
        currency: 'USD',
        sold_by: user.id,
        status: 'valid',
        payment_method: 'cash',
        delivery_method,
        transfer_token: transferToken,
        transfer_token_expires_at: transferTokenExpiresAt,
        ticket_type_id: ticket_type_id || null,
      })
      .select()
      .single()

    if (ticketError || !ticket) {
      console.error('Failed to create ticket:', ticketError)
      return new Response(
        JSON.stringify({ error: 'Failed to create ticket', details: ticketError?.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Created ticket ${ticket.id} with number ${ticketNumber}`)

    // 5. Charge organizer's card for platform fee
    let feeCharged = false
    let feePaymentIntentId: string | null = null
    let feeChargeError: string | null = null

    if (platformFeeCents > 0) {
      try {
        // Create a PaymentIntent for the platform fee
        const paymentIntent = await stripe.paymentIntents.create({
          amount: platformFeeCents,
          currency: 'usd',
          customer: event.organizer_stripe_customer_id,
          payment_method: event.organizer_payment_method_id,
          off_session: true,
          confirm: true,
          metadata: {
            type: 'cash_sale_platform_fee',
            event_id,
            event_title: event.title,
            ticket_id: ticket.id,
            ticket_number: ticketNumber,
            sale_amount_cents: amount_cents.toString(),
            seller_id: user.id,
          },
        })

        feePaymentIntentId = paymentIntent.id
        feeCharged = paymentIntent.status === 'succeeded'

        if (!feeCharged) {
          console.warn(`Fee payment not immediately successful: ${paymentIntent.status}`)
          feeChargeError = `Payment status: ${paymentIntent.status}`
        } else {
          console.log(`Platform fee charged: ${platformFeeCents} cents (PI: ${paymentIntent.id})`)
        }
      } catch (stripeError: unknown) {
        console.error('Failed to charge platform fee:', stripeError)
        const errorMessage = stripeError instanceof Error ? stripeError.message : 'Unknown Stripe error'
        feeChargeError = errorMessage

        // Don't fail the sale, but record the error
        // The organizer will need to be charged manually or disable cash sales
      }
    } else {
      // Free tickets have no fee
      feeCharged = true
    }

    // 6. Create cash_transactions record
    const { data: cashTx, error: cashTxError } = await supabaseAdmin
      .from('cash_transactions')
      .insert({
        event_id,
        seller_id: user.id,
        ticket_id: ticket.id,
        amount_cents,
        platform_fee_cents: platformFeeCents,
        currency: 'USD',
        status: 'pending', // Will be marked 'collected' when organizer confirms
        fee_charged: feeCharged,
        fee_payment_intent_id: feePaymentIntentId,
        fee_charge_error: feeChargeError,
        customer_name: customer_name || null,
        customer_email: customer_email || null,
        delivery_method,
      })
      .select()
      .single()

    if (cashTxError) {
      console.error('Failed to create cash transaction record:', cashTxError)
      // Don't fail - the ticket was already created
    }

    // 7. Update ticket type sold count if applicable
    if (ticket_type_id) {
      const { error: rpcError } = await supabaseAdmin.rpc('increment_ticket_type_sold', {
        p_ticket_type_id: ticket_type_id,
      })
      if (rpcError) {
        console.error('Failed to increment ticket type sold count:', rpcError)
      }
    }

    // 8. Send email notification if customer_email is provided
    let emailSent = false
    if (customer_email && delivery_method !== 'nfc') {
      try {
        // Generate QR code data for the ticket
        const qrData = `tickety:ticket:${ticket.id}`

        // Update ticket with QR code
        await supabaseAdmin
          .from('tickets')
          .update({ qr_code: qrData })
          .eq('id', ticket.id)

        // Call send-ticket-email function
        const emailResponse = await fetch(
          `${supabaseUrl}/functions/v1/send-ticket-email`,
          {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${supabaseServiceKey}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              ticket_id: ticket.id,
              customer_email,
              customer_name: customer_name || null,
            }),
          }
        )

        if (emailResponse.ok) {
          emailSent = true
          console.log(`Email sent to ${customer_email} for ticket ${ticket.id}`)
        } else {
          const emailError = await emailResponse.text()
          console.error('Failed to send ticket email:', emailError)
        }
      } catch (emailErr) {
        console.error('Error sending ticket email:', emailErr)
        // Don't fail the sale if email fails
      }
    }

    // Build response
    const response: Record<string, unknown> = {
      success: true,
      ticket: {
        id: ticket.id,
        ticket_number: ticketNumber,
        event_id,
        event_title: event.title,
        amount_cents,
        customer_name,
        customer_email,
        delivery_method,
        status: 'valid',
      },
      cash_transaction_id: cashTx?.id,
      platform_fee_cents: platformFeeCents,
      fee_charged: feeCharged,
      email_sent: emailSent,
    }

    // Include transfer token for NFC delivery
    if (delivery_method === 'nfc' && transferToken) {
      response.transfer_token = transferToken
      response.transfer_token_expires_at = transferTokenExpiresAt
    }

    // Warn if fee wasn't charged
    if (!feeCharged && platformFeeCents > 0) {
      response.warning = 'Platform fee could not be charged. Please check organizer payment method.'
      response.fee_error = feeChargeError
    }

    return new Response(
      JSON.stringify(response),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error: unknown) {
    console.error('Error processing cash sale:', error)
    const errorMessage = error instanceof Error ? error.message : 'Internal server error'
    return new Response(
      JSON.stringify({ error: errorMessage }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

/**
 * Generate a unique ticket number.
 * Format: XXXXXX (6 alphanumeric characters)
 */
function generateTicketNumber(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' // Excluding confusable chars
  const array = new Uint8Array(6)
  crypto.getRandomValues(array)
  return Array.from(array, (byte) => chars[byte % chars.length]).join('')
}

/**
 * Generate a secure transfer token for NFC delivery.
 * Format: 64-character hex string
 */
function generateTransferToken(): string {
  const array = new Uint8Array(32)
  crypto.getRandomValues(array)
  return Array.from(array, (byte) => byte.toString(16).padStart(2, '0')).join('')
}
