-- Fix: Infinite recursion between resale_listings INSERT policy and tickets SELECT policy.
--
-- The cycle:
--   resale_listings INSERT policy → subquery on tickets table
--   tickets SELECT policy "Anyone can view tickets listed for resale" → subquery on resale_listings
--
-- Solution: Use a SECURITY DEFINER function to check ticket ownership without
-- triggering RLS on the tickets table, breaking the circular reference.

-- Create a helper function that checks ticket ownership bypassing RLS
CREATE OR REPLACE FUNCTION check_ticket_owner(p_ticket_id UUID, p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM tickets
    WHERE id = p_ticket_id
    AND sold_by = p_user_id
    AND status = 'valid'
  );
$$;

-- Drop the old INSERT policy that causes recursion
DROP POLICY IF EXISTS "Sellers can create listings" ON resale_listings;

-- Recreate using the SECURITY DEFINER function (no RLS check on tickets = no recursion)
CREATE POLICY "Sellers can create listings"
    ON resale_listings
    FOR INSERT
    WITH CHECK (
        auth.uid() = seller_id
        AND check_ticket_owner(ticket_id, auth.uid())
    );
