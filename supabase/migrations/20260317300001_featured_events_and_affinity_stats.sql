-- ============================================================
-- Featured Events + Platform Tag Affinity Stats
-- ============================================================
-- 1. Add featured_at column to events (admin hand-feature)
-- 2. RPC to get platform-wide tag affinity summary for admin dashboard
-- 3. Update featured query to use scores + pinned events

-- ── 1. Add featured_at to events ───────────────────────────
-- NULL = not featured. Timestamp = when it was featured.
-- Hand-featured events always appear first in the carousel.

ALTER TABLE events ADD COLUMN IF NOT EXISTS featured_at TIMESTAMPTZ;

COMMENT ON COLUMN events.featured_at IS 'When this event was hand-featured by an admin. NULL = not featured.';

CREATE INDEX idx_events_featured ON events (featured_at DESC NULLS LAST)
  WHERE featured_at IS NOT NULL AND deleted_at IS NULL;

-- ── 2. get_featured_events() ───────────────────────────────
-- Returns featured events: hand-pinned first, then top-scored.
-- Efficient: reads from pre-computed event_scores table.

CREATE OR REPLACE FUNCTION get_featured_events(p_limit INT DEFAULT 5)
RETURNS TABLE (
  event_id UUID,
  is_pinned BOOLEAN,
  composite_score FLOAT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  (
    -- Hand-pinned events first (ordered by when they were featured)
    SELECT
      e.id AS event_id,
      true AS is_pinned,
      COALESCE(es.composite_score, 0.0) AS composite_score
    FROM events e
    LEFT JOIN event_scores es ON es.event_id = e.id
    WHERE e.featured_at IS NOT NULL
      AND e.deleted_at IS NULL
      AND e.status = 'active'
      AND e.date >= now()
      AND e.is_private = false
    ORDER BY e.featured_at DESC
  )
  UNION ALL
  (
    -- Top-scored events (excluding already-pinned ones)
    SELECT
      es.event_id,
      false AS is_pinned,
      es.composite_score
    FROM event_scores es
    JOIN events e ON e.id = es.event_id
    WHERE e.deleted_at IS NULL
      AND e.status = 'active'
      AND e.date >= now()
      AND e.is_private = false
      AND e.featured_at IS NULL  -- exclude pinned (already in first query)
    ORDER BY es.composite_score DESC
  )
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION get_featured_events(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_featured_events(INT) TO service_role;

-- ── 3. toggle_featured_event() ─────────────────────────────
-- Admin toggle: feature or unfeature an event.

CREATE OR REPLACE FUNCTION toggle_featured_event(p_event_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current TIMESTAMPTZ;
  v_new_state BOOLEAN;
BEGIN
  SELECT featured_at INTO v_current FROM events WHERE id = p_event_id;

  IF v_current IS NULL THEN
    UPDATE events SET featured_at = now() WHERE id = p_event_id;
    v_new_state := true;
  ELSE
    UPDATE events SET featured_at = NULL WHERE id = p_event_id;
    v_new_state := false;
  END IF;

  RETURN v_new_state;
END;
$$;

GRANT EXECUTE ON FUNCTION toggle_featured_event(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION toggle_featured_event(UUID) TO service_role;

-- ── 4. get_platform_tag_affinity() ─────────────────────────
-- Aggregates tag affinity across all users for admin dashboard.
-- Returns top tags by total affinity + user count.

CREATE OR REPLACE FUNCTION get_platform_tag_affinity(p_limit INT DEFAULT 15)
RETURNS TABLE (
  tag TEXT,
  user_count BIGINT,
  total_affinity FLOAT,
  avg_affinity FLOAT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    uta.tag,
    COUNT(DISTINCT uta.user_id) AS user_count,
    SUM(uta.affinity_score)::float AS total_affinity,
    AVG(uta.affinity_score)::float AS avg_affinity
  FROM user_tag_affinity uta
  WHERE uta.last_interaction >= now() - interval '90 days'
  GROUP BY uta.tag
  ORDER BY SUM(uta.affinity_score) DESC
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION get_platform_tag_affinity(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_platform_tag_affinity(INT) TO service_role;
