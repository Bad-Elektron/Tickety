-- Update access password to support shorter (5 char) default generation
-- and allow longer custom passwords.

-- Widen column to allow custom passwords of any reasonable length
ALTER TABLE events ALTER COLUMN access_password TYPE VARCHAR(64);

-- Update trigger to generate 5-char passwords
CREATE OR REPLACE FUNCTION generate_event_access_password()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.access_password = '' THEN
    NEW.access_password := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 5));
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
