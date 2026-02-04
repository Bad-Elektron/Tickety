-- Create pending_payments table for NFC tap-to-pay flow
-- This enables real-time communication between vendor and customer devices

CREATE TABLE IF NOT EXISTS pending_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Parties involved
    vendor_id UUID NOT NULL REFERENCES auth.users(id),
    customer_id UUID NOT NULL REFERENCES auth.users(id),

    -- What's being purchased
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    ticket_type_id UUID REFERENCES event_ticket_types(id),
    ticket_type_name VARCHAR(100),
    amount_cents INTEGER NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'USD',

    -- Payment tracking
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    stripe_payment_intent_id VARCHAR(255),

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '5 minutes'),
    completed_at TIMESTAMPTZ,

    -- Constraints
    CONSTRAINT valid_status CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'expired', 'cancelled')),
    CONSTRAINT positive_amount CHECK (amount_cents >= 0)
);

-- Indexes for common queries
CREATE INDEX idx_pending_payments_customer ON pending_payments(customer_id, status) WHERE status = 'pending';
CREATE INDEX idx_pending_payments_vendor ON pending_payments(vendor_id, status);
CREATE INDEX idx_pending_payments_expires ON pending_payments(expires_at) WHERE status = 'pending';

-- Enable RLS
ALTER TABLE pending_payments ENABLE ROW LEVEL SECURITY;

-- Vendors can create pending payments
CREATE POLICY "Vendors can create pending payments"
    ON pending_payments
    FOR INSERT
    WITH CHECK (vendor_id = auth.uid());

-- Vendors can view their own pending payments
CREATE POLICY "Vendors can view their pending payments"
    ON pending_payments
    FOR SELECT
    USING (vendor_id = auth.uid());

-- Customers can view pending payments for them
CREATE POLICY "Customers can view their pending payments"
    ON pending_payments
    FOR SELECT
    USING (customer_id = auth.uid());

-- Customers can update pending payments for them (to mark as processing/completed)
CREATE POLICY "Customers can update their pending payments"
    ON pending_payments
    FOR UPDATE
    USING (customer_id = auth.uid())
    WITH CHECK (customer_id = auth.uid());

-- Vendors can cancel their own pending payments
CREATE POLICY "Vendors can cancel their pending payments"
    ON pending_payments
    FOR UPDATE
    USING (vendor_id = auth.uid() AND status = 'pending')
    WITH CHECK (vendor_id = auth.uid() AND status = 'cancelled');

-- Enable Realtime for this table
ALTER PUBLICATION supabase_realtime ADD TABLE pending_payments;

-- Function to auto-expire old pending payments
CREATE OR REPLACE FUNCTION expire_old_pending_payments()
RETURNS void AS $$
BEGIN
    UPDATE pending_payments
    SET status = 'expired', updated_at = NOW()
    WHERE status = 'pending' AND expires_at < NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_pending_payments_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_pending_payments_timestamp ON pending_payments;
CREATE TRIGGER trigger_update_pending_payments_timestamp
    BEFORE UPDATE ON pending_payments
    FOR EACH ROW
    EXECUTE FUNCTION update_pending_payments_updated_at();
