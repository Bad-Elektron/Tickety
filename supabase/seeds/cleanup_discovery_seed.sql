-- ============================================================
-- CLEANUP: Remove Dev Discovery Seed Data
-- ============================================================
-- Removes seeded tickets, payments, tag affinity, and scores.
-- Does NOT remove event_views (use cleanup_engagement_seed.sql
-- for that).
--
-- Safe to run multiple times (idempotent).
-- ============================================================

-- Remove seeded tickets (identifiable by DSEED- prefix)
DELETE FROM tickets WHERE ticket_number LIKE 'DSEED-%';

-- Remove seeded payments (from seed test emails)
-- We can't easily identify seeded payments, so only remove
-- if the discovery seed marker exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM analytics_cache_meta WHERE key = 'discovery_seed_marker') THEN
    -- Truncate tag affinity (all dev data)
    TRUNCATE user_tag_affinity;

    -- Clear computed scores (will be rebuilt from real data)
    TRUNCATE event_scores;

    -- Reset discovery weights to defaults
    UPDATE discovery_weights SET
      weight = CASE key
        WHEN 'popularity' THEN 0.25
        WHEN 'velocity' THEN 0.20
        WHEN 'engagement' THEN 0.20
        WHEN 'recency' THEN 0.15
        WHEN 'urgency' THEN 0.10
        WHEN 'organizer_quality' THEN 0.10
        WHEN 'proximity' THEN 0.30
        WHEN 'tag_affinity' THEN 0.25
        WHEN 'price_match' THEN 0.10
        ELSE weight
      END,
      updated_at = now();

    -- Clear weight history
    TRUNCATE discovery_weight_history;

    -- Remove marker
    DELETE FROM analytics_cache_meta WHERE key = 'discovery_seed_marker';

    RAISE NOTICE 'Discovery seed data removed. Run refresh_event_scores() to recompute from real data.';
  ELSE
    RAISE NOTICE 'No discovery seed marker found — nothing to clean up.';
  END IF;
END;
$$;
