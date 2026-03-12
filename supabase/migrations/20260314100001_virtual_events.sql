-- Virtual Events: Timed Lockdown + Link Reveal
-- Adds event_format, virtual meeting URL/password, and lockdown system.

-- 1. Add virtual event columns to events table
ALTER TABLE events
  ADD COLUMN IF NOT EXISTS event_format TEXT NOT NULL DEFAULT 'in_person'
    CHECK (event_format IN ('in_person', 'virtual', 'hybrid')),
  ADD COLUMN IF NOT EXISTS virtual_event_url TEXT,
  ADD COLUMN IF NOT EXISTS virtual_event_password TEXT,
  ADD COLUMN IF NOT EXISTS virtual_locked BOOLEAN NOT NULL DEFAULT false;

-- 2. Extend block_private_ticket_resale trigger to also block resale on locked virtual events
CREATE OR REPLACE FUNCTION block_private_ticket_resale()
RETURNS TRIGGER AS $$
DECLARE
  v_ticket_mode TEXT;
  v_nft_enabled BOOLEAN;
  v_nft_minted BOOLEAN;
  v_virtual_locked BOOLEAN;
BEGIN
  -- Get ticket mode
  SELECT ticket_mode, nft_minted INTO v_ticket_mode, v_nft_minted
  FROM tickets WHERE id = NEW.ticket_id;

  -- Block private tickets
  IF v_ticket_mode = 'private' THEN
    RAISE EXCEPTION 'Private tickets cannot be listed for resale';
  END IF;

  -- Block unminted NFT/public tickets
  SELECT nft_enabled INTO v_nft_enabled
  FROM events WHERE id = (SELECT event_id FROM tickets WHERE id = NEW.ticket_id);

  IF (v_nft_enabled = true OR v_ticket_mode = 'public') AND v_nft_minted = false THEN
    RAISE EXCEPTION 'Ticket NFT has not been minted yet — please wait before listing';
  END IF;

  -- Block resale on locked virtual events
  SELECT e.virtual_locked INTO v_virtual_locked
  FROM events e
  JOIN tickets t ON t.event_id = e.id
  WHERE t.id = NEW.ticket_id;

  IF v_virtual_locked = true THEN
    RAISE EXCEPTION 'Resale is locked for this virtual event';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Lockdown function: finds unlocked virtual/hybrid events at T-1h,
--    locks them, cancels active resale listings, resets ticket listing status,
--    and inserts notifications for ticket holders.
CREATE OR REPLACE FUNCTION lockdown_virtual_events()
RETURNS void AS $$
DECLARE
  v_event RECORD;
  v_ticket RECORD;
BEGIN
  -- Find events that should be locked down
  FOR v_event IN
    SELECT id, title
    FROM events
    WHERE event_format IN ('virtual', 'hybrid')
      AND virtual_locked = false
      AND date <= NOW() + INTERVAL '1 hour'
      AND date > NOW() - INTERVAL '1 day' -- don't process very old events
  LOOP
    -- Lock the event
    UPDATE events SET virtual_locked = true WHERE id = v_event.id;

    -- Cancel active resale listings for this event
    UPDATE resale_listings
    SET status = 'cancelled'
    WHERE status = 'active'
      AND ticket_id IN (SELECT id FROM tickets WHERE event_id = v_event.id);

    -- Reset listing status on tickets
    UPDATE tickets
    SET listing_status = 'none', listing_price_cents = NULL
    WHERE event_id = v_event.id
      AND listing_status = 'listed';

    -- Insert notifications for all valid ticket holders
    FOR v_ticket IN
      SELECT owner_user_id
      FROM tickets
      WHERE event_id = v_event.id
        AND status = 'valid'
        AND owner_user_id IS NOT NULL
    LOOP
      INSERT INTO notifications (user_id, type, title, body, data)
      VALUES (
        v_ticket.owner_user_id,
        'virtual_event_revealed',
        'Virtual event link available',
        'The meeting link for "' || v_event.title || '" is now available. Check your ticket!',
        jsonb_build_object('event_id', v_event.id, 'event_title', v_event.title)
      );
    END LOOP;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Schedule lockdown check every 5 minutes via pg_cron
SELECT cron.schedule(
  'lockdown-virtual-events',
  '*/5 * * * *',
  $$SELECT lockdown_virtual_events()$$
);
