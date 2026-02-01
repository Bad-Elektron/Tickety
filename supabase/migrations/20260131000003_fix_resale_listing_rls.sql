-- Fix RLS policy for creating resale listings
-- The old policy checked owner_email, but ticket ownership is tracked via sold_by (user ID)

-- Drop the old policy
DROP POLICY IF EXISTS "Sellers can create listings" ON resale_listings;

-- Create new policy that checks sold_by instead of owner_email
CREATE POLICY "Sellers can create listings"
    ON resale_listings
    FOR INSERT
    WITH CHECK (
        auth.uid() = seller_id
        AND EXISTS (
            SELECT 1 FROM tickets
            WHERE tickets.id = ticket_id
            AND tickets.sold_by = auth.uid()
            AND tickets.status = 'valid'
        )
    );

-- Also add a policy for users to see tickets they own (via sold_by) for the resale flow
-- This ensures the ticket query in the resale flow works
DROP POLICY IF EXISTS "Users can view tickets they own" ON tickets;
CREATE POLICY "Users can view tickets they own"
ON tickets FOR SELECT
USING (sold_by = auth.uid());
