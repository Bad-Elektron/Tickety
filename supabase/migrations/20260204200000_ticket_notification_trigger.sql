-- Create a trigger to send notifications when tickets are purchased/transferred
-- This covers all ticket creation scenarios: card purchases, cash sales, resales, transfers

CREATE OR REPLACE FUNCTION notify_ticket_received()
RETURNS TRIGGER AS $$
DECLARE
  v_event_title TEXT;
  v_user_id UUID;
BEGIN
  -- Only notify if the ticket has an owner email
  IF NEW.owner_email IS NULL OR NEW.owner_email = '' THEN
    RETURN NEW;
  END IF;

  -- Get the event title
  SELECT title INTO v_event_title
  FROM events
  WHERE id = NEW.event_id;

  -- Find the user ID from the email
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE email = NEW.owner_email;

  -- Only create notification if user exists in the system
  IF v_user_id IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, title, body, data)
    VALUES (
      v_user_id,
      'ticketPurchased',
      'Ticket Received!',
      'You have received a ticket for ' || COALESCE(v_event_title, 'an event'),
      jsonb_build_object(
        'event_id', NEW.event_id,
        'ticket_id', NEW.id,
        'ticket_number', NEW.ticket_number,
        'event_title', v_event_title
      )
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for new tickets
DROP TRIGGER IF EXISTS on_ticket_created ON tickets;
CREATE TRIGGER on_ticket_created
  AFTER INSERT ON tickets
  FOR EACH ROW
  EXECUTE FUNCTION notify_ticket_received();

-- Also trigger on update when owner_email changes (for transfers)
CREATE OR REPLACE FUNCTION notify_ticket_transferred()
RETURNS TRIGGER AS $$
DECLARE
  v_event_title TEXT;
  v_user_id UUID;
BEGIN
  -- Only notify if owner_email changed and new owner exists
  IF OLD.owner_email IS DISTINCT FROM NEW.owner_email
     AND NEW.owner_email IS NOT NULL
     AND NEW.owner_email != '' THEN

    -- Get the event title
    SELECT title INTO v_event_title
    FROM events
    WHERE id = NEW.event_id;

    -- Find the user ID from the email
    SELECT id INTO v_user_id
    FROM auth.users
    WHERE email = NEW.owner_email;

    -- Only create notification if user exists in the system
    IF v_user_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, data)
      VALUES (
        v_user_id,
        'ticketPurchased',
        'Ticket Transferred!',
        'You have received a ticket for ' || COALESCE(v_event_title, 'an event'),
        jsonb_build_object(
          'event_id', NEW.event_id,
          'ticket_id', NEW.id,
          'ticket_number', NEW.ticket_number,
          'event_title', v_event_title
        )
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for ticket transfers
DROP TRIGGER IF EXISTS on_ticket_transferred ON tickets;
CREATE TRIGGER on_ticket_transferred
  AFTER UPDATE ON tickets
  FOR EACH ROW
  EXECUTE FUNCTION notify_ticket_transferred();
