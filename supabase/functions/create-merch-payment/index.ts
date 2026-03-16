import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import Stripe from 'https://esm.sh/stripe@14.21.0'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
})

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const supabase = createClient(supabaseUrl, supabaseServiceKey)

const PLATFORM_FEE_RATE = 0.05

serve(async (req) => {
  try {
    // Get authenticated user
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: userError } = await supabase.auth.getUser(token)
    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Invalid token' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const { product_id, variant_id, quantity, fulfillment_type, shipping_address } = await req.json()

    if (!product_id || !quantity || quantity < 1) {
      return new Response(JSON.stringify({ error: 'product_id and quantity required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Fetch product
    const { data: product, error: productError } = await supabase
      .from('merch_products')
      .select('*, merch_variants(*)')
      .eq('id', product_id)
      .single()

    if (productError || !product) {
      return new Response(JSON.stringify({ error: 'Product not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    if (!product.is_active) {
      return new Response(JSON.stringify({ error: 'Product is not available' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Validate organizer is Enterprise tier
    const { data: subscription } = await supabase
      .from('subscriptions')
      .select('tier')
      .eq('user_id', product.organizer_id)
      .eq('status', 'active')
      .maybeSingle()

    if (!subscription || subscription.tier !== 'enterprise') {
      return new Response(JSON.stringify({ error: 'Organizer requires Enterprise tier' }), {
        status: 403,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Determine price
    let unitPriceCents = product.base_price_cents
    if (variant_id) {
      const variant = product.merch_variants?.find((v: any) => v.id === variant_id)
      if (!variant) {
        return new Response(JSON.stringify({ error: 'Variant not found' }), {
          status: 404,
          headers: { 'Content-Type': 'application/json' },
        })
      }
      unitPriceCents = variant.price_cents

      // Check inventory
      if (variant.inventory_count !== null && variant.inventory_count < quantity) {
        return new Response(JSON.stringify({ error: 'Insufficient inventory' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        })
      }
    }

    const baseCents = unitPriceCents * quantity
    const platformFeeCents = Math.ceil(baseCents * PLATFORM_FEE_RATE)
    // Stripe fee: (base + platform + 30) / (1 - 0.029)
    const totalCents = Math.ceil((baseCents + platformFeeCents + 30) / (1 - 0.029))

    if (product.source === 'stripe') {
      // Create Stripe PaymentIntent
      // Get or create Stripe customer
      const { data: profile } = await supabase
        .from('profiles')
        .select('stripe_customer_id, email, display_name')
        .eq('id', user.id)
        .single()

      let customerId = profile?.stripe_customer_id
      if (!customerId) {
        const customer = await stripe.customers.create({
          email: profile?.email || user.email,
          name: profile?.display_name || undefined,
          metadata: { user_id: user.id },
        })
        customerId = customer.id
        await supabase
          .from('profiles')
          .update({ stripe_customer_id: customerId })
          .eq('id', user.id)
      }

      const ephemeralKey = await stripe.ephemeralKeys.create(
        { customer: customerId },
        { apiVersion: '2023-10-16' }
      )

      const paymentIntent = await stripe.paymentIntents.create({
        amount: totalCents,
        currency: 'usd',
        customer: customerId,
        metadata: {
          user_id: user.id,
          type: 'merch_purchase',
          product_id,
          variant_id: variant_id || '',
          quantity: quantity.toString(),
          organizer_id: product.organizer_id,
          base_amount_cents: baseCents.toString(),
          platform_fee_cents: platformFeeCents.toString(),
        },
      })

      // Create merch_order
      const { data: order, error: orderError } = await supabase
        .from('merch_orders')
        .insert({
          user_id: user.id,
          organizer_id: product.organizer_id,
          product_id,
          variant_id: variant_id || null,
          quantity,
          amount_cents: totalCents,
          status: 'pending',
          fulfillment_type: fulfillment_type || 'ship',
          shipping_address: shipping_address || null,
          stripe_payment_intent_id: paymentIntent.id,
        })
        .select('id')
        .single()

      if (orderError) {
        console.error('Failed to create merch order:', orderError)
      }

      // Create payment record
      await supabase.from('payments').insert({
        user_id: user.id,
        amount_cents: totalCents,
        currency: 'usd',
        status: 'pending',
        type: 'merch_purchase',
        stripe_payment_intent_id: paymentIntent.id,
        platform_fee_cents: platformFeeCents,
        metadata: {
          product_title: product.title,
          order_id: order?.id,
        },
      })

      return new Response(
        JSON.stringify({
          client_secret: paymentIntent.client_secret,
          payment_intent_id: paymentIntent.id,
          customer_id: customerId,
          ephemeral_key: ephemeralKey.secret,
          order_id: order?.id,
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      )
    } else if (product.source === 'shopify') {
      // For Shopify, we create an order record and return the checkout URL
      // The organizer would need to set up Shopify checkout redirect
      const { data: order } = await supabase
        .from('merch_orders')
        .insert({
          user_id: user.id,
          organizer_id: product.organizer_id,
          product_id,
          variant_id: variant_id || null,
          quantity,
          amount_cents: baseCents,
          status: 'pending',
          fulfillment_type: fulfillment_type || 'ship',
          shipping_address: shipping_address || null,
          shopify_checkout_url: `https://${product.external_id ? '' : ''}shop`, // placeholder
        })
        .select('id')
        .single()

      return new Response(
        JSON.stringify({
          checkout_url: null, // Shopify checkout URL would be generated here
          order_id: order?.id,
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      )
    }

    return new Response(JSON.stringify({ error: 'Unsupported source' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('Create merch payment error:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})
