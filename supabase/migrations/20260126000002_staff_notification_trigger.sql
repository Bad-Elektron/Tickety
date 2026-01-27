-- Function to create notification when staff is added to an event
CREATE OR REPLACE FUNCTION notify_staff_added()
RETURNS TRIGGER AS $$
DECLARE
    event_record RECORD;
    role_label TEXT;
BEGIN
    -- Get event details
    SELECT title INTO event_record FROM events WHERE id = NEW.event_id;

    -- Format role label for display
    role_label := CASE NEW.role
        WHEN 'usher' THEN 'Usher'
        WHEN 'seller' THEN 'Seller'
        WHEN 'manager' THEN 'Manager'
        ELSE INITCAP(NEW.role)
    END;

    -- Insert notification for the new staff member
    INSERT INTO notifications (user_id, type, title, body, data)
    VALUES (
        NEW.user_id,
        'staff_added',
        'You''ve been added as staff!',
        'You are now a ' || role_label || ' for ' || COALESCE(event_record.title, 'an event'),
        jsonb_build_object(
            'event_id', NEW.event_id,
            'event_title', event_record.title,
            'role', NEW.role,
            'staff_id', NEW.id
        )
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on event_staff insert
CREATE TRIGGER on_staff_added
    AFTER INSERT ON event_staff
    FOR EACH ROW
    EXECUTE FUNCTION notify_staff_added();

-- Comment
COMMENT ON FUNCTION notify_staff_added() IS 'Creates a notification when a user is added as staff to an event';
