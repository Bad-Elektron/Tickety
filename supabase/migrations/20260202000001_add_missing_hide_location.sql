-- Add hide_location column to events table if it doesn't exist
ALTER TABLE events ADD COLUMN IF NOT EXISTS hide_location BOOLEAN DEFAULT FALSE;
