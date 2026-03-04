-- ============================================================
-- DEV ENGAGEMENT SEED DATA
-- ============================================================
--
-- PURPOSE
-- -------
-- Populates event_views with realistic fake data so the admin
-- Engagement dashboard has something to display during development.
--
-- HOW TO RUN
-- ----------
-- Option A: Supabase SQL Editor (Dashboard → SQL → paste & run)
-- Option B: psql < supabase/seeds/dev_engagement_seed.sql
-- Option C: supabase db reset  (if added to seed.sql)
--
-- HOW TO IDENTIFY DEV DATA
-- ------------------------
-- 1. A marker row exists in analytics_cache_meta:
--      key = 'dev_seed_marker'
--    Query:  SELECT * FROM analytics_cache_meta
--            WHERE key = 'dev_seed_marker';
--    If that row exists → dev seed data is present.
--
-- 2. All seeded event_views have viewed_at in the range
--    [now() - 60 days, now()]. After cleanup, real organic
--    views will accumulate naturally from app usage.
--
-- HOW TO REMOVE
-- -------------
-- Run the CLEANUP block below (or the companion cleanup script):
--
--   TRUNCATE event_views, analytics_engagement_daily;
--   DELETE FROM analytics_cache_meta WHERE key = 'dev_seed_marker';
--   UPDATE analytics_cache_meta SET refreshed_at = now()
--     WHERE key = 'engagement_last_refresh';
--
-- This is safe because:
--   - event_views only contains view telemetry (no business data)
--   - analytics_engagement_daily is a derived cache
--   - Real views will re-accumulate from app usage
--
-- VOLUME
-- ------
-- Generates ~1,500-2,500 rows across up to 10 events and
-- 20 viewers over 60 days with varied sources. Enough to
-- make charts, tables, and KPIs look realistic.
-- ============================================================

-- ── 0. Safety: skip if already seeded ─────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM analytics_cache_meta WHERE key = 'dev_seed_marker') THEN
    RAISE NOTICE 'Dev engagement seed already present — skipping. Run cleanup first to re-seed.';
    RETURN;
  END IF;

  -- ── 1. Plant the marker ───────────────────────────────────
  INSERT INTO analytics_cache_meta (key, refreshed_at)
  VALUES ('dev_seed_marker', now());

  -- ── 2. Seed event_views ───────────────────────────────────
  -- Pick up to 10 real events and 20 real users, then generate
  -- a sparse cross-join with random dates and sources.
  INSERT INTO event_views (event_id, viewer_id, viewed_at, source)
  SELECT
    e_id,
    v_id,
    -- Random timestamp within each day
    day + (random() * interval '23 hours' + interval '30 minutes'),
    (ARRAY['home_feed','search','tag_browse','direct','shared','notification'])[
      floor(random() * 6 + 1)::int
    ]
  FROM (
    -- Expand every (event, viewer, day) triple
    SELECT
      e.id AS e_id,
      v.id AS v_id,
      d.day
    FROM (SELECT id FROM events WHERE deleted_at IS NULL ORDER BY date DESC LIMIT 10) e
    CROSS JOIN (SELECT id FROM profiles ORDER BY referred_at DESC NULLS LAST LIMIT 20) v
    CROSS JOIN (
      SELECT generate_series(
        (now() - interval '60 days')::date,
        now()::date,
        interval '1 day'
      )::date AS day
    ) d
  ) combos
  -- ~2.5% sampling keeps volume reasonable (~1500-2500 rows)
  WHERE random() < 0.025
  ON CONFLICT DO NOTHING;

  -- ── 3. Skew some events to have more views (top performers) ──
  -- Give the 3 most recent events an extra burst in the last 14 days
  INSERT INTO event_views (event_id, viewer_id, viewed_at, source)
  SELECT
    e.id,
    v.id,
    (now() - (random() * interval '14 days')) + (random() * interval '12 hours'),
    (ARRAY['home_feed','search','shared','direct'])[
      floor(random() * 4 + 1)::int
    ]
  FROM (SELECT id FROM events WHERE deleted_at IS NULL ORDER BY date DESC LIMIT 3) e
  CROSS JOIN (SELECT id FROM profiles ORDER BY referred_at DESC NULLS LAST LIMIT 15) v
  WHERE random() < 0.15
  ON CONFLICT DO NOTHING;

  -- ── 4. Refresh the engagement cache ───────────────────────
  PERFORM refresh_engagement_cache();

  RAISE NOTICE 'Dev engagement seed complete. Check admin dashboard → Engagement.';
END;
$$;
