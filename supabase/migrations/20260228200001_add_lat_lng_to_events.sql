-- Add latitude, longitude, and formatted_address to events table
-- All nullable for backward compatibility with existing events
ALTER TABLE events
  ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS formatted_address TEXT;
