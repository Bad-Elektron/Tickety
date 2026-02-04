-- Create cash_transactions table for tracking cash sales at events
-- Enables staff to sell tickets for cash with 5% platform fee charged to organizer

-- ============================================================================
-- CASH TRANSACTIONS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS cash_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Core relationships
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    seller_id UUID NOT NULL REFERENCES auth.users(id),
    ticket_id UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,

    -- Sale amount (what customer paid in cash)
    amount_cents INTEGER NOT NULL CHECK (amount_cents >= 0),
    platform_fee_cents INTEGER NOT NULL DEFAULT 0,
    currency VARCHAR(3) NOT NULL DEFAULT 'USD',

    -- Transaction status
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'collected', 'disputed')),

    -- Platform fee collection (charged to organizer's card)
    fee_charged BOOLEAN NOT NULL DEFAULT FALSE,
    fee_payment_intent_id VARCHAR(255),
    fee_charge_error TEXT,

    -- Customer details (optional)
    customer_name VARCHAR(255),
    customer_email VARCHAR(255),

    -- Ticket delivery method
    delivery_method VARCHAR(20) CHECK (delivery_method IN ('nfc', 'email', 'in_person')),

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Reconciliation tracking
    reconciled_at TIMESTAMPTZ,
    reconciled_by UUID REFERENCES auth.users(id)
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX idx_cash_tx_event ON cash_transactions(event_id);
CREATE INDEX idx_cash_tx_seller ON cash_transactions(seller_id, created_at DESC);
CREATE INDEX idx_cash_tx_status ON cash_transactions(event_id, status);

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE cash_transactions ENABLE ROW LEVEL SECURITY;

-- Staff (sellers) can view their own cash transactions
CREATE POLICY "Staff can view own cash transactions"
    ON cash_transactions
    FOR SELECT
    USING (seller_id = auth.uid());

-- Organizers can view all cash transactions for their events
CREATE POLICY "Organizers can view event cash transactions"
    ON cash_transactions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM events
            WHERE events.id = cash_transactions.event_id
            AND events.organizer_id = auth.uid()
        )
    );

-- Organizers can update cash transaction status (for reconciliation)
CREATE POLICY "Organizers can update cash transaction status"
    ON cash_transactions
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM events
            WHERE events.id = cash_transactions.event_id
            AND events.organizer_id = auth.uid()
        )
    );

-- Service role can manage all cash transactions (for edge functions)
CREATE POLICY "Service role can manage cash transactions"
    ON cash_transactions
    FOR ALL
    USING (auth.role() = 'service_role');

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

CREATE OR REPLACE FUNCTION update_cash_transactions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_cash_transactions_updated_at
    BEFORE UPDATE ON cash_transactions
    FOR EACH ROW
    EXECUTE FUNCTION update_cash_transactions_updated_at();

-- ============================================================================
-- ADD COLUMNS TO EVENTS TABLE
-- ============================================================================

-- Enable cash sales for the event (requires organizer payment method)
ALTER TABLE events ADD COLUMN IF NOT EXISTS cash_sales_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Stripe customer ID for charging platform fees
ALTER TABLE events ADD COLUMN IF NOT EXISTS organizer_stripe_customer_id VARCHAR(255);

-- Default payment method ID for charging fees
ALTER TABLE events ADD COLUMN IF NOT EXISTS organizer_payment_method_id VARCHAR(255);

-- ============================================================================
-- ADD COLUMNS TO TICKETS TABLE
-- ============================================================================

-- Payment method used to purchase the ticket
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS payment_method VARCHAR(20) DEFAULT 'card';

-- How the ticket was delivered to the customer
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS delivery_method VARCHAR(20);

-- Transfer token for NFC ticket delivery (expires after 5 minutes)
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS transfer_token VARCHAR(64);
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS transfer_token_expires_at TIMESTAMPTZ;

-- ============================================================================
-- HELPER FUNCTION: Get cash summary for an event
-- ============================================================================

CREATE OR REPLACE FUNCTION get_event_cash_summary(p_event_id UUID)
RETURNS TABLE (
    total_cash_cents BIGINT,
    total_fees_cents BIGINT,
    fees_collected_cents BIGINT,
    transaction_count BIGINT,
    collected_count BIGINT,
    disputed_count BIGINT,
    pending_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(SUM(ct.amount_cents), 0)::BIGINT AS total_cash_cents,
        COALESCE(SUM(ct.platform_fee_cents), 0)::BIGINT AS total_fees_cents,
        COALESCE(SUM(CASE WHEN ct.fee_charged THEN ct.platform_fee_cents ELSE 0 END), 0)::BIGINT AS fees_collected_cents,
        COUNT(*)::BIGINT AS transaction_count,
        COUNT(*) FILTER (WHERE ct.status = 'collected')::BIGINT AS collected_count,
        COUNT(*) FILTER (WHERE ct.status = 'disputed')::BIGINT AS disputed_count,
        COUNT(*) FILTER (WHERE ct.status = 'pending')::BIGINT AS pending_count
    FROM cash_transactions ct
    WHERE ct.event_id = p_event_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- HELPER FUNCTION: Get cash summary per seller for an event
-- ============================================================================

CREATE OR REPLACE FUNCTION get_event_cash_by_seller(p_event_id UUID)
RETURNS TABLE (
    seller_id UUID,
    seller_email TEXT,
    total_cash_cents BIGINT,
    total_fees_cents BIGINT,
    transaction_count BIGINT,
    collected_count BIGINT,
    pending_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        ct.seller_id,
        u.email AS seller_email,
        COALESCE(SUM(ct.amount_cents), 0)::BIGINT AS total_cash_cents,
        COALESCE(SUM(ct.platform_fee_cents), 0)::BIGINT AS total_fees_cents,
        COUNT(*)::BIGINT AS transaction_count,
        COUNT(*) FILTER (WHERE ct.status = 'collected')::BIGINT AS collected_count,
        COUNT(*) FILTER (WHERE ct.status = 'pending')::BIGINT AS pending_count
    FROM cash_transactions ct
    JOIN auth.users u ON u.id = ct.seller_id
    WHERE ct.event_id = p_event_id
    GROUP BY ct.seller_id, u.email
    ORDER BY total_cash_cents DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE cash_transactions IS 'Tracks cash sales made by staff at events. Platform fee (5%) is charged to organizer card.';
COMMENT ON COLUMN cash_transactions.amount_cents IS 'Cash amount collected from customer';
COMMENT ON COLUMN cash_transactions.platform_fee_cents IS 'Platform fee (5% of amount_cents) charged to organizer';
COMMENT ON COLUMN cash_transactions.fee_charged IS 'Whether the platform fee has been charged to organizer card';
COMMENT ON COLUMN cash_transactions.fee_payment_intent_id IS 'Stripe PaymentIntent ID for the fee charge';
COMMENT ON COLUMN cash_transactions.status IS 'pending = cash not yet collected, collected = organizer confirmed receipt, disputed = issue with collection';
COMMENT ON COLUMN cash_transactions.delivery_method IS 'How ticket was given to customer: nfc, email, or in_person';

COMMENT ON COLUMN events.cash_sales_enabled IS 'Whether cash sales are enabled for this event (requires payment method)';
COMMENT ON COLUMN events.organizer_stripe_customer_id IS 'Stripe Customer ID for charging platform fees';
COMMENT ON COLUMN events.organizer_payment_method_id IS 'Default payment method for fee charges';

COMMENT ON COLUMN tickets.payment_method IS 'How customer paid: card, cash, crypto';
COMMENT ON COLUMN tickets.delivery_method IS 'How ticket was delivered: nfc, email, in_person, app';
COMMENT ON COLUMN tickets.transfer_token IS 'One-time token for NFC ticket transfer';
COMMENT ON COLUMN tickets.transfer_token_expires_at IS 'Expiry time for transfer token (5 minutes)';
