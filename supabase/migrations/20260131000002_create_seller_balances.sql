-- Create seller_balances table for tracking Stripe-managed seller funds
-- This tracks funds held in sellers' Stripe Express accounts (not in Tickety's account)
-- Funds are transferred to seller's Stripe balance on each sale, withdrawn when seller adds bank details

CREATE TABLE IF NOT EXISTS seller_balances (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
    stripe_account_id VARCHAR(255) NOT NULL,
    -- Balance fields are cached from Stripe API for display purposes
    -- Actual source of truth is always the Stripe API
    available_balance_cents INTEGER NOT NULL DEFAULT 0,
    pending_balance_cents INTEGER NOT NULL DEFAULT 0,
    currency VARCHAR(3) NOT NULL DEFAULT 'usd',
    -- Whether the seller can withdraw (has added bank details)
    payouts_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    -- Whether full Stripe verification is complete (for higher limits)
    details_submitted BOOLEAN NOT NULL DEFAULT FALSE,
    -- Last time balance was synced from Stripe
    last_synced_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_seller_balances_user_id ON seller_balances(user_id);
CREATE INDEX IF NOT EXISTS idx_seller_balances_stripe_account_id ON seller_balances(stripe_account_id);

-- Enable RLS
ALTER TABLE seller_balances ENABLE ROW LEVEL SECURITY;

-- RLS Policies

-- Users can view their own balance
CREATE POLICY "Users can view own balance"
    ON seller_balances
    FOR SELECT
    USING (auth.uid() = user_id);

-- Service role can manage all balances (for edge functions/webhooks)
CREATE POLICY "Service role can manage balances"
    ON seller_balances
    FOR ALL
    USING (auth.role() = 'service_role');

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_seller_balances_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to automatically update updated_at
CREATE TRIGGER seller_balances_updated_at
    BEFORE UPDATE ON seller_balances
    FOR EACH ROW
    EXECUTE FUNCTION update_seller_balances_updated_at();

-- Comments
COMMENT ON TABLE seller_balances IS 'Caches Stripe Connect balance info for sellers. Source of truth is Stripe API.';
COMMENT ON COLUMN seller_balances.available_balance_cents IS 'Cached available balance from Stripe (funds ready for payout)';
COMMENT ON COLUMN seller_balances.pending_balance_cents IS 'Cached pending balance from Stripe (funds not yet available)';
COMMENT ON COLUMN seller_balances.payouts_enabled IS 'Whether seller has added bank details and can withdraw';
COMMENT ON COLUMN seller_balances.details_submitted IS 'Whether seller has completed full Stripe verification';
COMMENT ON COLUMN seller_balances.last_synced_at IS 'Last time balance was fetched from Stripe API';
