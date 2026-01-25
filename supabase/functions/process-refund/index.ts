import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import Stripe from 'https://esm.sh/stripe@13.10.0?target=deno'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
})

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface RefundRequest {
  payment_id: string
  reason?: string
}

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

    // Create Supabase client with service role for full access
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

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

    const body: RefundRequest = await req.json()
    const { payment_id, reason } = body

    if (!payment_id) {
      return new Response(
        JSON.stringify({ error: 'Missing payment_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get the payment record
    const { data: payment, error: paymentError } = await supabaseAdmin
      .from('payments')
      .select('*, events(organizer_id)')
      .eq('id', payment_id)
      .single()

    if (paymentError || !payment) {
      return new Response(
        JSON.stringify({ error: 'Payment not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check if already refunded
    if (payment.status === 'refunded') {
      return new Response(
        JSON.stringify({ error: 'Payment already refunded' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify user has permission (must be payment owner or event organizer)
    const isOwner = payment.user_id === user.id
    const isOrganizer = payment.events?.organizer_id === user.id

    // Check if user is admin/organizer staff for the event
    const { data: staffRecord } = await supabaseAdmin
      .from('event_staff')
      .select('role')
      .eq('event_id', payment.event_id)
      .eq('user_id', user.id)
      .single()

    const isAdmin = staffRecord?.role === 'admin'

    if (!isOwner && !isOrganizer && !isAdmin) {
      return new Response(
        JSON.stringify({ error: 'You do not have permission to refund this payment' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check if payment has a Stripe charge to refund
    if (!payment.stripe_payment_intent_id) {
      return new Response(
        JSON.stringify({ error: 'No Stripe payment associated with this record' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Create Stripe refund
    const refund = await stripe.refunds.create({
      payment_intent: payment.stripe_payment_intent_id,
      reason: reason === 'duplicate' ? 'duplicate' :
              reason === 'fraudulent' ? 'fraudulent' :
              'requested_by_customer',
      metadata: {
        payment_id,
        refunded_by: user.id,
      },
    })

    // Update payment status
    const { data: updatedPayment, error: updateError } = await supabaseAdmin
      .from('payments')
      .update({
        status: 'refunded',
        metadata: {
          ...payment.metadata,
          refund_id: refund.id,
          refund_reason: reason,
          refunded_by: user.id,
          refunded_at: new Date().toISOString(),
        },
      })
      .eq('id', payment_id)
      .select()
      .single()

    if (updateError) {
      console.error('Failed to update payment status:', updateError)
      // Don't fail - the refund was processed
    }

    // Update ticket status if exists
    if (payment.ticket_id) {
      await supabaseAdmin
        .from('tickets')
        .update({ status: 'refunded' })
        .eq('id', payment.ticket_id)
    }

    console.log(`Refund processed: ${refund.id} for payment ${payment_id}`)

    return new Response(
      JSON.stringify({
        success: true,
        refund_id: refund.id,
        payment: updatedPayment || { ...payment, status: 'refunded' },
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )

  } catch (error) {
    console.error('Error processing refund:', error)

    // Handle Stripe-specific errors
    if (error.type === 'StripeCardError') {
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({ error: error.message || 'Failed to process refund' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
