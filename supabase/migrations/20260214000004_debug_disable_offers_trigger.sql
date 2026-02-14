-- Temporarily replace check_pending_offers_on_signup with a no-op
-- to test if it's causing the signup failure.
-- RESTORE AFTER DEBUGGING.

CREATE OR REPLACE FUNCTION check_pending_offers_on_signup()
RETURNS TRIGGER AS $$
BEGIN
    -- NO-OP for debugging
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
