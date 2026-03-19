-- ============================================================
-- Event Discovery Algorithm
-- ============================================================
-- Weighted scoring system for event feed ranking.
-- Layer 1: Pre-computed event scores (materialized view, refreshed every 15 min)
-- Layer 2: Per-request personalization (SQL function at query time)
-- Admin tuning dashboard for weight adjustment + preview.

-- ── discovery_weights ──────────────────────────────────────
-- Tunable algorithm weights. Editable via admin dashboard.

CREATE TABLE discovery_weights (
  key TEXT PRIMARY KEY,
  weight FLOAT NOT NULL DEFAULT 0.0
    CHECK (weight >= 0.0 AND weight <= 1.0),
  description TEXT,
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE discovery_weights IS 'Tunable weights for the event discovery scoring algorithm';

ALTER TABLE discovery_weights ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read discovery weights"
  ON discovery_weights FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Service role full access on discovery_weights"
  ON discovery_weights FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Seed default weights
INSERT INTO discovery_weights (key, weight, description) VALUES
  ('popularity',        0.25, 'Bayesian-smoothed view count (7d)'),
  ('velocity',          0.20, 'Ticket sales velocity (48h)'),
  ('engagement',        0.20, 'View-to-purchase conversion rate'),
  ('recency',           0.15, 'How recently the event was created'),
  ('urgency',           0.10, 'Sell-through percentage (tickets sold / max)'),
  ('organizer_quality', 0.10, 'Organizer verification and reputation'),
  ('proximity',         0.30, 'Distance from user location (personalization layer)'),
  ('tag_affinity',      0.25, 'User tag preference match (personalization layer)'),
  ('price_match',       0.10, 'Price range match to user history (personalization layer)');

-- ── discovery_weight_history ───────────────────────────────
-- Audit trail for weight changes.

CREATE TABLE discovery_weight_history (
  id BIGSERIAL PRIMARY KEY,
  key TEXT NOT NULL,
  old_weight FLOAT NOT NULL,
  new_weight FLOAT NOT NULL,
  changed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE discovery_weight_history IS 'Audit log of discovery weight changes';

ALTER TABLE discovery_weight_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read weight history"
  ON discovery_weight_history FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Service role full access on weight history"
  ON discovery_weight_history FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ── user_tag_affinity ──────────────────────────────────────
-- Per-user tag preferences built from interactions.

CREATE TABLE user_tag_affinity (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tag TEXT NOT NULL,
  affinity_score FLOAT NOT NULL DEFAULT 0.0,
  last_interaction TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, tag)
);

COMMENT ON TABLE user_tag_affinity IS 'Per-user tag affinity scores for personalized feed ranking';

CREATE INDEX idx_uta_user ON user_tag_affinity (user_id);

ALTER TABLE user_tag_affinity ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own tag affinity"
  ON user_tag_affinity FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Users can upsert own tag affinity"
  ON user_tag_affinity FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own tag affinity"
  ON user_tag_affinity FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Service role full access on user_tag_affinity"
  ON user_tag_affinity FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ── event_scores ───────────────────────────────────────────
-- Pre-computed Layer 1 scores. Refreshed by cron.
-- Using a regular table (not materialized view) for flexibility
-- with incremental updates and index support.

CREATE TABLE event_scores (
  event_id UUID PRIMARY KEY REFERENCES events(id) ON DELETE CASCADE,
  popularity_score FLOAT NOT NULL DEFAULT 0.0,
  velocity_score FLOAT NOT NULL DEFAULT 0.0,
  engagement_score FLOAT NOT NULL DEFAULT 0.0,
  recency_score FLOAT NOT NULL DEFAULT 0.0,
  urgency_score FLOAT NOT NULL DEFAULT 0.0,
  organizer_quality_score FLOAT NOT NULL DEFAULT 0.0,
  composite_score FLOAT NOT NULL DEFAULT 0.0,
  trending_rank INT,
  refreshed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE event_scores IS 'Pre-computed event scores for discovery feed ranking';

CREATE INDEX idx_es_composite ON event_scores (composite_score DESC);
CREATE INDEX idx_es_trending ON event_scores (trending_rank ASC NULLS LAST);

ALTER TABLE event_scores ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read event scores"
  ON event_scores FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Service role full access on event_scores"
  ON event_scores FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ── refresh_event_scores() ─────────────────────────────────
-- Recomputes all event scores using current weights.
-- Called by pg_cron every 15 minutes.

CREATE OR REPLACE FUNCTION refresh_event_scores()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  w_pop FLOAT;
  w_vel FLOAT;
  w_eng FLOAT;
  w_rec FLOAT;
  w_urg FLOAT;
  w_org FLOAT;
  v_max_velocity FLOAT;
BEGIN
  -- Load current weights
  SELECT COALESCE(weight, 0.25) INTO w_pop FROM discovery_weights WHERE key = 'popularity';
  SELECT COALESCE(weight, 0.20) INTO w_vel FROM discovery_weights WHERE key = 'velocity';
  SELECT COALESCE(weight, 0.20) INTO w_eng FROM discovery_weights WHERE key = 'engagement';
  SELECT COALESCE(weight, 0.15) INTO w_rec FROM discovery_weights WHERE key = 'recency';
  SELECT COALESCE(weight, 0.10) INTO w_urg FROM discovery_weights WHERE key = 'urgency';
  SELECT COALESCE(weight, 0.10) INTO w_org FROM discovery_weights WHERE key = 'organizer_quality';

  -- Get max velocity for normalization
  SELECT COALESCE(MAX(cnt), 1) INTO v_max_velocity
  FROM (
    SELECT COUNT(*) AS cnt
    FROM tickets
    WHERE sold_at >= now() - interval '48 hours'
      AND status NOT IN ('cancelled', 'refunded')
    GROUP BY event_id
  ) sub;

  -- Upsert scores for all active upcoming events
  INSERT INTO event_scores (
    event_id,
    popularity_score,
    velocity_score,
    engagement_score,
    recency_score,
    urgency_score,
    organizer_quality_score,
    composite_score,
    refreshed_at
  )
  SELECT
    e.id,
    -- Popularity: Bayesian smoothed views (7d). n/(n+k) where k=50
    COALESCE(ev_stats.views_7d::float / (ev_stats.views_7d + 50), 0) AS popularity,
    -- Velocity: sales in last 48h normalized by max
    COALESCE(vel_stats.sales_48h::float / v_max_velocity, 0) AS velocity,
    -- Engagement: conversion rate (purchasers / unique viewers), Wilson lower-bound simplified
    CASE
      WHEN COALESCE(ev_stats.unique_viewers, 0) > 0
      THEN LEAST(ev_stats.purchasers::float / ev_stats.unique_viewers, 1.0)
      ELSE 0
    END AS engagement,
    -- Recency: 1 / (1 + days_since_created * 0.1)
    1.0 / (1.0 + EXTRACT(EPOCH FROM (now() - e.created_at)) / 86400.0 * 0.1) AS recency,
    -- Urgency: sell-through percentage
    CASE
      WHEN COALESCE(e.max_tickets, 0) > 0
      THEN LEAST(COALESCE(ticket_stats.sold_count, 0)::float / e.max_tickets, 1.0)
      ELSE 0
    END AS urgency,
    -- Organizer quality: based on verification status
    CASE
      WHEN p.identity_verification_status = 'verified' THEN 1.0
      WHEN p.identity_verification_status = 'pending' THEN 0.7
      WHEN p.identity_verification_status IS NULL THEN 0.5
      ELSE 0.2  -- 'failed' or other
    END AS organizer_quality,
    -- Composite score
    (
      w_pop * COALESCE(ev_stats.views_7d::float / (ev_stats.views_7d + 50), 0)
      + w_vel * COALESCE(vel_stats.sales_48h::float / v_max_velocity, 0)
      + w_eng * CASE
          WHEN COALESCE(ev_stats.unique_viewers, 0) > 0
          THEN LEAST(ev_stats.purchasers::float / ev_stats.unique_viewers, 1.0)
          ELSE 0
        END
      + w_rec * (1.0 / (1.0 + EXTRACT(EPOCH FROM (now() - e.created_at)) / 86400.0 * 0.1))
      + w_urg * CASE
          WHEN COALESCE(e.max_tickets, 0) > 0
          THEN LEAST(COALESCE(ticket_stats.sold_count, 0)::float / e.max_tickets, 1.0)
          ELSE 0
        END
      + w_org * CASE
          WHEN p.identity_verification_status = 'verified' THEN 1.0
          WHEN p.identity_verification_status = 'pending' THEN 0.7
          WHEN p.identity_verification_status IS NULL THEN 0.5
          ELSE 0.2
        END
    ) AS composite,
    now()
  FROM events e
  LEFT JOIN profiles p ON p.id = e.organizer_id
  -- View stats from engagement cache (7d + all-time unique viewers/purchasers)
  LEFT JOIN LATERAL (
    SELECT
      COALESCE(SUM(CASE WHEN aed.day >= (now() - interval '7 days')::date THEN aed.total_views ELSE 0 END), 0) AS views_7d,
      COALESCE(SUM(aed.unique_viewers), 0) AS unique_viewers,
      COALESCE(SUM(aed.purchasers), 0) AS purchasers
    FROM analytics_engagement_daily aed
    WHERE aed.event_id = e.id
  ) ev_stats ON true
  -- Velocity: ticket sales in last 48h
  LEFT JOIN LATERAL (
    SELECT COUNT(*) AS sales_48h
    FROM tickets t
    WHERE t.event_id = e.id
      AND t.sold_at >= now() - interval '48 hours'
      AND t.status NOT IN ('cancelled', 'refunded')
  ) vel_stats ON true
  -- Total sold tickets
  LEFT JOIN LATERAL (
    SELECT COUNT(*) AS sold_count
    FROM tickets t
    WHERE t.event_id = e.id
      AND t.status NOT IN ('cancelled', 'refunded')
  ) ticket_stats ON true
  WHERE e.deleted_at IS NULL
    AND e.status = 'active'
    AND e.date >= now()
    AND e.is_private = false
  ON CONFLICT (event_id) DO UPDATE SET
    popularity_score = EXCLUDED.popularity_score,
    velocity_score = EXCLUDED.velocity_score,
    engagement_score = EXCLUDED.engagement_score,
    recency_score = EXCLUDED.recency_score,
    urgency_score = EXCLUDED.urgency_score,
    organizer_quality_score = EXCLUDED.organizer_quality_score,
    composite_score = EXCLUDED.composite_score,
    refreshed_at = EXCLUDED.refreshed_at;

  -- Remove scores for events that are no longer active/upcoming
  DELETE FROM event_scores
  WHERE event_id NOT IN (
    SELECT id FROM events
    WHERE deleted_at IS NULL
      AND status = 'active'
      AND date >= now()
      AND is_private = false
  );

  -- Update trending ranks
  WITH ranked AS (
    SELECT event_id, ROW_NUMBER() OVER (ORDER BY composite_score DESC) AS rank
    FROM event_scores
  )
  UPDATE event_scores es
  SET trending_rank = r.rank
  FROM ranked r
  WHERE es.event_id = r.event_id;

  -- Update refresh meta
  INSERT INTO analytics_cache_meta (key, refreshed_at)
  VALUES ('event_scores_last_refresh', now())
  ON CONFLICT (key) DO UPDATE SET refreshed_at = now();
END;
$$;

GRANT EXECUTE ON FUNCTION refresh_event_scores() TO service_role;

-- ── get_personalized_feed() ────────────────────────────────
-- Returns scored + personalized events for a user.
-- Handles cold-start (no user / no history) by falling back to composite_score.

CREATE OR REPLACE FUNCTION get_personalized_feed(
  p_user_id UUID DEFAULT NULL,
  p_lat FLOAT DEFAULT NULL,
  p_lng FLOAT DEFAULT NULL,
  p_page INT DEFAULT 0,
  p_page_size INT DEFAULT 20
)
RETURNS TABLE (
  event_id UUID,
  composite_score FLOAT,
  popularity_score FLOAT,
  velocity_score FLOAT,
  engagement_score FLOAT,
  recency_score FLOAT,
  urgency_score FLOAT,
  organizer_quality_score FLOAT,
  proximity_boost FLOAT,
  affinity_boost FLOAT,
  price_boost FLOAT,
  time_decay FLOAT,
  final_score FLOAT,
  trending_rank INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  w_prox FLOAT;
  w_aff FLOAT;
  w_price FLOAT;
  v_user_avg_price FLOAT;
  v_offset INT;
BEGIN
  v_offset := p_page * p_page_size;

  -- Load personalization weights
  SELECT COALESCE(weight, 0.30) INTO w_prox FROM discovery_weights WHERE key = 'proximity';
  SELECT COALESCE(weight, 0.25) INTO w_aff FROM discovery_weights WHERE key = 'tag_affinity';
  SELECT COALESCE(weight, 0.10) INTO w_price FROM discovery_weights WHERE key = 'price_match';

  -- User average ticket price (for price matching)
  IF p_user_id IS NOT NULL THEN
    SELECT COALESCE(AVG(pay.amount_cents), 0)
    INTO v_user_avg_price
    FROM payments pay
    WHERE pay.user_id = p_user_id
      AND pay.status = 'completed';
  ELSE
    v_user_avg_price := 0;
  END IF;

  RETURN QUERY
  SELECT
    es.event_id,
    es.composite_score,
    es.popularity_score,
    es.velocity_score,
    es.engagement_score,
    es.recency_score,
    es.urgency_score,
    es.organizer_quality_score,
    -- Proximity boost: 1 / (1 + distance_km * 0.02)
    CASE
      WHEN p_lat IS NOT NULL AND p_lng IS NOT NULL
           AND e.latitude IS NOT NULL AND e.longitude IS NOT NULL
      THEN 1.0 / (1.0 + (
        -- Haversine approximation in km
        111.0 * SQRT(
          POW(e.latitude - p_lat, 2) +
          POW((e.longitude - p_lng) * COS(RADIANS((e.latitude + p_lat) / 2.0)), 2)
        )
      ) * 0.02)
      ELSE 0.0
    END AS proximity_boost,
    -- Tag affinity boost: sum of user affinity for event's tags
    CASE
      WHEN p_user_id IS NOT NULL AND e.tags IS NOT NULL AND array_length(e.tags, 1) > 0
      THEN COALESCE((
        SELECT LEAST(SUM(uta.affinity_score), 1.0)
        FROM user_tag_affinity uta
        WHERE uta.user_id = p_user_id
          AND uta.tag = ANY(e.tags)
      ), 0.0)
      ELSE 0.0
    END AS affinity_boost,
    -- Price match boost: 1 - |event_price - user_avg| / max(both, 1)
    CASE
      WHEN p_user_id IS NOT NULL AND v_user_avg_price > 0 AND e.price_in_cents IS NOT NULL
      THEN GREATEST(
        1.0 - ABS(e.price_in_cents - v_user_avg_price) / GREATEST(v_user_avg_price, e.price_in_cents::float, 1.0),
        0.0
      )
      ELSE 0.0
    END AS price_boost,
    -- Time decay: e^(-0.03 * days_until_event), cast to float (EXP returns numeric)
    EXP(-0.03 * GREATEST(EXTRACT(EPOCH FROM (e.date - now())) / 86400.0, 0))::float AS time_decay,
    -- Final score = composite * (1 + personalization boosts) * time_decay
    (
      es.composite_score
      * (1.0
        + w_prox * CASE
            WHEN p_lat IS NOT NULL AND p_lng IS NOT NULL
                 AND e.latitude IS NOT NULL AND e.longitude IS NOT NULL
            THEN 1.0 / (1.0 + (
              111.0 * SQRT(
                POW(e.latitude - p_lat, 2) +
                POW((e.longitude - p_lng) * COS(RADIANS((e.latitude + p_lat) / 2.0)), 2)
              )
            ) * 0.02)
            ELSE 0.0
          END
        + w_aff * CASE
            WHEN p_user_id IS NOT NULL AND e.tags IS NOT NULL AND array_length(e.tags, 1) > 0
            THEN COALESCE((
              SELECT LEAST(SUM(uta.affinity_score), 1.0)
              FROM user_tag_affinity uta
              WHERE uta.user_id = p_user_id
                AND uta.tag = ANY(e.tags)
            ), 0.0)
            ELSE 0.0
          END
        + w_price * CASE
            WHEN p_user_id IS NOT NULL AND v_user_avg_price > 0 AND e.price_in_cents IS NOT NULL
            THEN GREATEST(
              1.0 - ABS(e.price_in_cents - v_user_avg_price) / GREATEST(v_user_avg_price, e.price_in_cents::float, 1.0),
              0.0
            )
            ELSE 0.0
          END
      )
      * EXP(-0.03 * GREATEST(EXTRACT(EPOCH FROM (e.date - now())) / 86400.0, 0))
    )::float AS final_score,
    es.trending_rank
  FROM event_scores es
  JOIN events e ON e.id = es.event_id
  WHERE e.deleted_at IS NULL
    AND e.status = 'active'
    AND e.date >= now()
    AND e.is_private = false
  ORDER BY final_score DESC
  LIMIT p_page_size + 1
  OFFSET v_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION get_personalized_feed(UUID, FLOAT, FLOAT, INT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_personalized_feed(UUID, FLOAT, FLOAT, INT, INT) TO service_role;

-- ── preview_feed_with_weights() ────────────────────────────
-- Admin preview: recalculates scores with hypothetical weights.
-- Read-only — does NOT persist anything.

CREATE OR REPLACE FUNCTION preview_feed_with_weights(
  p_weights JSONB,
  p_limit INT DEFAULT 10
)
RETURNS TABLE (
  event_id UUID,
  event_title TEXT,
  popularity_score FLOAT,
  velocity_score FLOAT,
  engagement_score FLOAT,
  recency_score FLOAT,
  urgency_score FLOAT,
  organizer_quality_score FLOAT,
  preview_composite FLOAT,
  current_composite FLOAT,
  current_rank INT,
  preview_rank INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  w_pop FLOAT;
  w_vel FLOAT;
  w_eng FLOAT;
  w_rec FLOAT;
  w_urg FLOAT;
  w_org FLOAT;
BEGIN
  -- Extract weights from JSONB (fall back to current DB weights)
  w_pop := COALESCE((p_weights->>'popularity')::float,
    (SELECT weight FROM discovery_weights WHERE key = 'popularity'), 0.25);
  w_vel := COALESCE((p_weights->>'velocity')::float,
    (SELECT weight FROM discovery_weights WHERE key = 'velocity'), 0.20);
  w_eng := COALESCE((p_weights->>'engagement')::float,
    (SELECT weight FROM discovery_weights WHERE key = 'engagement'), 0.20);
  w_rec := COALESCE((p_weights->>'recency')::float,
    (SELECT weight FROM discovery_weights WHERE key = 'recency'), 0.15);
  w_urg := COALESCE((p_weights->>'urgency')::float,
    (SELECT weight FROM discovery_weights WHERE key = 'urgency'), 0.10);
  w_org := COALESCE((p_weights->>'organizer_quality')::float,
    (SELECT weight FROM discovery_weights WHERE key = 'organizer_quality'), 0.10);

  RETURN QUERY
  WITH preview AS (
    SELECT
      es.event_id,
      e.title AS event_title,
      es.popularity_score,
      es.velocity_score,
      es.engagement_score,
      es.recency_score,
      es.urgency_score,
      es.organizer_quality_score,
      (
        w_pop * es.popularity_score
        + w_vel * es.velocity_score
        + w_eng * es.engagement_score
        + w_rec * es.recency_score
        + w_urg * es.urgency_score
        + w_org * es.organizer_quality_score
      ) AS preview_composite,
      es.composite_score AS current_composite,
      es.trending_rank AS current_rank
    FROM event_scores es
    JOIN events e ON e.id = es.event_id
    WHERE e.deleted_at IS NULL
      AND e.status = 'active'
      AND e.date >= now()
  )
  SELECT
    p.event_id,
    p.event_title,
    p.popularity_score,
    p.velocity_score,
    p.engagement_score,
    p.recency_score,
    p.urgency_score,
    p.organizer_quality_score,
    p.preview_composite,
    p.current_composite,
    p.current_rank,
    ROW_NUMBER() OVER (ORDER BY p.preview_composite DESC)::int AS preview_rank
  FROM preview p
  ORDER BY p.preview_composite DESC
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION preview_feed_with_weights(JSONB, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION preview_feed_with_weights(JSONB, INT) TO service_role;

-- ── update_user_tag_affinity() ─────────────────────────────
-- Called on user interactions to build tag preferences.
-- view=+0.1, purchase=+1.0, share=+0.3. Decays existing score * 0.95.

CREATE OR REPLACE FUNCTION update_user_tag_affinity(
  p_user_id UUID,
  p_tag TEXT,
  p_interaction_type TEXT  -- 'view', 'purchase', 'share'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_increment FLOAT;
BEGIN
  v_increment := CASE p_interaction_type
    WHEN 'purchase' THEN 1.0
    WHEN 'share' THEN 0.3
    WHEN 'view' THEN 0.1
    ELSE 0.05
  END;

  INSERT INTO user_tag_affinity (user_id, tag, affinity_score, last_interaction)
  VALUES (p_user_id, p_tag, v_increment, now())
  ON CONFLICT (user_id, tag) DO UPDATE SET
    affinity_score = LEAST(
      user_tag_affinity.affinity_score * 0.95 + v_increment,
      5.0  -- cap at 5.0 to prevent runaway
    ),
    last_interaction = now();
END;
$$;

GRANT EXECUTE ON FUNCTION update_user_tag_affinity(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION update_user_tag_affinity(UUID, TEXT, TEXT) TO service_role;

-- ── update_discovery_weight() ──────────────────────────────
-- Updates a single weight and logs to history. Admin use.

CREATE OR REPLACE FUNCTION update_discovery_weight(
  p_key TEXT,
  p_new_weight FLOAT,
  p_changed_by UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old_weight FLOAT;
BEGIN
  -- Get current weight
  SELECT weight INTO v_old_weight
  FROM discovery_weights
  WHERE key = p_key;

  IF v_old_weight IS NULL THEN
    RAISE EXCEPTION 'Unknown weight key: %', p_key;
  END IF;

  -- Log change
  INSERT INTO discovery_weight_history (key, old_weight, new_weight, changed_by)
  VALUES (p_key, v_old_weight, p_new_weight, p_changed_by);

  -- Update weight
  UPDATE discovery_weights
  SET weight = p_new_weight,
      updated_by = p_changed_by,
      updated_at = now()
  WHERE key = p_key;
END;
$$;

GRANT EXECUTE ON FUNCTION update_discovery_weight(TEXT, FLOAT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION update_discovery_weight(TEXT, FLOAT, UUID) TO service_role;

-- ── pg_cron: refresh event scores every 15 minutes ─────────
SELECT cron.schedule(
  'refresh-event-scores',
  '*/15 * * * *',
  $$SELECT refresh_event_scores()$$
);

-- ── Initial score computation ──────────────────────────────
SELECT refresh_event_scores();
