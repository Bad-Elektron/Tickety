-- Add access password support for events and individual ticket types.
-- Event-level password = "master password" that unlocks all tickets.
-- Ticket-type-level password = unlocks only that specific ticket type.

-- ── Event-level access password ──
ALTER TABLE events
  ADD COLUMN IF NOT EXISTS access_password VARCHAR(8);

-- Auto-generate 8-char uppercase alphanumeric password when set to non-null empty string
-- Organizer can also supply their own custom password.
CREATE OR REPLACE FUNCTION generate_event_access_password()
RETURNS TRIGGER AS $$
BEGIN
  -- If password is explicitly set to empty string, auto-generate one
  IF NEW.access_password = '' THEN
    NEW.access_password := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_generate_event_access_password
  BEFORE INSERT OR UPDATE ON events
  FOR EACH ROW
  EXECUTE FUNCTION generate_event_access_password();

-- ── Ticket-type-level access password ──
ALTER TABLE event_ticket_types
  ADD COLUMN IF NOT EXISTS access_password VARCHAR(64);

-- Index for fast password lookups
CREATE INDEX IF NOT EXISTS idx_events_access_password
  ON events (access_password) WHERE access_password IS NOT NULL;
