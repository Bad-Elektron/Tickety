-- Fix: Allow anyone to view tickets that have an active resale listing.
-- Without this, the resale browse screen's inner join on tickets fails
-- because the tickets RLS blocks non-owners from seeing the ticket data.

DROP POLICY IF EXISTS "Anyone can view tickets listed for resale" ON tickets;

CREATE POLICY "Anyone can view tickets listed for resale"
ON tickets FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM resale_listings
    WHERE resale_listings.ticket_id = tickets.id
    AND resale_listings.status = 'active'
  )
);

-- Also add an RLS policy on tickets allowing the owner to update listing_status.
-- The sold_by user needs to update their ticket's listing fields when creating/cancelling listings.
DROP POLICY IF EXISTS "Owners can update ticket listing status" ON tickets;

CREATE POLICY "Owners can update ticket listing status"
ON tickets FOR UPDATE
USING (sold_by = auth.uid())
WITH CHECK (sold_by = auth.uid());
