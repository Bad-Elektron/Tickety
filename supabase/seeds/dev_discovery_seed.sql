-- ============================================================
-- DEV DISCOVERY ALGORITHM SEED DATA
-- ============================================================
--
-- PURPOSE
-- -------
-- Populates event_views, tickets, and tag affinity data with
-- realistic patterns so the discovery algorithm produces
-- meaningful scores and the admin tuning dashboard has data.
--
-- HOW TO RUN
-- ----------
-- Option A: Supabase SQL Editor (Dashboard -> SQL -> paste & run)
-- Option B: psql < supabase/seeds/dev_discovery_seed.sql
--
-- PREREQUISITES
-- -------------
-- 1. Run the engagement seed first (dev_engagement_seed.sql)
--    OR have real event_views data.
-- 2. Migration 20260317200001_discovery_algorithm.sql applied.
-- 3. At least a few events and profiles in the database.
--
-- HOW TO IDENTIFY DEV DATA
-- ------------------------
-- Marker row in analytics_cache_meta:
--   key = 'discovery_seed_marker'
--
-- HOW TO REMOVE
-- -------------
-- Run cleanup_discovery_seed.sql
-- ============================================================

DO $$
DECLARE
  v_event_ids UUID[];
  v_user_ids UUID[];
  v_event_id UUID;
  v_user_id UUID;
  v_tag TEXT;
  v_tags TEXT[];
  v_i INT;
  v_j INT;
  v_days_ago INT;
  v_sold_count INT;
  v_event_count INT;
  v_user_count INT;
BEGIN
  -- ── 0. Skip if already seeded ─────────────────────────────
  IF EXISTS (SELECT 1 FROM analytics_cache_meta WHERE key = 'discovery_seed_marker') THEN
    RAISE NOTICE 'Discovery seed already present — skipping. Run cleanup first to re-seed.';
    RETURN;
  END IF;

  -- Plant marker
  INSERT INTO analytics_cache_meta (key, refreshed_at)
  VALUES ('discovery_seed_marker', now());

  -- ── 1. Gather events and users ────────────────────────────
  SELECT array_agg(id) INTO v_event_ids
  FROM (
    SELECT id FROM events
    WHERE deleted_at IS NULL
      AND status = 'active'
    ORDER BY date DESC
    LIMIT 15
  ) e;

  SELECT array_agg(id) INTO v_user_ids
  FROM (
    SELECT id FROM profiles
    ORDER BY random()
    LIMIT 25
  ) p;

  v_event_count := COALESCE(array_length(v_event_ids, 1), 0);
  v_user_count := COALESCE(array_length(v_user_ids, 1), 0);

  IF v_event_count = 0 THEN
    RAISE NOTICE 'No events found — cannot seed discovery data.';
    RETURN;
  END IF;

  IF v_user_count = 0 THEN
    RAISE NOTICE 'No profiles found — cannot seed discovery data.';
    RETURN;
  END IF;

  RAISE NOTICE 'Seeding discovery data for % events and % users', v_event_count, v_user_count;

  -- ── 2. Seed event_views with varied patterns ──────────────
  -- Some events get lots of views (popular), some get few (niche).
  -- This creates differentiated popularity scores.

  FOR v_i IN 1..v_event_count LOOP
    v_event_id := v_event_ids[v_i];

    -- First 3 events: high traffic (trending)
    -- Middle events: moderate traffic
    -- Last events: low traffic (niche)
    FOR v_j IN 1..v_user_count LOOP
      v_user_id := v_user_ids[v_j];

      -- Trending events: 80% chance of view per user per recent day
      IF v_i <= 3 THEN
        FOR v_days_ago IN 0..13 LOOP
          IF random() < 0.80 THEN
            INSERT INTO event_views (event_id, viewer_id, viewed_at, source)
            VALUES (
              v_event_id,
              v_user_id,
              now() - (v_days_ago || ' days')::interval
                + (random() * interval '16 hours')
                + interval '6 hours',
              (ARRAY['home_feed','search','shared','notification'])[
                floor(random() * 4 + 1)::int
              ]
            )
            ON CONFLICT DO NOTHING;
          END IF;
        END LOOP;

      -- Moderate events: 30% chance
      ELSIF v_i <= 8 THEN
        FOR v_days_ago IN 0..29 LOOP
          IF random() < 0.30 THEN
            INSERT INTO event_views (event_id, viewer_id, viewed_at, source)
            VALUES (
              v_event_id,
              v_user_id,
              now() - (v_days_ago || ' days')::interval
                + (random() * interval '16 hours')
                + interval '6 hours',
              (ARRAY['home_feed','tag_browse','direct','search'])[
                floor(random() * 4 + 1)::int
              ]
            )
            ON CONFLICT DO NOTHING;
          END IF;
        END LOOP;

      -- Niche events: 8% chance
      ELSE
        FOR v_days_ago IN 0..29 LOOP
          IF random() < 0.08 THEN
            INSERT INTO event_views (event_id, viewer_id, viewed_at, source)
            VALUES (
              v_event_id,
              v_user_id,
              now() - (v_days_ago || ' days')::interval
                + (random() * interval '16 hours')
                + interval '6 hours',
              (ARRAY['direct','tag_browse','shared'])[
                floor(random() * 3 + 1)::int
              ]
            )
            ON CONFLICT DO NOTHING;
          END IF;
        END LOOP;
      END IF;
    END LOOP;
  END LOOP;

  RAISE NOTICE 'Event views seeded.';

  -- ── 3. Seed tickets (sales velocity data) ─────────────────
  -- Create fake ticket purchases at varied rates.
  -- Trending events: many recent sales. Moderate: some. Niche: few.

  FOR v_i IN 1..v_event_count LOOP
    v_event_id := v_event_ids[v_i];

    -- Determine how many tickets to create
    v_sold_count := CASE
      WHEN v_i <= 3 THEN 20 + floor(random() * 30)::int   -- 20-50 tickets
      WHEN v_i <= 8 THEN 5 + floor(random() * 15)::int    -- 5-20 tickets
      ELSE floor(random() * 5)::int                        -- 0-5 tickets
    END;

    FOR v_j IN 1..v_sold_count LOOP
      -- Pick a random buyer
      v_user_id := v_user_ids[floor(random() * v_user_count + 1)::int];

      -- Trending events: sales clustered in last 48h
      -- Others: spread over last 30 days
      v_days_ago := CASE
        WHEN v_i <= 3 THEN floor(random() * 3)::int  -- 0-2 days ago
        ELSE floor(random() * 30)::int                -- 0-30 days ago
      END;

      INSERT INTO tickets (
        event_id,
        ticket_number,
        owner_email,
        price_paid_cents,
        status,
        sold_by,
        sold_at
      ) VALUES (
        v_event_id,
        'DSEED-' || gen_random_uuid()::text,
        'seed_' || v_j || '@test.local',
        COALESCE(
          (SELECT price_in_cents FROM events WHERE id = v_event_id),
          floor(random() * 10000 + 500)::int
        ),
        'valid',
        v_user_id,
        now() - (v_days_ago || ' days')::interval
          + (random() * interval '20 hours')
      )
      ON CONFLICT (ticket_number) DO NOTHING;
    END LOOP;
  END LOOP;

  RAISE NOTICE 'Tickets seeded.';

  -- ── 4. Seed payments (for price-match personalization) ────
  -- Each user gets a handful of completed payments at varied prices
  -- so the price_match signal has data to work with.

  FOR v_j IN 1..v_user_count LOOP
    v_user_id := v_user_ids[v_j];

    -- 2-6 past payments per user at varied price points
    FOR v_i IN 1..LEAST(2 + floor(random() * 5)::int, v_event_count) LOOP
      v_event_id := v_event_ids[v_i];

      INSERT INTO payments (
        user_id,
        event_id,
        amount_cents,
        platform_fee_cents,
        status,
        type,
        created_at
      ) VALUES (
        v_user_id,
        v_event_id,
        -- Price cluster: some users buy cheap, some expensive
        CASE
          WHEN v_j <= 8 THEN 1500 + floor(random() * 3000)::int   -- $15-45 buyers
          WHEN v_j <= 16 THEN 5000 + floor(random() * 10000)::int -- $50-150 buyers
          ELSE 500 + floor(random() * 2000)::int                  -- $5-25 buyers
        END,
        250,
        'completed',
        'primary_purchase',
        now() - ((floor(random() * 60)::int) || ' days')::interval
      )
      ON CONFLICT DO NOTHING;
    END LOOP;
  END LOOP;

  RAISE NOTICE 'Payments seeded.';

  -- ── 5. Seed user_tag_affinity ─────────────────────────────
  -- Give users affinity toward specific tag clusters so the
  -- personalization layer produces differentiated results.

  FOR v_j IN 1..v_user_count LOOP
    v_user_id := v_user_ids[v_j];

    -- Assign each user to a "taste cluster"
    -- Cluster 1 (users 1-8): music/nightlife fans
    -- Cluster 2 (users 9-16): tech/business fans
    -- Cluster 3 (users 17+): food/arts/outdoors fans

    IF v_j <= 8 THEN
      v_tags := ARRAY['music', 'nightlife', 'concert', 'festival', 'dj'];
    ELSIF v_j <= 16 THEN
      v_tags := ARRAY['technology', 'business', 'startup', 'conference', 'networking'];
    ELSE
      v_tags := ARRAY['food', 'art', 'outdoor', 'wellness', 'community'];
    END IF;

    FOREACH v_tag IN ARRAY v_tags LOOP
      INSERT INTO user_tag_affinity (user_id, tag, affinity_score, last_interaction)
      VALUES (
        v_user_id,
        v_tag,
        0.3 + random() * 2.0,  -- 0.3 to 2.3
        now() - ((floor(random() * 14)::int) || ' days')::interval
      )
      ON CONFLICT (user_id, tag) DO UPDATE SET
        affinity_score = EXCLUDED.affinity_score,
        last_interaction = EXCLUDED.last_interaction;
    END LOOP;
  END LOOP;

  RAISE NOTICE 'Tag affinity seeded.';

  -- ── 6. Refresh caches ─────────────────────────────────────
  -- Rebuild engagement cache from the new views
  PERFORM refresh_engagement_cache();

  -- Compute discovery scores
  PERFORM refresh_event_scores();

  RAISE NOTICE '────────────────────────────────────────────────';
  RAISE NOTICE 'Discovery seed complete!';
  RAISE NOTICE '';
  RAISE NOTICE 'Verify:';
  RAISE NOTICE '  SELECT * FROM event_scores ORDER BY composite_score DESC LIMIT 10;';
  RAISE NOTICE '  SELECT * FROM get_personalized_feed(NULL, NULL, NULL, 0, 10);';
  RAISE NOTICE '  SELECT * FROM user_tag_affinity LIMIT 20;';
  RAISE NOTICE '  SELECT * FROM discovery_weights;';
END;
$$;
