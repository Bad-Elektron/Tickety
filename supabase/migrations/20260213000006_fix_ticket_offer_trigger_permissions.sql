-- Fix: Replace auth.users lookup with profiles lookup to avoid permission issues.
-- The trigger runs during authenticated user INSERTs and auth.users is not
-- accessible to the authenticated role.

CREATE OR REPLACE FUNCTION notify_ticket_offer_created()
RETURNS TRIGGER AS $$
DECLARE
    event_title TEXT;
    organizer_name TEXT;
    recipient_uid UUID;
    price_label TEXT;
BEGIN
    -- Get event title
    SELECT title INTO event_title FROM events WHERE id = NEW.event_id;

    -- Get organizer name
    SELECT display_name INTO organizer_name FROM profiles WHERE id = NEW.organizer_id;

    -- Look up recipient by email using profiles table (not auth.users)
    SELECT id INTO recipient_uid FROM profiles WHERE email = NEW.recipient_email;

    -- If recipient is not registered yet, skip notification (handled by signup trigger)
    IF recipient_uid IS NULL THEN
        RETURN NEW;
    END IF;

    -- Link the recipient user ID if not already set
    IF NEW.recipient_user_id IS NULL THEN
        NEW.recipient_user_id := recipient_uid;
    END IF;

    -- Format price label
    IF NEW.price_cents = 0 THEN
        price_label := 'Free';
    ELSE
        price_label := '$' || (NEW.price_cents / 100.0)::NUMERIC(10,2)::TEXT;
    END IF;

    -- Create notification
    INSERT INTO notifications (user_id, type, title, body, data)
    VALUES (
        recipient_uid,
        'favor_ticket_offer',
        'You received a ticket offer!',
        COALESCE(organizer_name, 'An organizer') || ' sent you a ' || price_label || ' ticket for ' || COALESCE(event_title, 'an event'),
        jsonb_build_object(
            'offer_id', NEW.id,
            'event_id', NEW.event_id,
            'event_title', event_title,
            'organizer_name', organizer_name,
            'price_cents', NEW.price_cents,
            'ticket_mode', NEW.ticket_mode,
            'message', NEW.message
        )
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
