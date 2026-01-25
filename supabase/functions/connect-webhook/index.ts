import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import Stripe from 'https://esm.sh/stripe@13.10.0?target=deno'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
})

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const webhookSecret = Deno.env.get('STRIPE_CONNECT_WEBHOOK_SECRET')!

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

  console.log(`Processing Connect webhook event: ${event.type}`)

  try {
    switch (event.type) {
      case 'account.updated':
        await handleAccountUpdated(event.data.object as Stripe.Account)
        break

      case 'account.application.deauthorized':
        await handleAccountDeauthorized(event.data.object as Stripe.Account)
        break

      default:
        console.log(`Unhandled Connect event type: ${event.type}`)
    }

    return new Response(JSON.stringify({ received: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })

  } catch (error) {
    console.error('Error processing Connect webhook:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    })
  }
})

async function handleAccountUpdated(account: Stripe.Account) {
  const userId = account.metadata?.supabase_user_id
  if (!userId) {
    console.log('No user ID in account metadata, skipping')
    return
  }

  console.log(`Account updated: ${account.id} for user ${userId}`)

  // Check if the account has completed onboarding
  const isOnboarded =
    account.charges_enabled &&
    account.payouts_enabled &&
    account.details_submitted

  console.log(`Account ${account.id} onboarding status: ${isOnboarded}`)

  // Update the user's profile
  const { error } = await supabase
    .from('profiles')
    .update({
      stripe_connect_onboarded: isOnboarded,
    })
    .eq('id', userId)

  if (error) {
    console.error('Failed to update profile:', error)
    return
  }

  console.log(`Updated profile for user ${userId}: onboarded=${isOnboarded}`)
}

async function handleAccountDeauthorized(account: Stripe.Account) {
  const userId = account.metadata?.supabase_user_id
  if (!userId) {
    console.log('No user ID in account metadata, skipping')
    return
  }

  console.log(`Account deauthorized: ${account.id} for user ${userId}`)

  // Clear the Connect account info from the user's profile
  const { error } = await supabase
    .from('profiles')
    .update({
      stripe_connect_account_id: null,
      stripe_connect_onboarded: false,
    })
    .eq('id', userId)

  if (error) {
    console.error('Failed to clear profile Connect info:', error)
    return
  }

  // Cancel any active resale listings from this user
  const { error: listingError } = await supabase
    .from('resale_listings')
    .update({ status: 'cancelled' })
    .eq('seller_id', userId)
    .eq('status', 'active')

  if (listingError) {
    console.error('Failed to cancel user listings:', listingError)
  }

  console.log(`Cleared Connect info for user ${userId}`)
}
