import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const supabase = createClient(supabaseUrl, supabaseServiceKey)

serve(async (req) => {
  try {
    const { organizer_id } = await req.json()

    if (!organizer_id) {
      return new Response(JSON.stringify({ error: 'organizer_id required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Fetch organizer's merch config
    const { data: config, error: configError } = await supabase
      .from('organizer_merch_config')
      .select()
      .eq('organizer_id', organizer_id)
      .single()

    if (configError || !config) {
      return new Response(JSON.stringify({ error: 'Merch config not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    if (config.provider !== 'shopify' || !config.shopify_domain || !config.shopify_storefront_token) {
      return new Response(JSON.stringify({ error: 'Shopify not configured' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Fetch products from Shopify Storefront API
    const shopifyUrl = `https://${config.shopify_domain}/api/2024-01/graphql.json`
    const query = `{
      products(first: 100) {
        edges {
          node {
            id
            title
            description
            images(first: 5) {
              edges {
                node {
                  url
                }
              }
            }
            variants(first: 50) {
              edges {
                node {
                  id
                  title
                  price {
                    amount
                    currencyCode
                  }
                  quantityAvailable
                  sku
                }
              }
            }
          }
        }
      }
    }`

    const shopifyResponse = await fetch(shopifyUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Shopify-Storefront-Access-Token': config.shopify_storefront_token,
      },
      body: JSON.stringify({ query }),
    })

    if (!shopifyResponse.ok) {
      const errorText = await shopifyResponse.text()
      console.error('Shopify API error:', errorText)
      return new Response(JSON.stringify({ error: 'Shopify API error' }), {
        status: 502,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const shopifyData = await shopifyResponse.json()
    const products = shopifyData.data?.products?.edges || []

    // Track synced external IDs
    const syncedExternalIds: string[] = []

    for (const { node: product } of products) {
      const externalId = product.id
      syncedExternalIds.push(externalId)

      const imageUrls = product.images.edges.map((e: any) => e.node.url)

      // Get base price from first variant
      const firstVariant = product.variants.edges[0]?.node
      const basePriceCents = firstVariant
        ? Math.round(parseFloat(firstVariant.price.amount) * 100)
        : 0

      // Upsert product
      const { data: upsertedProduct, error: productError } = await supabase
        .from('merch_products')
        .upsert(
          {
            organizer_id: organizer_id,
            source: 'shopify',
            external_id: externalId,
            title: product.title,
            description: product.description,
            image_urls: imageUrls,
            base_price_cents: basePriceCents,
            is_active: true,
            updated_at: new Date().toISOString(),
          },
          { onConflict: 'organizer_id,external_id' }
        )
        .select('id')
        .single()

      if (productError) {
        console.error(`Failed to upsert product ${product.title}:`, productError)
        continue
      }

      // Sync variants
      for (let i = 0; i < product.variants.edges.length; i++) {
        const { node: variant } = product.variants.edges[i]
        const priceCents = Math.round(parseFloat(variant.price.amount) * 100)

        await supabase.from('merch_variants').upsert(
          {
            product_id: upsertedProduct.id,
            external_id: variant.id,
            name: variant.title || 'Default',
            price_cents: priceCents,
            inventory_count: variant.quantityAvailable,
            sku: variant.sku,
            sort_order: i,
          },
          { onConflict: 'product_id,external_id' }
        )
      }
    }

    // Mark removed products as inactive
    if (syncedExternalIds.length > 0) {
      await supabase
        .from('merch_products')
        .update({ is_active: false, updated_at: new Date().toISOString() })
        .eq('organizer_id', organizer_id)
        .eq('source', 'shopify')
        .not('external_id', 'in', `(${syncedExternalIds.map(id => `"${id}"`).join(',')})`)
    }

    return new Response(
      JSON.stringify({ synced: syncedExternalIds.length }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Sync error:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})
