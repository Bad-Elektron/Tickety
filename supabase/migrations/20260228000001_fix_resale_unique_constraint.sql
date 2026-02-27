-- Fix: Replace the full UNIQUE constraint on ticket_id with a partial unique index.
-- The old constraint prevented re-listing a ticket after cancelling because the
-- cancelled row still occupied the unique slot. The new partial index only enforces
-- uniqueness for active listings.

-- Drop the old full unique constraint
ALTER TABLE resale_listings DROP CONSTRAINT IF EXISTS unique_active_listing;

-- Create a partial unique index that only applies to active listings
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_active_listing
ON resale_listings (ticket_id)
WHERE status = 'active';
