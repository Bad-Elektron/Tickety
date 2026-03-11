-- Add preferred_currency to profiles (default USD)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS preferred_currency TEXT NOT NULL DEFAULT 'usd';
