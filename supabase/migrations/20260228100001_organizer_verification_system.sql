-- ============================================================
-- Organizer Verification & Event Security System
-- ============================================================
-- Adds identity verification for organizers, event status system,
-- event reporting, auto-hold for large unverified events,
-- and similarity detection.

-- ============================================================
-- 1. Profile additions for identity verification
-- ============================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS identity_verification_status TEXT DEFAULT 'none';
  -- Values: 'none', 'pending', 'verified', 'failed'
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS identity_verified_at TIMESTAMPTZ;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS stripe_identity_session_id TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS payout_delay_days INTEGER DEFAULT 14;
  -- 14 for unverified, reduced to 2 after verification

-- ============================================================
-- 2. Event status system
-- ============================================================

ALTER TABLE events ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active';
  -- 'active' = live and visible to buyers
  -- 'pending_review' = auto-held, needs admin approval
  -- 'suspended' = admin took it down
ALTER TABLE events ADD COLUMN IF NOT EXISTS status_reason TEXT;

-- ============================================================
-- 3. Event reports table
-- ============================================================

CREATE TABLE IF NOT EXISTS event_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  reporter_id UUID NOT NULL REFERENCES auth.users(id),
  reason TEXT NOT NULL,
    -- 'impersonation', 'scam', 'inappropriate', 'duplicate', 'other'
  description TEXT,
  status TEXT NOT NULL DEFAULT 'open',
    -- 'open', 'reviewed', 'resolved', 'dismissed'
  reviewed_by UUID REFERENCES auth.users(id),
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(event_id, reporter_id)
);

-- RLS for event_reports
ALTER TABLE event_reports ENABLE ROW LEVEL SECURITY;

-- Reporters can insert their own reports
CREATE POLICY "Users can report events"
  ON event_reports FOR INSERT
  TO authenticated
  WITH CHECK (reporter_id = auth.uid());

-- Reporters can view their own reports
CREATE POLICY "Users can view own reports"
  ON event_reports FOR SELECT
  TO authenticated
  USING (reporter_id = auth.uid());

-- Service role can do anything (for admin API)
CREATE POLICY "Service role full access to reports"
  ON event_reports FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ============================================================
-- 4. Auto-hold trigger for unverified large events
-- ============================================================

CREATE OR REPLACE FUNCTION auto_hold_unverified_large_events()
RETURNS TRIGGER AS $$
DECLARE
  v_feature_enabled BOOLEAN;
BEGIN
  -- Check if feature flag is enabled
  SELECT enabled INTO v_feature_enabled
  FROM feature_flags
  WHERE key = 'organizer_verification';

  -- If flag doesn't exist or is disabled, skip
  IF v_feature_enabled IS NOT TRUE THEN
    RETURN NEW;
  END IF;

  -- Calculate total capacity across ticket types on UPDATE
  -- On INSERT, max_tickets may be set directly
  IF NEW.max_tickets IS NOT NULL AND NEW.max_tickets >= 250 THEN
    -- Check if organizer is verified
    IF NOT EXISTS (
      SELECT 1 FROM profiles
      WHERE id = NEW.organizer_id
      AND identity_verification_status = 'verified'
    ) THEN
      NEW.status := 'pending_review';
      NEW.status_reason := 'Events with 250+ capacity require organizer identity verification';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on INSERT and UPDATE of max_tickets
DROP TRIGGER IF EXISTS trigger_auto_hold_unverified_large_events ON events;
CREATE TRIGGER trigger_auto_hold_unverified_large_events
  BEFORE INSERT OR UPDATE OF max_tickets ON events
  FOR EACH ROW
  EXECUTE FUNCTION auto_hold_unverified_large_events();

-- ============================================================
-- 5. Similarity detection function (pg_trgm)
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE OR REPLACE FUNCTION find_similar_events(
  p_title TEXT,
  p_venue TEXT DEFAULT NULL,
  p_date DATE DEFAULT NULL
)
RETURNS TABLE(event_id UUID, title TEXT, venue TEXT, similarity FLOAT)
AS $$
  SELECT e.id, e.title, e.venue,
    similarity(e.title, p_title)::FLOAT AS sim
  FROM events e
  WHERE e.status = 'active'
    AND e.deleted_at IS NULL
    AND similarity(e.title, p_title) > 0.4
    AND (p_venue IS NULL OR e.venue ILIKE '%' || p_venue || '%')
    AND (p_date IS NULL OR e.date::date BETWEEN p_date - 7 AND p_date + 7)
  ORDER BY sim DESC
  LIMIT 10;
$$ LANGUAGE sql STABLE;

-- ============================================================
-- 6. Feature flags for verification system
-- ============================================================

INSERT INTO feature_flags (key, enabled, description) VALUES
  ('organizer_verification', true, 'Require identity verification for 250+ capacity events'),
  ('event_similarity_check', true, 'Warn about similar events on creation'),
  ('event_reporting', true, 'Allow users to report suspicious events')
ON CONFLICT (key) DO NOTHING;
