-- Add hide_location column to events table
-- When true, location details are only shown to ticket holders

ALTER TABLE events
ADD COLUMN IF NOT EXISTS hide_location BOOLEAN DEFAULT FALSE;

-- Add comment for documentation
COMMENT ON COLUMN events.hide_location IS 'When true, venue/city/country are only revealed after ticket purchase';
