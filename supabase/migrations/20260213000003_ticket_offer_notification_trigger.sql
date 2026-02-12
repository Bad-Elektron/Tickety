-- Trigger to create notification when a ticket offer is created
CREATE OR REPLACE FUNCTION notify_ticket_offer_created()
RETURNS TRIGGER AS $$
DECLARE
    event_record RECORD;
    organizer_record RECORD;
    recipient_uid UUID;
    price_label TEXT;
BEGIN
    -- Get event details
    SELECT title INTO event_record FROM events WHERE id = NEW.event_id;

    -- Get organizer name
    SELECT display_name INTO organizer_record FROM profiles WHERE id = NEW.organizer_id;

    -- Look up recipient by email
    SELECT id INTO recipient_uid FROM auth.users WHERE email = NEW.recipient_email;

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
        COALESCE(organizer_record.display_name, 'An organizer') || ' sent you a ' || price_label || ' ticket for ' || COALESCE(event_record.title, 'an event'),
        jsonb_build_object(
            'offer_id', NEW.id,
            'event_id', NEW.event_id,
            'event_title', event_record.title,
            'organizer_name', organizer_record.display_name,
            'price_cents', NEW.price_cents,
            'ticket_mode', NEW.ticket_mode,
            'message', NEW.message
        )
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on ticket_offers insert
CREATE TRIGGER on_ticket_offer_created
    BEFORE INSERT ON ticket_offers
    FOR EACH ROW
    EXECUTE FUNCTION notify_ticket_offer_created();

COMMENT ON FUNCTION notify_ticket_offer_created() IS 'Creates a notification when a favor ticket offer is sent to a registered user';
