-- Add listing_status and listing_price_cents columns to tickets table.
-- These columns track whether a ticket is currently listed for resale,
-- so the UI can reflect the correct state without joining resale_listings.

ALTER TABLE tickets
ADD COLUMN IF NOT EXISTS listing_status VARCHAR(20) NOT NULL DEFAULT 'none'
  CHECK (listing_status IN ('none', 'listed', 'sold', 'cancelled')),
ADD COLUMN IF NOT EXISTS listing_price_cents INTEGER;

-- Backfill: Mark tickets that have active resale listings
UPDATE tickets
SET listing_status = 'listed',
    listing_price_cents = rl.price_cents
FROM resale_listings rl
WHERE rl.ticket_id = tickets.id
AND rl.status = 'active';

-- Index for quick lookups of listed tickets
CREATE INDEX IF NOT EXISTS idx_tickets_listing_status ON tickets(listing_status)
WHERE listing_status != 'none';
