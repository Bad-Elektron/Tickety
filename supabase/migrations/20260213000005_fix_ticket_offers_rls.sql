-- Fix RLS policies that query auth.users (not accessible to authenticated role).
-- Use auth.jwt() ->> 'email' instead.

-- Drop the broken policies
DROP POLICY IF EXISTS "recipients_view_their_offers" ON ticket_offers;
DROP POLICY IF EXISTS "recipients_update_their_offers" ON ticket_offers;

-- Recreate with JWT email extraction
CREATE POLICY "recipients_view_their_offers" ON ticket_offers
    FOR SELECT
    USING (
        auth.uid() = recipient_user_id
        OR recipient_email = (auth.jwt() ->> 'email')
    );

CREATE POLICY "recipients_update_their_offers" ON ticket_offers
    FOR UPDATE
    USING (
        auth.uid() = recipient_user_id
        OR recipient_email = (auth.jwt() ->> 'email')
    )
    WITH CHECK (
        auth.uid() = recipient_user_id
        OR recipient_email = (auth.jwt() ->> 'email')
    );
