-- Fix: remove accepted_at column reference (doesn't exist in event_staff)
CREATE OR REPLACE FUNCTION auto_add_organizer_as_staff()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO event_staff (event_id, user_id, role)
    VALUES (NEW.id, NEW.organizer_id, 'manager')
    ON CONFLICT DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
