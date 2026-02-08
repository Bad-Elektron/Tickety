import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import Stripe from 'https://esm.sh/stripe@14.21.0'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
})

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const supabase = createClient(supabaseUrl, supabaseServiceKey)

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Verify caller is using service role key (admin-only operation)
    const authHeader = req.headers.get('Authorization')
    const token = authHeader?.replace('Bearer ', '')
    if (token !== supabaseServiceKey) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized - service role key required' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Fetch completed payments missing receipt_url
    const { data: payments, error: fetchError } = await supabase
      .from('payments')
      .select('id, stripe_payment_intent_id')
      .eq('status', 'completed')
      .is('receipt_url', null)
      .not('stripe_payment_intent_id', 'is', null)

    if (fetchError) {
      throw new Error(`Failed to fetch payments: ${fetchError.message}`)
    }

    if (!payments || payments.length === 0) {
      return new Response(
        JSON.stringify({ message: 'No payments to backfill', updated: 0 }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Found ${payments.length} payments to backfill`)

    let updated = 0
    let failed = 0
    const errors: string[] = []

    for (const payment of payments) {
      try {
        // Retrieve PaymentIntent from Stripe
        const pi = await stripe.paymentIntents.retrieve(payment.stripe_payment_intent_id)
        const chargeId = pi.latest_charge as string

        if (!chargeId) {
          errors.push(`${payment.id}: no charge found`)
          failed++
          continue
        }

        // Retrieve Charge to get receipt URL
        const charge = await stripe.charges.retrieve(chargeId)

        if (!charge.receipt_url) {
          errors.push(`${payment.id}: charge has no receipt_url`)
          failed++
          continue
        }

        // Update the payment record
        const { error: updateError } = await supabase
          .from('payments')
          .update({
            receipt_url: charge.receipt_url,
            stripe_charge_id: chargeId,
          })
          .eq('id', payment.id)

        if (updateError) {
          errors.push(`${payment.id}: update failed - ${updateError.message}`)
          failed++
        } else {
          updated++
          console.log(`Updated payment ${payment.id} with receipt URL`)
        }
      } catch (err) {
        errors.push(`${payment.id}: ${err.message}`)
        failed++
      }
    }

    return new Response(
      JSON.stringify({
        total: payments.length,
        updated,
        failed,
        errors: errors.length > 0 ? errors : undefined,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Backfill error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
