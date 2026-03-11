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

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const body = await req.json()
    const { payment_intent_id, do_transfer } = body

    if (!payment_intent_id) {
      return new Response(JSON.stringify({ error: 'Missing payment_intent_id' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Get the PI from Stripe
    const pi = await stripe.paymentIntents.retrieve(payment_intent_id)

    // Check for transfers related to this charge
    let transfers: any[] = []
    if (pi.latest_charge) {
      const transferList = await stripe.transfers.list({
        limit: 10,
      })
      // Filter for transfers with this source_transaction
      transfers = transferList.data.filter(
        (t: any) => t.source_transaction === pi.latest_charge
      )
    }

    // Check seller account balance
    const sellerAccountId = pi.metadata.seller_account_id
    let sellerBalance = null
    let sellerAccount = null
    if (sellerAccountId) {
      try {
        sellerAccount = await stripe.accounts.retrieve(sellerAccountId)
        sellerBalance = await stripe.balance.retrieve({ stripeAccount: sellerAccountId })
      } catch (e: any) {
        sellerBalance = { error: e.message }
      }
    }

    // Optionally create the missing transfer (settlement-currency aware)
    let transferResult: any = null
    if (do_transfer && sellerAccountId && pi.latest_charge) {
      const sellerAmountCents = parseInt(pi.metadata.seller_amount_cents || '0')
      if (sellerAmountCents > 0) {
        // Try source_transaction with settlement currency first
        try {
          const charge = await stripe.charges.retrieve(pi.latest_charge as string, { expand: ['balance_transaction'] })
          const balanceTx = charge.balance_transaction as any

          if (balanceTx && typeof balanceTx === 'object') {
            const settlementCurrency = balanceTx.currency
            const netSettlement = balanceTx.amount - balanceTx.fee
            const sellerFraction = sellerAmountCents / pi.amount
            const sellerSettlementAmount = Math.round(netSettlement * sellerFraction)

            const transfer = await stripe.transfers.create({
              amount: sellerSettlementAmount,
              currency: settlementCurrency,
              destination: sellerAccountId,
              source_transaction: pi.latest_charge as string,
              metadata: {
                resale_listing_id: pi.metadata.resale_listing_id,
                ticket_id: pi.metadata.ticket_id,
                payment_intent_id: pi.id,
                original_currency: pi.currency,
                original_seller_amount: String(sellerAmountCents),
                type: 'resale_seller_payout_manual',
              },
            })
            transferResult = {
              success: true,
              transfer_id: transfer.id,
              amount: transfer.amount,
              currency: settlementCurrency,
              original_amount: sellerAmountCents,
              original_currency: pi.currency,
            }
          } else {
            throw new Error('Balance transaction not available')
          }
        } catch (e: any) {
          // Fallback: direct balance transfer in charge currency
          try {
            const transfer = await stripe.transfers.create({
              amount: sellerAmountCents,
              currency: pi.currency,
              destination: sellerAccountId,
              metadata: {
                resale_listing_id: pi.metadata.resale_listing_id,
                ticket_id: pi.metadata.ticket_id,
                payment_intent_id: pi.id,
                type: 'resale_seller_payout_manual_fallback',
              },
            })
            transferResult = { success: true, transfer_id: transfer.id, amount: transfer.amount, currency: pi.currency, fallback: true }
          } catch (e2: any) {
            transferResult = { success: false, error: e2.message, code: e2.code, first_error: e.message }
          }
        }
      }
    }

    return new Response(JSON.stringify({
      transfer_result: transferResult,
      payment_intent: {
        id: pi.id,
        status: pi.status,
        amount: pi.amount,
        currency: pi.currency,
        latest_charge: pi.latest_charge,
        metadata: pi.metadata,
      },
      transfers: transfers.map(t => ({
        id: t.id,
        amount: t.amount,
        currency: t.currency,
        destination: t.destination,
        source_transaction: t.source_transaction,
        created: t.created,
      })),
      seller_account: sellerAccount ? {
        id: sellerAccount.id,
        charges_enabled: sellerAccount.charges_enabled,
        payouts_enabled: sellerAccount.payouts_enabled,
        details_submitted: sellerAccount.details_submitted,
        capabilities: sellerAccount.capabilities,
      } : null,
      seller_balance: sellerBalance,
    }, null, 2), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })

  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})
