-- Trigger to check for pending ticket offers when a new user signs up
CREATE OR REPLACE FUNCTION check_pending_offers_on_signup()
RETURNS TRIGGER AS $$
DECLARE
    offer_record RECORD;
    event_record RECORD;
    organizer_record RECORD;
    price_label TEXT;
BEGIN
    -- Find pending offers matching the new user's email
    FOR offer_record IN
        SELECT * FROM ticket_offers
        WHERE recipient_email = NEW.email
        AND status = 'pending'
        AND recipient_user_id IS NULL
    LOOP
        -- Link the offer to the new user
        UPDATE ticket_offers
        SET recipient_user_id = NEW.id
        WHERE id = offer_record.id;

        -- Get event details
        SELECT title INTO event_record FROM events WHERE id = offer_record.event_id;

        -- Get organizer name
        SELECT display_name INTO organizer_record FROM profiles WHERE id = offer_record.organizer_id;

        -- Format price label
        IF offer_record.price_cents = 0 THEN
            price_label := 'Free';
        ELSE
            price_label := '$' || (offer_record.price_cents / 100.0)::NUMERIC(10,2)::TEXT;
        END IF;

        -- Create notification for the new user
        INSERT INTO notifications (user_id, type, title, body, data)
        VALUES (
            NEW.id,
            'favor_ticket_offer',
            'You received a ticket offer!',
            COALESCE(organizer_record.display_name, 'An organizer') || ' sent you a ' || price_label || ' ticket for ' || COALESCE(event_record.title, 'an event'),
            jsonb_build_object(
                'offer_id', offer_record.id,
                'event_id', offer_record.event_id,
                'event_title', event_record.title,
                'organizer_name', organizer_record.display_name,
                'price_cents', offer_record.price_cents,
                'ticket_mode', offer_record.ticket_mode,
                'message', offer_record.message
            )
        );
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on auth.users insert
CREATE TRIGGER on_user_signup_check_offers
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION check_pending_offers_on_signup();

COMMENT ON FUNCTION check_pending_offers_on_signup() IS 'Links pending ticket offers and creates notifications when a new user signs up';
