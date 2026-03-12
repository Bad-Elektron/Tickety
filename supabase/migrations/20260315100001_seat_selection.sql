-- Seat selection at checkout: holds, ticket seat assignment, payment seat data
-- ============================================================================

-- Add seat assignment columns to tickets
ALTER TABLE tickets
  ADD COLUMN IF NOT EXISTS venue_section_id TEXT,
  ADD COLUMN IF NOT EXISTS seat_id TEXT,
  ADD COLUMN IF NOT EXISTS seat_label TEXT;

-- Add seat_selections JSONB to payments (avoids Stripe metadata size limits)
ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS seat_selections JSONB;

-- Index for fast lookup of sold seats per event+section
CREATE INDEX IF NOT EXISTS idx_tickets_event_section_seat
  ON tickets(event_id, venue_section_id, seat_id)
  WHERE venue_section_id IS NOT NULL;

-- Seat holds: temporary locks during checkout flow
CREATE TABLE IF NOT EXISTS seat_holds (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  venue_section_id TEXT NOT NULL,
  seat_id TEXT NOT NULL,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (event_id, venue_section_id, seat_id)
);

-- Index for expiry cleanup
CREATE INDEX IF NOT EXISTS idx_seat_holds_expires
  ON seat_holds(expires_at);

-- RLS policies
ALTER TABLE seat_holds ENABLE ROW LEVEL SECURITY;

-- Anyone can read holds (to see which seats are taken)
CREATE POLICY "Public can read seat holds"
  ON seat_holds FOR SELECT
  USING (true);

-- Users can insert their own holds
CREATE POLICY "Users can create own holds"
  ON seat_holds FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can delete their own holds
CREATE POLICY "Users can delete own holds"
  ON seat_holds FOR DELETE
  USING (auth.uid() = user_id);

-- pg_cron: expire stale holds every minute
SELECT cron.schedule(
  'expire-seat-holds',
  '* * * * *',
  $$DELETE FROM seat_holds WHERE expires_at < now()$$
);
