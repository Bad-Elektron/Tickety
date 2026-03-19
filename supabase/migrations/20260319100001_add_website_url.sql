-- Add website URL field to events (Pro+ feature)
ALTER TABLE events ADD COLUMN IF NOT EXISTS website_url TEXT;
