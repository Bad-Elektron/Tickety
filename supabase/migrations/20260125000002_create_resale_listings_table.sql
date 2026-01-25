-- Create resale_listings table for secondary market
CREATE TABLE IF NOT EXISTS resale_listings (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ticket_id UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    seller_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    price_cents INTEGER NOT NULL CHECK (price_cents > 0),
    currency VARCHAR(3) NOT NULL DEFAULT 'usd',
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'sold', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Only one active listing per ticket
    CONSTRAINT unique_active_listing UNIQUE (ticket_id) DEFERRABLE INITIALLY DEFERRED
);

-- Add Stripe Connect columns to profiles
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS stripe_connect_account_id VARCHAR(255),
ADD COLUMN IF NOT EXISTS stripe_connect_onboarded BOOLEAN DEFAULT FALSE;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_resale_listings_ticket_id ON resale_listings(ticket_id);
CREATE INDEX IF NOT EXISTS idx_resale_listings_seller_id ON resale_listings(seller_id);
CREATE INDEX IF NOT EXISTS idx_resale_listings_status ON resale_listings(status);
CREATE INDEX IF NOT EXISTS idx_resale_listings_created_at ON resale_listings(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_profiles_stripe_connect_account_id ON profiles(stripe_connect_account_id);

-- Enable RLS
ALTER TABLE resale_listings ENABLE ROW LEVEL SECURITY;

-- RLS Policies

-- Anyone can view active listings
CREATE POLICY "Anyone can view active listings"
    ON resale_listings
    FOR SELECT
    USING (status = 'active');

-- Sellers can view their own listings (any status)
CREATE POLICY "Sellers can view own listings"
    ON resale_listings
    FOR SELECT
    USING (auth.uid() = seller_id);

-- Sellers can create listings for tickets they own
CREATE POLICY "Sellers can create listings"
    ON resale_listings
    FOR INSERT
    WITH CHECK (
        auth.uid() = seller_id
        AND EXISTS (
            SELECT 1 FROM tickets
            WHERE tickets.id = ticket_id
            AND tickets.owner_email = (
                SELECT email FROM auth.users WHERE id = auth.uid()
            )
            AND tickets.status = 'valid'
        )
    );

-- Sellers can update their own listings
CREATE POLICY "Sellers can update own listings"
    ON resale_listings
    FOR UPDATE
    USING (auth.uid() = seller_id)
    WITH CHECK (auth.uid() = seller_id);

-- Sellers can delete their own listings
CREATE POLICY "Sellers can delete own listings"
    ON resale_listings
    FOR DELETE
    USING (auth.uid() = seller_id);

-- Service role can manage all listings (for webhook operations)
CREATE POLICY "Service role can manage listings"
    ON resale_listings
    FOR ALL
    USING (auth.role() = 'service_role');

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_resale_listings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to automatically update updated_at
CREATE TRIGGER resale_listings_updated_at
    BEFORE UPDATE ON resale_listings
    FOR EACH ROW
    EXECUTE FUNCTION update_resale_listings_updated_at();

-- Function to check unique active listing constraint
-- (PostgreSQL partial unique indexes don't work well with updates)
CREATE OR REPLACE FUNCTION check_active_listing()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'active' THEN
        IF EXISTS (
            SELECT 1 FROM resale_listings
            WHERE ticket_id = NEW.ticket_id
            AND status = 'active'
            AND id != NEW.id
        ) THEN
            RAISE EXCEPTION 'Only one active listing per ticket is allowed';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to enforce unique active listing
CREATE TRIGGER check_active_listing_trigger
    BEFORE INSERT OR UPDATE ON resale_listings
    FOR EACH ROW
    EXECUTE FUNCTION check_active_listing();

-- Comments
COMMENT ON TABLE resale_listings IS 'Stores resale listings for the secondary ticket market';
COMMENT ON COLUMN resale_listings.price_cents IS 'Listing price in cents set by the seller';
COMMENT ON COLUMN profiles.stripe_connect_account_id IS 'Stripe Connect Express account ID for receiving resale payouts';
COMMENT ON COLUMN profiles.stripe_connect_onboarded IS 'Whether the user has completed Stripe Connect onboarding';
