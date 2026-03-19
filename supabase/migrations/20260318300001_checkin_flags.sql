-- Verification discrepancy flags for check-in audit trail.
--
-- Records cases where a ticket was admitted via offline cache but
-- failed blockchain or database verification. Synced from the
-- usher's device during background sync cycles.

CREATE TABLE IF NOT EXISTS checkin_flags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  flag_type TEXT NOT NULL, -- 'blockchain_failed', 'database_mismatch'
  tier TEXT NOT NULL,      -- 'blockchain', 'database'
  message TEXT,
  flagged_by UUID NOT NULL REFERENCES auth.users(id),
  flagged_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved BOOLEAN NOT NULL DEFAULT false,
  resolved_by UUID REFERENCES auth.users(id),
  resolved_at TIMESTAMPTZ,
  resolution_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_checkin_flags_event ON checkin_flags(event_id);
CREATE INDEX idx_checkin_flags_ticket ON checkin_flags(ticket_id);
CREATE INDEX idx_checkin_flags_unresolved ON checkin_flags(event_id) WHERE NOT resolved;

-- RLS: organizers and staff can read flags for their events,
-- ushers can insert flags, organizers can resolve them.
ALTER TABLE checkin_flags ENABLE ROW LEVEL SECURITY;

-- Ushers/vendors/organizers can insert flags for events they're assigned to
CREATE POLICY checkin_flags_insert ON checkin_flags
  FOR INSERT TO authenticated
  WITH CHECK (
    flagged_by = auth.uid()
    AND (
      -- Event organizer
      EXISTS (
        SELECT 1 FROM events WHERE id = event_id AND organizer_id = auth.uid()
      )
      -- Or assigned staff (usher/vendor)
      OR EXISTS (
        SELECT 1 FROM event_staff
        WHERE event_staff.event_id = checkin_flags.event_id
          AND user_id = auth.uid()
      )
    )
  );

-- Organizers and staff can read flags for their events
CREATE POLICY checkin_flags_select ON checkin_flags
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM events WHERE id = event_id AND organizer_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM event_staff
      WHERE event_staff.event_id = checkin_flags.event_id
        AND user_id = auth.uid()
    )
  );

-- Only organizers can resolve flags
CREATE POLICY checkin_flags_update ON checkin_flags
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM events WHERE id = event_id AND organizer_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM events WHERE id = event_id AND organizer_id = auth.uid()
    )
  );

-- Helper: get unresolved flag count for an event (used in admin dashboard badge)
CREATE OR REPLACE FUNCTION get_checkin_flag_count(p_event_id UUID)
RETURNS INTEGER
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
  SELECT COUNT(*)::INTEGER
  FROM checkin_flags
  WHERE event_id = p_event_id AND NOT resolved;
$$;
