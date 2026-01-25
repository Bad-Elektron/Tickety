-- Create payments table for tracking all payment transactions
CREATE TABLE IF NOT EXISTS payments (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    ticket_id UUID REFERENCES tickets(id) ON DELETE SET NULL,
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
    platform_fee_cents INTEGER NOT NULL DEFAULT 0 CHECK (platform_fee_cents >= 0),
    currency VARCHAR(3) NOT NULL DEFAULT 'usd',
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'refunded')),
    type VARCHAR(30) NOT NULL DEFAULT 'primary_purchase' CHECK (type IN ('primary_purchase', 'resale_purchase', 'vendor_pos')),
    stripe_payment_intent_id VARCHAR(255),
    stripe_charge_id VARCHAR(255),
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add Stripe customer ID to profiles table
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS stripe_customer_id VARCHAR(255);

-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS idx_payments_user_id ON payments(user_id);
CREATE INDEX IF NOT EXISTS idx_payments_event_id ON payments(event_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(status);
CREATE INDEX IF NOT EXISTS idx_payments_stripe_payment_intent_id ON payments(stripe_payment_intent_id);
CREATE INDEX IF NOT EXISTS idx_payments_created_at ON payments(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_profiles_stripe_customer_id ON profiles(stripe_customer_id);

-- Enable Row Level Security
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can view their own payments
CREATE POLICY "Users can view own payments"
    ON payments
    FOR SELECT
    USING (auth.uid() = user_id);

-- RLS Policy: Event organizers can view payments for their events
CREATE POLICY "Organizers can view event payments"
    ON payments
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM events
            WHERE events.id = payments.event_id
            AND events.organizer_id = auth.uid()
        )
    );

-- RLS Policy: Event staff can view payments for their events
CREATE POLICY "Staff can view event payments"
    ON payments
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM event_staff
            WHERE event_staff.event_id = payments.event_id
            AND event_staff.user_id = auth.uid()
            AND event_staff.role IN ('admin', 'vendor')
        )
    );

-- RLS Policy: Service role can insert/update payments (for webhooks)
CREATE POLICY "Service role can manage payments"
    ON payments
    FOR ALL
    USING (auth.role() = 'service_role');

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_payments_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to automatically update updated_at
CREATE TRIGGER payments_updated_at
    BEFORE UPDATE ON payments
    FOR EACH ROW
    EXECUTE FUNCTION update_payments_updated_at();

-- Comment on table
COMMENT ON TABLE payments IS 'Stores all payment transactions for ticket purchases';
COMMENT ON COLUMN payments.type IS 'Type of payment: primary_purchase (direct buy), resale_purchase (P2P), vendor_pos (at-event sale)';
COMMENT ON COLUMN payments.platform_fee_cents IS 'Platform fee in cents (e.g., 5% of resale transactions)';
