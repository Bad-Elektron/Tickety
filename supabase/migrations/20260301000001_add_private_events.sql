-- Add private event support with invite codes

-- Add columns to events table
ALTER TABLE events
  ADD COLUMN IF NOT EXISTS is_private BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS invite_code VARCHAR(8) UNIQUE;

-- Index for fast invite code lookups
CREATE INDEX IF NOT EXISTS idx_events_invite_code ON events (invite_code) WHERE invite_code IS NOT NULL;

-- Trigger function: auto-generate invite code for private events, clear for public
CREATE OR REPLACE FUNCTION generate_event_invite_code()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_private = true AND NEW.invite_code IS NULL THEN
    -- Generate 8-char uppercase alphanumeric code (same pattern as referral codes)
    NEW.invite_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  ELSIF NEW.is_private = false THEN
    NEW.invite_code := NULL;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger on insert and update
CREATE TRIGGER trg_generate_event_invite_code
  BEFORE INSERT OR UPDATE ON events
  FOR EACH ROW
  EXECUTE FUNCTION generate_event_invite_code();
