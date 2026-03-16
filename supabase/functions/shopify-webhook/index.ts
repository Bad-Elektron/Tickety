import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const supabase = createClient(supabaseUrl, supabaseServiceKey)

serve(async (req) => {
  try {
    const topic = req.headers.get('x-shopify-topic')
    const body = await req.json()

    console.log(`Shopify webhook: ${topic}`)

    switch (topic) {
      case 'orders/fulfilled': {
        // Find the merch order by shopify order data
        const shopifyOrderId = body.id?.toString()
        if (!shopifyOrderId) break

        // Try to match by product external_id + user
        const fulfillment = body.fulfillments?.[0]
        const trackingInfo = fulfillment ? {
          tracking_number: fulfillment.tracking_number,
          tracking_url: fulfillment.tracking_url,
          carrier: fulfillment.tracking_company,
        } : null

        // Update matching orders to shipped/delivered
        const { error } = await supabase
          .from('merch_orders')
          .update({
            status: fulfillment ? 'shipped' : 'delivered',
            ...(trackingInfo && { tracking_info: trackingInfo }),
            updated_at: new Date().toISOString(),
          })
          .eq('shopify_checkout_url', shopifyOrderId)

        if (error) {
          console.error('Failed to update order for fulfillment:', error)
        }
        break
      }

      case 'orders/cancelled': {
        const shopifyOrderId = body.id?.toString()
        if (!shopifyOrderId) break

        await supabase
          .from('merch_orders')
          .update({
            status: 'cancelled',
            updated_at: new Date().toISOString(),
          })
          .eq('shopify_checkout_url', shopifyOrderId)
        break
      }

      default:
        console.log(`Unhandled Shopify topic: ${topic}`)
    }

    return new Response(JSON.stringify({ received: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('Shopify webhook error:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})
