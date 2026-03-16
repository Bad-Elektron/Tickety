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

      case 'payment_intent.processing':
        await handlePaymentProcessing(event.data.object as Stripe.PaymentIntent)
        break

      case 'payment_intent.payment_failed':
        await handlePaymentFailed(event.data.object as Stripe.PaymentIntent)
        break

      case 'charge.refunded':
        await handleChargeRefunded(event.data.object as Stripe.Charge)
        break

      // Invoice events (for subscription payment tracking)
      case 'invoice.paid':
        await handleInvoicePaid(event.data.object as Stripe.Invoice)
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

      // Identity verification events
      case 'identity.verification_session.verified':
        await handleIdentityVerified(event.data.object)
        break

      case 'identity.verification_session.requires_input':
        await handleIdentityFailed(event.data.object)
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

  // Try to fetch receipt URL from the charge
  let receiptUrl: string | null = null
  const chargeId = paymentIntent.latest_charge as string
  if (chargeId) {
    try {
      const charge = await stripe.charges.retrieve(chargeId)
      receiptUrl = charge.receipt_url || null
    } catch (err) {
      console.error('Failed to fetch charge for receipt URL:', err.message)
    }
  }

  // Update payment record (or create if it doesn't exist)
  const { data: existingPayment } = await supabase
    .from('payments')
    .select('id, metadata, seat_selections')
    .eq('stripe_payment_intent_id', paymentIntent.id)
    .maybeSingle()

  // Extract fee metadata (present when service fees were applied)
  const serviceFeeCents = parseInt(paymentIntent.metadata.service_fee_cents || '0', 10)

  if (existingPayment) {
    // Update existing record
    const { error: updateError } = await supabase
      .from('payments')
      .update({
        status: 'completed',
        stripe_charge_id: chargeId,
        ...(receiptUrl && { receipt_url: receiptUrl }),
      })
      .eq('id', existingPayment.id)

    if (updateError) {
      console.error('Failed to update payment record:', updateError)
    }
  } else {
    // Payment record was never created — insert it now
    console.log('No existing payment record found, creating one from webhook')
    const { error: insertError } = await supabase
      .from('payments')
      .insert({
        user_id,
        event_id,
        amount_cents: paymentIntent.amount,
        currency: paymentIntent.currency,
        status: 'completed',
        type: type || 'primary_purchase',
        stripe_payment_intent_id: paymentIntent.id,
        stripe_charge_id: chargeId,
        platform_fee_cents: serviceFeeCents,
        ...(receiptUrl && { receipt_url: receiptUrl }),
        metadata: {
          event_title: paymentIntent.metadata.event_title || null,
          created_by_webhook: true,
        },
      })

    if (insertError) {
      console.error('Failed to insert payment record from webhook:', insertError)
    }
  }

  // Handle wallet top-up settlement (ACH succeeded)
  if (type === 'wallet_top_up') {
    await handleWalletTopUpSucceeded(paymentIntent)
    return
  }

  // Handle ACH direct purchase settlement — tickets already created, just mark completed
  if (type === 'ach_purchase') {
    console.log(`ACH purchase settled: ${paymentIntent.id} for event ${event_id}`)
    // Payment already updated to 'completed' above. Tickets already exist. Nothing else needed.
    return
  }

  // Handle merch purchase — update order to paid, decrement inventory
  if (type === 'merch_purchase') {
    console.log(`Merch purchase succeeded: ${paymentIntent.id}`)
    const { product_id: merchProductId, variant_id: merchVariantId, quantity: merchQtyStr } = paymentIntent.metadata
    const merchQty = parseInt(merchQtyStr || '1', 10)

    // Update merch_order to paid
    const { error: orderUpdateError } = await supabase
      .from('merch_orders')
      .update({ status: 'paid', updated_at: new Date().toISOString() })
      .eq('stripe_payment_intent_id', paymentIntent.id)

    if (orderUpdateError) {
      console.error('Failed to update merch order:', orderUpdateError)
    }

    // Decrement inventory if variant specified
    if (merchVariantId) {
      const { data: variant } = await supabase
        .from('merch_variants')
        .select('inventory_count')
        .eq('id', merchVariantId)
        .single()

      if (variant && variant.inventory_count !== null) {
        await supabase
          .from('merch_variants')
          .update({ inventory_count: Math.max(0, variant.inventory_count - merchQty) })
          .eq('id', merchVariantId)
      }
    }
    return
  }

  // Skip ticket creation for test events (non-UUID event IDs)
  const isTestEvent = event_id?.startsWith('test-')
  if (isTestEvent) {
    console.log('Skipping ticket creation for test event')
    return
  }

  // Create tickets for the user
  if (type === 'primary_purchase' || type === 'vendor_pos' || type === 'waitlist_auto_purchase') {
    // Get user info for ticket
    const { data: profile } = await supabase
      .from('profiles')
      .select('email, display_name')
      .eq('id', user_id)
      .single()

    // Get user's auth email as fallback
    const { data: authData } = await supabase.auth.admin.getUserById(user_id)
    const ownerEmail = profile?.email || authData?.user?.email || null
    const ownerName = profile?.display_name || null

    // Calculate price per ticket (use base amount from metadata when fees were applied)
    const baseAmountCents = parseInt(paymentIntent.metadata.base_amount_cents || '0', 10)
    const pricePerTicket = baseAmountCents
      ? Math.round(baseAmountCents / quantity)
      : Math.round(paymentIntent.amount / quantity)

    // Get seat_selections and ticket_items from payment record metadata
    let seatSelections: any[] | null = existingPayment?.seat_selections as any[] | null
    const ticketItems: any[] | null = existingPayment?.metadata?.ticket_items as any[] | null
    console.log(`[ticket-creation] existingPayment=${!!existingPayment}, hasMetadata=${!!existingPayment?.metadata}, ticketItems=${JSON.stringify(ticketItems)}`)

    // Build a flat list of per-ticket category/icon from ticket_items
    // e.g. [{ticket_type_id, quantity: 2, category: 'entry'}, {ticket_type_id, quantity: 1, category: 'redeemable', item_icon: '🎸'}]
    // → ['entry', 'entry', 'redeemable'] with icons [null, null, '🎸']
    const ticketCategories: string[] = []
    const ticketIcons: (string | null)[] = []
    const ticketTypeNames: (string | null)[] = []
    if (ticketItems && Array.isArray(ticketItems)) {
      // Fetch ticket type names from DB
      const typeIds = ticketItems.map((ti: any) => ti.ticket_type_id).filter(Boolean)
      let typeNameMap: Record<string, string> = {}
      if (typeIds.length > 0) {
        const { data: dbTypes } = await supabase
          .from('event_ticket_types')
          .select('id, name')
          .in('id', typeIds)
        if (dbTypes) {
          for (const dt of dbTypes) {
            typeNameMap[dt.id] = dt.name
          }
        }
      }
      for (const item of ticketItems) {
        const qty = item.quantity || 1
        const typeName = typeNameMap[item.ticket_type_id] || null
        for (let j = 0; j < qty; j++) {
          ticketCategories.push(item.category || 'entry')
          ticketIcons.push(item.item_icon || null)
          ticketTypeNames.push(typeName)
        }
      }
    }

    // Create tickets for each quantity
    const ticketIds: string[] = []
    for (let i = 0; i < quantity; i++) {
      // Generate unique ticket number
      const timestamp = Date.now().toString().substring(7)
      const random = Math.floor(Math.random() * 9999).toString().padLeft(4, '0')
      const ticketNumber = `TKT-${timestamp}-${random}`

      // Assign seat data from seat_selections if present
      const seatData = seatSelections?.[i]
      // Assign category and type name from ticket_items breakdown
      const category = ticketCategories[i] || 'entry'
      const itemIcon = ticketIcons[i] || null
      const typeName = ticketTypeNames[i] || null
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
          category,
          ...(itemIcon && { item_icon: itemIcon }),
          ...(typeName && { ticket_type_name: typeName }),
          ...(seatData && {
            venue_section_id: seatData.section_id,
            seat_id: seatData.seat_id,
            seat_label: seatData.seat_label,
          }),
        })
        .select()
        .single()

      if (ticketError) {
        console.error(`Failed to create ticket ${i + 1}/${quantity}:`, ticketError)
        continue
      }

      ticketIds.push(ticket.id)
      console.log(`Ticket ${i + 1}/${quantity} created: ${ticketNumber} (${category})`)
    }

    // Link first ticket to payment (for reference)
    if (ticketIds.length > 0) {
      await supabase
        .from('payments')
        .update({ ticket_id: ticketIds[0] })
        .eq('stripe_payment_intent_id', paymentIntent.id)
    }

    // Clean up seat holds after ticket creation
    if (seatSelections && seatSelections.length > 0) {
      const seatIds = seatSelections.map((s: any) => s.seat_id)
      await supabase
        .from('seat_holds')
        .delete()
        .eq('event_id', event_id)
        .in_('seat_id', seatIds)
      console.log(`Cleaned up ${seatIds.length} seat holds`)
    }

    console.log(`Created ${ticketIds.length} tickets for payment ${paymentIntent.id}`)

    // Enqueue NFT minting (fire-and-forget, never blocks ticket delivery)
    if (ticketIds.length > 0 && event_id) {
      enqueueNftMints(event_id, user_id, ticketIds).catch(err =>
        console.error('enqueueNftMints failed (non-blocking):', err.message)
      )
    }

    // Generate wallet passes (fire-and-forget, never blocks ticket delivery)
    if (ticketIds.length > 0) {
      enqueueWalletPasses(ticketIds).catch(err =>
        console.error('enqueueWalletPasses failed (non-blocking):', err.message)
      )
    }

    // Update widget checkout session status if this came from the widget
    if (existingPayment?.metadata?.source === 'widget') {
      await supabase
        .from('widget_checkout_sessions')
        .update({ status: 'completed', updated_at: new Date().toISOString() })
        .eq('stripe_payment_intent_id', paymentIntent.id)
      console.log('Widget checkout session marked completed')
    }
  }

  // For resale purchases: transfer ticket ownership + mark listing sold + enqueue NFT transfer
  if (type === 'resale_purchase') {
    const resaleListingId = paymentIntent.metadata.resale_listing_id
    const ticketId = paymentIntent.metadata.ticket_id
    const buyerId = paymentIntent.metadata.buyer_id
    const sellerId = paymentIntent.metadata.seller_id

    if (!resaleListingId || !ticketId || !buyerId) {
      console.error('Missing resale metadata:', { resaleListingId, ticketId, buyerId })
      return
    }

    // Get buyer info
    const { data: buyerProfile } = await supabase
      .from('profiles')
      .select('email, display_name')
      .eq('id', buyerId)
      .single()

    const { data: buyerAuth } = await supabase.auth.admin.getUserById(buyerId)
    const buyerEmail = buyerProfile?.email || buyerAuth?.user?.email || null
    const buyerName = buyerProfile?.display_name || null

    // Transfer ticket ownership
    const { error: ticketError } = await supabase
      .from('tickets')
      .update({
        sold_by: buyerId,
        owner_email: buyerEmail,
        owner_name: buyerName,
        listing_status: 'none',
        listing_price_cents: null,
      })
      .eq('id', ticketId)

    if (ticketError) {
      console.error('Failed to transfer ticket ownership:', ticketError)
    } else {
      console.log(`Ticket ${ticketId} ownership transferred from ${sellerId} to ${buyerId}`)
    }

    // Mark listing as sold
    const { error: listingError } = await supabase
      .from('resale_listings')
      .update({ status: 'sold' })
      .eq('id', resaleListingId)

    if (listingError) {
      console.error('Failed to mark listing as sold:', listingError)
    }

    // Transfer funds to seller's Stripe account (Separate Charges and Transfers pattern)
    // The charge was made on the platform account, now we transfer the seller's portion.
    //
    // Currency handling: The platform settles in EUR. When a USD charge is made,
    // Stripe converts to EUR for the platform's balance. source_transaction Transfers
    // must use the balance transaction's currency (EUR), not the charge currency (USD).
    // We read the balance transaction to get the correct settlement currency and amount,
    // then calculate the seller's share proportionally.
    const sellerAccountId = paymentIntent.metadata.seller_account_id
    const sellerAmountCents = parseInt(paymentIntent.metadata.seller_amount_cents || '0')

    if (sellerAccountId && sellerAmountCents > 0) {
      const chargeId = paymentIntent.latest_charge as string
      let transferSuccess = false

      if (chargeId) {
        try {
          // Retrieve the charge's balance transaction to get settlement currency/amount
          const charge = await stripe.charges.retrieve(chargeId, { expand: ['balance_transaction'] })
          const balanceTx = charge.balance_transaction as Stripe.BalanceTransaction | null

          if (balanceTx && typeof balanceTx === 'object') {
            const settlementCurrency = balanceTx.currency // e.g. 'eur'
            const settlementAmount = balanceTx.amount      // gross amount in settlement currency
            const stripeFee = balanceTx.fee                // Stripe's processing fee
            const netSettlement = settlementAmount - stripeFee

            // Calculate seller's share proportionally:
            // sellerAmountCents / chargeAmount gives the seller's fraction in charge currency,
            // apply that fraction to the net settlement amount in settlement currency
            const chargeAmount = paymentIntent.amount
            const sellerFraction = sellerAmountCents / chargeAmount
            const sellerSettlementAmount = Math.round(netSettlement * sellerFraction)

            console.log(`Settlement: ${settlementAmount} ${settlementCurrency} (net ${netSettlement}), seller fraction: ${sellerFraction.toFixed(4)}, seller gets: ${sellerSettlementAmount} ${settlementCurrency}`)

            if (sellerSettlementAmount > 0) {
              const transfer = await stripe.transfers.create({
                amount: sellerSettlementAmount,
                currency: settlementCurrency,
                destination: sellerAccountId,
                source_transaction: chargeId,
                metadata: {
                  resale_listing_id: resaleListingId,
                  ticket_id: ticketId,
                  buyer_id: buyerId,
                  seller_id: sellerId,
                  original_currency: paymentIntent.currency,
                  original_seller_amount: String(sellerAmountCents),
                  type: 'resale_seller_payout',
                },
              })
              console.log(`Transfer ${transfer.id} created (source_transaction): ${sellerSettlementAmount} ${settlementCurrency} to ${sellerAccountId}`)
              transferSuccess = true
            }
          } else {
            console.warn('Balance transaction not available or not expanded, trying direct...')
          }
        } catch (err: any) {
          console.warn(`source_transaction transfer failed (${err.code}): ${err.message}, trying direct balance...`)
        }
      }

      // Fallback: transfer from platform available balance in charge currency (no source_transaction)
      // This works when platform has available funds in the charge currency
      if (!transferSuccess) {
        try {
          const transfer = await stripe.transfers.create({
            amount: sellerAmountCents,
            currency: paymentIntent.currency,
            destination: sellerAccountId,
            metadata: {
              resale_listing_id: resaleListingId,
              ticket_id: ticketId,
              buyer_id: buyerId,
              seller_id: sellerId,
              payment_intent_id: paymentIntent.id,
              type: 'resale_seller_payout',
            },
          })
          console.log(`Transfer ${transfer.id} created (balance): ${sellerAmountCents} ${paymentIntent.currency} to ${sellerAccountId}`)
          transferSuccess = true
        } catch (err: any) {
          console.error(`Balance transfer also failed (${err.code}): ${err.message}`)
          // Transfer can be retried manually via debug-resale function
        }
      }
    } else {
      console.warn('Missing seller account or amount for transfer:', { sellerAccountId, sellerAmountCents })
    }

    // Enqueue NFT transfer if ticket has a minted NFT
    const { data: ticketNft } = await supabase
      .from('tickets')
      .select('nft_minted, nft_policy_id, nft_asset_id')
      .eq('id', ticketId)
      .single()

    if (ticketNft?.nft_minted) {
      enqueueNftTransfer(ticketId, paymentIntent.metadata.event_id, buyerId, sellerId, resaleListingId).catch(err =>
        console.error('enqueueNftTransfer failed (non-blocking):', err.message)
      )
    }

    console.log(`Resale purchase completed: listing ${resaleListingId}, ticket ${ticketId}`)
  }

  // For favor ticket purchases, create ticket and update the offer
  if (type === 'favor_ticket_purchase') {
    const offer_id = paymentIntent.metadata.offer_id
    if (!offer_id) {
      console.error('No offer_id in favor_ticket_purchase metadata')
      return
    }

    // Fetch the offer
    const { data: offer, error: offerError } = await supabase
      .from('ticket_offers')
      .select('*')
      .eq('id', offer_id)
      .single()

    if (offerError || !offer) {
      console.error('Offer not found for favor ticket purchase:', offer_id)
      return
    }

    // Get user info
    const { data: profile } = await supabase
      .from('profiles')
      .select('email, display_name')
      .eq('id', user_id)
      .single()

    const { data: authData } = await supabase.auth.admin.getUserById(user_id)
    const ownerEmail = profile?.email || authData?.user?.email || null
    const ownerName = profile?.display_name || null

    // Generate ticket number
    const timestamp = Date.now().toString().substring(7)
    const random = Math.floor(Math.random() * 9999).toString().padLeft(4, '0')
    const ticketNumber = `TKT-${timestamp}-${random}`

    // Use base amount (before fees) for ticket price, fall back to total for backward compat
    const favorBaseAmount = parseInt(paymentIntent.metadata.base_amount_cents || '0', 10)

    // Create ticket with the correct mode
    const { data: ticket, error: ticketError } = await supabase
      .from('tickets')
      .insert({
        event_id: offer.event_id,
        ticket_number: ticketNumber,
        owner_email: ownerEmail,
        owner_name: ownerName,
        owner_user_id: user_id,
        price_paid_cents: favorBaseAmount || paymentIntent.amount,
        currency: paymentIntent.currency.toUpperCase(),
        status: 'valid',
        sold_by: offer.organizer_id,
        ticket_mode: offer.ticket_mode,
        offer_id: offer.id,
      })
      .select()
      .single()

    if (ticketError) {
      console.error('Failed to create favor ticket:', ticketError)
      return
    }

    // Update offer status
    await supabase
      .from('ticket_offers')
      .update({
        status: 'accepted',
        ticket_id: ticket.id,
        recipient_user_id: user_id,
      })
      .eq('id', offer_id)

    // Link ticket to payment
    await supabase
      .from('payments')
      .update({ ticket_id: ticket.id })
      .eq('stripe_payment_intent_id', paymentIntent.id)

    console.log(`Favor ticket created: ${ticketNumber} for offer ${offer_id}`)
  }
}

async function handlePaymentProcessing(paymentIntent: Stripe.PaymentIntent) {
  const { type } = paymentIntent.metadata
  console.log(`Payment processing: ${paymentIntent.id}, type: ${type}`)

  // ACH payments go through a processing state before succeeding
  if (type === 'wallet_top_up') {
    console.log(`ACH top-up processing for user ${paymentIntent.metadata.supabase_user_id}`)
  }
}

async function handleWalletTopUpSucceeded(paymentIntent: Stripe.PaymentIntent) {
  const userId = paymentIntent.metadata.supabase_user_id
  const creditAmountCents = parseInt(paymentIntent.metadata.credit_amount_cents || '0', 10)
  const achFeeCents = parseInt(paymentIntent.metadata.ach_fee_cents || '0', 10)

  console.log(`Wallet top-up succeeded: ${paymentIntent.id}, credit: ${creditAmountCents} cents for user ${userId}`)

  if (!userId || !creditAmountCents) {
    console.error('Missing metadata in wallet top-up PaymentIntent:', paymentIntent.id)
    return
  }

  // Move funds from pending_cents to available_cents
  const { data: wallet, error: walletError } = await supabase
    .from('wallet_balances')
    .select('available_cents, pending_cents')
    .eq('user_id', userId)
    .single()

  if (walletError || !wallet) {
    console.error('Wallet not found for top-up settlement:', userId)
    return
  }

  const newAvailable = wallet.available_cents + creditAmountCents
  const newPending = Math.max(0, wallet.pending_cents - creditAmountCents)

  const { error: updateError } = await supabase
    .from('wallet_balances')
    .update({
      available_cents: newAvailable,
      pending_cents: newPending,
    })
    .eq('user_id', userId)

  if (updateError) {
    console.error('Failed to update wallet balance on top-up settlement:', updateError)
    return
  }

  // Update wallet transaction: change from pending to completed
  await supabase
    .from('wallet_transactions')
    .update({
      type: 'ach_top_up',
      balance_after_cents: newAvailable,
      description: `ACH top-up of $${(creditAmountCents / 100).toFixed(2)} (settled)`,
    })
    .eq('stripe_payment_intent_id', paymentIntent.id)

  console.log(`Wallet top-up settled for user ${userId}: +${creditAmountCents} cents, new available: ${newAvailable}`)
}

async function handleWalletTopUpFailed(paymentIntent: Stripe.PaymentIntent) {
  const userId = paymentIntent.metadata.supabase_user_id
  const creditAmountCents = parseInt(paymentIntent.metadata.credit_amount_cents || '0', 10)

  console.log(`Wallet top-up failed: ${paymentIntent.id} for user ${userId}`)

  if (!userId) return

  // Remove from pending_cents
  const { data: wallet } = await supabase
    .from('wallet_balances')
    .select('pending_cents')
    .eq('user_id', userId)
    .single()

  if (wallet) {
    const newPending = Math.max(0, wallet.pending_cents - creditAmountCents)
    await supabase
      .from('wallet_balances')
      .update({ pending_cents: newPending })
      .eq('user_id', userId)
  }

  // Delete the failed wallet transaction
  await supabase
    .from('wallet_transactions')
    .delete()
    .eq('stripe_payment_intent_id', paymentIntent.id)

  console.log(`Cleaned up failed wallet top-up for user ${userId}`)
}

async function handlePaymentFailed(paymentIntent: Stripe.PaymentIntent) {
  console.log(`Payment failed: ${paymentIntent.id}`)

  // Handle wallet top-up failure
  if (paymentIntent.metadata?.type === 'wallet_top_up') {
    await handleWalletTopUpFailed(paymentIntent)
  }

  // Handle ACH direct purchase failure — revoke tickets
  if (paymentIntent.metadata?.type === 'ach_purchase') {
    await handleACHPurchaseFailed(paymentIntent)
  }

  // Find the payment first so we can cancel referral earnings
  const { data: failedPayment } = await supabase
    .from('payments')
    .select('id')
    .eq('stripe_payment_intent_id', paymentIntent.id)
    .maybeSingle()

  const { error } = await supabase
    .from('payments')
    .update({ status: 'failed' })
    .eq('stripe_payment_intent_id', paymentIntent.id)

  if (error) {
    console.error('Failed to update payment status:', error)
  }

  // Cancel any referral earnings for this payment
  if (failedPayment?.id) {
    const { error: earningsError } = await supabase
      .from('referral_earnings')
      .update({ status: 'cancelled' })
      .eq('payment_id', failedPayment.id)
      .eq('status', 'pending')

    if (earningsError) {
      console.error('Failed to cancel referral earnings:', earningsError)
    }
  }
}

async function handleACHPurchaseFailed(paymentIntent: Stripe.PaymentIntent) {
  const eventId = paymentIntent.metadata.event_id
  const userId = paymentIntent.metadata.user_id

  console.log(`ACH purchase failed: ${paymentIntent.id} for event ${eventId}, user ${userId}`)

  // Find tickets created for this payment
  const { data: payment } = await supabase
    .from('payments')
    .select('id')
    .eq('stripe_payment_intent_id', paymentIntent.id)
    .maybeSingle()

  if (payment) {
    // Find all tickets linked to this payment by matching event_id, user_id,
    // and created around the same time as the payment
    const { data: tickets } = await supabase
      .from('tickets')
      .select('id')
      .eq('event_id', eventId)
      .eq('sold_by', userId)
      .eq('status', 'valid')

    if (tickets && tickets.length > 0) {
      // Revoke tickets by marking them as cancelled
      const ticketIds = tickets.map((t: { id: string }) => t.id)
      const { error: revokeError } = await supabase
        .from('tickets')
        .update({ status: 'cancelled' })
        .in('id', ticketIds)

      if (revokeError) {
        console.error('Failed to revoke tickets for failed ACH:', revokeError)
      } else {
        console.log(`Revoked ${ticketIds.length} tickets for failed ACH payment ${paymentIntent.id}`)
      }
    }
  }

  // Create notification for the user about the failed payment
  if (userId) {
    try {
      await supabase.from('notifications').insert({
        user_id: userId,
        type: 'payment_failed',
        title: 'Bank Payment Failed',
        body: `Your bank payment for ${paymentIntent.metadata.event_title || 'an event'} could not be processed. Your tickets have been cancelled.`,
        data: {
          event_id: eventId,
          payment_intent_id: paymentIntent.id,
        },
      })
    } catch (err) {
      console.error('Failed to create notification:', err.message)
    }
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

  // Cancel any referral earnings for this payment
  const { error: earningsError } = await supabase
    .from('referral_earnings')
    .update({ status: 'cancelled' })
    .eq('payment_id', payment.id)
    .eq('status', 'pending')

  if (earningsError) {
    console.error('Failed to cancel referral earnings on refund:', earningsError)
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

async function handleInvoicePaid(invoice: Stripe.Invoice) {
  // Extract subscription ID — handle both old and new Stripe API versions
  // Old: invoice.subscription (string)
  // New (2025+): invoice.parent.subscription_details.subscription
  const subscriptionId: string | null =
    (invoice as any).subscription as string ||
    (invoice as any).parent?.subscription_details?.subscription as string ||
    null

  // Only track subscription invoices
  if (!subscriptionId) {
    console.log('Invoice is not for a subscription, skipping payment record')
    return
  }

  const customerId = invoice.customer as string

  console.log(`Subscription invoice paid: ${invoice.id}, amount: ${invoice.amount_paid}, subscription: ${subscriptionId}`)

  // Find user by subscription ID
  const { data: sub } = await supabase
    .from('subscriptions')
    .select('user_id, tier')
    .eq('stripe_subscription_id', subscriptionId)
    .single()

  if (!sub) {
    console.error('No subscription found for:', subscriptionId)
    return
  }

  // Skip $0 invoices (e.g., trial starts)
  if (invoice.amount_paid <= 0) {
    console.log('Skipping $0 invoice')
    return
  }

  // Check if we already recorded this invoice
  const { data: existing } = await supabase
    .from('payments')
    .select('id')
    .eq('stripe_invoice_id', invoice.id)
    .maybeSingle()

  if (existing) {
    console.log('Payment already recorded for invoice:', invoice.id)
    return
  }

  // Get receipt URL from the charge
  let receiptUrl: string | null = null
  const chargeId = invoice.charge as string
  if (chargeId) {
    try {
      const charge = await stripe.charges.retrieve(chargeId)
      receiptUrl = charge.receipt_url || null
    } catch (err) {
      console.error('Failed to fetch charge for receipt URL:', err.message)
    }
  }

  // Determine description based on invoice lines
  const lineItem = invoice.lines?.data?.[0]
  const description = lineItem?.description || `${sub.tier} plan`

  // Create payment record
  const { error } = await supabase
    .from('payments')
    .insert({
      user_id: sub.user_id,
      event_id: null,
      amount_cents: invoice.amount_paid,
      platform_fee_cents: 0,
      currency: invoice.currency,
      status: 'completed',
      type: 'subscription',
      stripe_payment_intent_id: invoice.payment_intent as string || null,
      stripe_charge_id: chargeId || null,
      stripe_invoice_id: invoice.id,
      receipt_url: receiptUrl,
      metadata: {
        tier: sub.tier,
        description: description,
        period_start: lineItem?.period?.start ? new Date(lineItem.period.start * 1000).toISOString() : null,
        period_end: lineItem?.period?.end ? new Date(lineItem.period.end * 1000).toISOString() : null,
      },
    })

  if (error) {
    console.error('Failed to create subscription payment record:', error)
  } else {
    console.log(`Subscription payment recorded: $${(invoice.amount_paid / 100).toFixed(2)} for ${sub.tier} plan`)
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

// ============================================================
// IDENTITY VERIFICATION EVENT HANDLERS
// ============================================================

async function handleIdentityVerified(session: any) {
  const userId = session.metadata?.supabase_user_id
  if (!userId) {
    console.error('No supabase_user_id in identity session metadata:', session.id)
    return
  }

  console.log(`Identity verified for user ${userId}, session ${session.id}`)

  // Update profile: set verified status, reduce payout delay
  const { error: profileError } = await supabase
    .from('profiles')
    .update({
      identity_verification_status: 'verified',
      identity_verified_at: new Date().toISOString(),
      payout_delay_days: 2,
    })
    .eq('id', userId)

  if (profileError) {
    console.error('Failed to update profile verification status:', profileError)
  }

  // Auto-approve any pending_review events by this organizer
  const { data: pendingEvents, error: eventsError } = await supabase
    .from('events')
    .select('id, title')
    .eq('organizer_id', userId)
    .eq('status', 'pending_review')
    .is('deleted_at', null)

  if (eventsError) {
    console.error('Failed to fetch pending events:', eventsError)
  } else if (pendingEvents && pendingEvents.length > 0) {
    const { error: approveError } = await supabase
      .from('events')
      .update({
        status: 'active',
        status_reason: 'Auto-approved: organizer identity verified',
      })
      .eq('organizer_id', userId)
      .eq('status', 'pending_review')

    if (approveError) {
      console.error('Failed to auto-approve events:', approveError)
    } else {
      console.log(`Auto-approved ${pendingEvents.length} pending events for verified user ${userId}`)
    }
  }
}

async function handleIdentityFailed(session: any) {
  const userId = session.metadata?.supabase_user_id
  if (!userId) {
    console.error('No supabase_user_id in identity session metadata:', session.id)
    return
  }

  console.log(`Identity verification failed/needs input for user ${userId}, session ${session.id}`)

  const { error } = await supabase
    .from('profiles')
    .update({
      identity_verification_status: 'failed',
    })
    .eq('id', userId)

  if (error) {
    console.error('Failed to update profile verification status:', error)
  }
}

// ============================================================
// Wallet Pass Generation (Apple Wallet & Google Wallet)
// ============================================================

async function enqueueWalletPasses(ticketIds: string[]) {
  try {
    const generateUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/generate-wallet-pass`
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    for (const ticketId of ticketIds) {
      // Generate both Apple and Google passes (fire-and-forget)
      for (const passType of ['apple', 'google']) {
        fetch(generateUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${serviceKey}`,
          },
          body: JSON.stringify({ ticket_id: ticketId, pass_type: passType }),
        }).catch(err =>
          console.error(`Fire-and-forget ${passType} pass generation failed:`, err.message)
        )
      }
      console.log(`Wallet pass generation enqueued for ticket ${ticketId}`)
    }
  } catch (err) {
    console.error('enqueueWalletPasses error:', err.message)
  }
}

// ============================================================
// NFT Minting Queue
// ============================================================

async function enqueueNftMints(eventId: string, userId: string, ticketIds: string[]) {
  try {
    // Check if event has NFT minting enabled (all new events default to true)
    const { data: event } = await supabase
      .from('events')
      .select('nft_enabled')
      .eq('id', eventId)
      .single()

    if (event?.nft_enabled === false) return

    // Look up buyer's Cardano wallet address
    const { data: wallet } = await supabase
      .from('user_wallets')
      .select('cardano_address')
      .eq('user_id', userId)
      .single()

    for (const ticketId of ticketIds) {
      if (!wallet?.cardano_address) {
        // No wallet — skip, user can claim later
        await supabase.from('nft_mint_queue').insert({
          ticket_id: ticketId,
          event_id: eventId,
          buyer_address: '',
          status: 'skipped',
          error_message: 'Buyer has no Cardano wallet',
        })
        console.log(`NFT mint skipped for ticket ${ticketId}: no Cardano wallet`)
        continue
      }

      // Insert into mint queue
      const { data: queueEntry, error: queueError } = await supabase
        .from('nft_mint_queue')
        .insert({
          ticket_id: ticketId,
          event_id: eventId,
          buyer_address: wallet.cardano_address,
          status: 'queued',
        })
        .select()
        .single()

      if (queueError) {
        console.error(`Failed to enqueue NFT mint for ticket ${ticketId}:`, queueError)
        continue
      }

      // Fire-and-forget: invoke the mint function
      try {
        const mintUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/mint-ticket-nft`
        fetch(mintUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
          },
          body: JSON.stringify({ queue_id: queueEntry.id, ticket_id: ticketId }),
        }).catch(err => console.error(`Fire-and-forget mint failed:`, err.message))
      } catch (err) {
        console.error(`Failed to invoke mint function:`, err.message)
      }

      console.log(`NFT mint enqueued for ticket ${ticketId}`)
    }
  } catch (err) {
    console.error('enqueueNftMints error:', err.message)
  }
}

// ============================================================
// NFT Transfer Queue (for resale)
// ============================================================

async function enqueueNftTransfer(
  ticketId: string, eventId: string, buyerId: string, sellerId: string, resaleListingId: string,
) {
  try {
    // Look up buyer's Cardano wallet address
    const { data: buyerWallet } = await supabase
      .from('user_wallets')
      .select('cardano_address')
      .eq('user_id', buyerId)
      .single()

    if (!buyerWallet?.cardano_address) {
      // No wallet — skip transfer, buyer can claim later
      await supabase.from('nft_mint_queue').insert({
        ticket_id: ticketId,
        event_id: eventId,
        buyer_address: '',
        action: 'transfer',
        status: 'skipped',
        resale_listing_id: resaleListingId,
        error_message: 'Buyer has no Cardano wallet',
      })
      console.log(`NFT transfer skipped for ticket ${ticketId}: buyer has no wallet`)
      return
    }

    // Look up seller's Cardano address (for reference)
    const { data: sellerWallet } = await supabase
      .from('user_wallets')
      .select('cardano_address')
      .eq('user_id', sellerId)
      .single()

    // Insert into queue
    const { data: queueEntry, error: queueError } = await supabase
      .from('nft_mint_queue')
      .insert({
        ticket_id: ticketId,
        event_id: eventId,
        buyer_address: buyerWallet.cardano_address,
        seller_address: sellerWallet?.cardano_address || null,
        action: 'transfer',
        status: 'queued',
        resale_listing_id: resaleListingId,
      })
      .select()
      .single()

    if (queueError) {
      console.error(`Failed to enqueue NFT transfer for ticket ${ticketId}:`, queueError)
      return
    }

    // Fire-and-forget: invoke the transfer function
    try {
      const transferUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/transfer-ticket-nft`
      fetch(transferUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
        },
        body: JSON.stringify({ queue_id: queueEntry.id, ticket_id: ticketId }),
      }).catch(err => console.error(`Fire-and-forget transfer failed:`, err.message))
    } catch (err) {
      console.error(`Failed to invoke transfer function:`, err.message)
    }

    console.log(`NFT transfer enqueued for ticket ${ticketId} (resale ${resaleListingId})`)
  } catch (err) {
    console.error('enqueueNftTransfer error:', err.message)
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
