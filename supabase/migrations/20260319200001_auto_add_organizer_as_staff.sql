-- Auto-add event organizer as manager staff when an event is created.
-- This ensures organizers can always scan tickets and sell at their own events.

CREATE OR REPLACE FUNCTION auto_add_organizer_as_staff()
RETURNS TRIGGER AS $$
BEGIN
    -- Only for new events (not updates)
    -- Add the organizer as a manager (can check tickets + sell + manage staff)
    INSERT INTO event_staff (event_id, user_id, role, accepted_at)
    VALUES (NEW.id, NEW.organizer_id, 'manager', now())
    ON CONFLICT DO NOTHING; -- Skip if already staff (e.g., recurring series template)

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger fires after event creation
DROP TRIGGER IF EXISTS trg_auto_add_organizer_staff ON events;
CREATE TRIGGER trg_auto_add_organizer_staff
    AFTER INSERT ON events
    FOR EACH ROW
    EXECUTE FUNCTION auto_add_organizer_as_staff();
