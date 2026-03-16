-- Merch Store System: Physical merchandise via Shopify/Stripe integration
-- Enterprise-only feature for organizers to sell merchandise

-- Organizer merch configuration
CREATE TABLE IF NOT EXISTS organizer_merch_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  provider TEXT NOT NULL DEFAULT 'none' CHECK (provider IN ('shopify', 'stripe', 'none')),
  shopify_domain TEXT,
  shopify_storefront_token TEXT,
  is_active BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (organizer_id)
);

-- Enable RLS
ALTER TABLE organizer_merch_config ENABLE ROW LEVEL SECURITY;

-- Owner can read/update their own config
CREATE POLICY "organizer_merch_config_select" ON organizer_merch_config
  FOR SELECT USING (organizer_id = auth.uid());

CREATE POLICY "organizer_merch_config_insert" ON organizer_merch_config
  FOR INSERT WITH CHECK (organizer_id = auth.uid());

CREATE POLICY "organizer_merch_config_update" ON organizer_merch_config
  FOR UPDATE USING (organizer_id = auth.uid());

-- Merch products
CREATE TABLE IF NOT EXISTS merch_products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  source TEXT NOT NULL CHECK (source IN ('shopify', 'stripe')),
  external_id TEXT,
  title TEXT NOT NULL,
  description TEXT,
  image_urls JSONB DEFAULT '[]'::jsonb,
  base_price_cents INT NOT NULL DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  event_id UUID REFERENCES events(id) ON DELETE SET NULL,
  fulfillment_type TEXT NOT NULL DEFAULT 'ship' CHECK (fulfillment_type IN ('ship', 'pickup')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE merch_products ENABLE ROW LEVEL SECURITY;

-- Public can see active products
CREATE POLICY "merch_products_public_select" ON merch_products
  FOR SELECT USING (is_active = true);

-- Owner can manage their products
CREATE POLICY "merch_products_owner_insert" ON merch_products
  FOR INSERT WITH CHECK (organizer_id = auth.uid());

CREATE POLICY "merch_products_owner_update" ON merch_products
  FOR UPDATE USING (organizer_id = auth.uid());

CREATE POLICY "merch_products_owner_delete" ON merch_products
  FOR DELETE USING (organizer_id = auth.uid());

-- Owner can see inactive products too
CREATE POLICY "merch_products_owner_select_all" ON merch_products
  FOR SELECT USING (organizer_id = auth.uid());

-- Merch variants
CREATE TABLE IF NOT EXISTS merch_variants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES merch_products(id) ON DELETE CASCADE,
  external_id TEXT,
  name TEXT NOT NULL,
  price_cents INT NOT NULL DEFAULT 0,
  inventory_count INT,
  sku TEXT,
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE merch_variants ENABLE ROW LEVEL SECURITY;

-- Variants visible if product is visible (via subquery)
CREATE POLICY "merch_variants_select" ON merch_variants
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM merch_products mp
      WHERE mp.id = merch_variants.product_id
      AND (mp.is_active = true OR mp.organizer_id = auth.uid())
    )
  );

CREATE POLICY "merch_variants_owner_insert" ON merch_variants
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM merch_products mp
      WHERE mp.id = merch_variants.product_id
      AND mp.organizer_id = auth.uid()
    )
  );

CREATE POLICY "merch_variants_owner_update" ON merch_variants
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM merch_products mp
      WHERE mp.id = merch_variants.product_id
      AND mp.organizer_id = auth.uid()
    )
  );

CREATE POLICY "merch_variants_owner_delete" ON merch_variants
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM merch_products mp
      WHERE mp.id = merch_variants.product_id
      AND mp.organizer_id = auth.uid()
    )
  );

-- Merch orders
CREATE TABLE IF NOT EXISTS merch_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  organizer_id UUID NOT NULL REFERENCES profiles(id),
  product_id UUID NOT NULL REFERENCES merch_products(id),
  variant_id UUID REFERENCES merch_variants(id),
  quantity INT NOT NULL DEFAULT 1,
  amount_cents INT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded')),
  shipping_address JSONB,
  tracking_info JSONB,
  fulfillment_type TEXT NOT NULL DEFAULT 'ship' CHECK (fulfillment_type IN ('ship', 'pickup')),
  stripe_payment_intent_id TEXT,
  shopify_checkout_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE merch_orders ENABLE ROW LEVEL SECURITY;

-- Buyer can see their own orders
CREATE POLICY "merch_orders_buyer_select" ON merch_orders
  FOR SELECT USING (user_id = auth.uid());

-- Organizer can see orders for their products
CREATE POLICY "merch_orders_organizer_select" ON merch_orders
  FOR SELECT USING (organizer_id = auth.uid());

-- Insert: authenticated users
CREATE POLICY "merch_orders_insert" ON merch_orders
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- Organizer can update order status
CREATE POLICY "merch_orders_organizer_update" ON merch_orders
  FOR UPDATE USING (organizer_id = auth.uid());

-- Add merch_purchase to payments type constraint
-- First check if the constraint exists and update it
DO $$
BEGIN
  -- Drop old constraint if it exists
  ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_type_check;
  -- Add updated constraint with merch_purchase
  ALTER TABLE payments ADD CONSTRAINT payments_type_check
    CHECK (type IN ('primary_purchase', 'resale_purchase', 'vendor_pos', 'subscription', 'favor_ticket_purchase', 'wallet_purchase', 'wallet_top_up', 'ach_purchase', 'waitlist_auto_purchase', 'merch_purchase'));
EXCEPTION
  WHEN undefined_table THEN NULL;
END $$;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_merch_products_organizer ON merch_products (organizer_id);
CREATE INDEX IF NOT EXISTS idx_merch_products_event ON merch_products (event_id) WHERE event_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_merch_variants_product ON merch_variants (product_id);
CREATE INDEX IF NOT EXISTS idx_merch_orders_user ON merch_orders (user_id);
CREATE INDEX IF NOT EXISTS idx_merch_orders_organizer ON merch_orders (organizer_id);
CREATE INDEX IF NOT EXISTS idx_merch_orders_status ON merch_orders (status);
