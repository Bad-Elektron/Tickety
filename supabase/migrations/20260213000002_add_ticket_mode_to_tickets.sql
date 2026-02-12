-- Add ticket_mode column to tickets table
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS ticket_mode TEXT NOT NULL DEFAULT 'standard'
    CHECK (ticket_mode IN ('standard', 'private', 'public'));

-- Add offer_id column (FK to ticket_offers)
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS offer_id UUID REFERENCES ticket_offers(id) ON DELETE SET NULL;

-- Index for quick lookup
CREATE INDEX IF NOT EXISTS idx_tickets_offer_id ON tickets(offer_id);
CREATE INDEX IF NOT EXISTS idx_tickets_ticket_mode ON tickets(ticket_mode);

-- Trigger to block private tickets from being listed for resale
CREATE OR REPLACE FUNCTION block_private_ticket_resale()
RETURNS TRIGGER AS $$
DECLARE
    t_mode TEXT;
BEGIN
    SELECT ticket_mode INTO t_mode FROM tickets WHERE id = NEW.ticket_id;

    IF t_mode = 'private' THEN
        RAISE EXCEPTION 'Private tickets cannot be listed for resale';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_ticket_mode_before_resale
    BEFORE INSERT ON resale_listings
    FOR EACH ROW
    EXECUTE FUNCTION block_private_ticket_resale();

COMMENT ON COLUMN tickets.ticket_mode IS 'Ticket mode: standard (normal), private (off-chain, no resale), public (on-chain NFT)';
COMMENT ON FUNCTION block_private_ticket_resale() IS 'Prevents private tickets from being listed for resale';
