-- ============================================================
-- Engagement Tracking System
-- ============================================================
-- Raw event view telemetry + pre-computed daily cache for
-- platform-wide analytics. Per-event queries run live against
-- indexed event_views; platform-wide queries read the cache.

-- ── event_views ──────────────────────────────────────────────
-- Raw view telemetry. One row per viewer per event per hour
-- (hourly dedup via unique index).

CREATE TABLE event_views (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  viewer_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  viewed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  source TEXT NOT NULL DEFAULT 'direct'
    CHECK (source IN ('home_feed','search','tag_browse','direct','shared','notification'))
);

COMMENT ON TABLE event_views IS 'Raw event view telemetry for engagement analytics';
COMMENT ON COLUMN event_views.source IS 'Where the user navigated from to view the event';

-- Per-event time-range lookups
CREATE INDEX idx_ev_event_viewed ON event_views (event_id, viewed_at DESC);

-- Unique viewer + conversion joins
CREATE INDEX idx_ev_viewer_event ON event_views (viewer_id, event_id)
  WHERE viewer_id IS NOT NULL;

-- Platform-wide time scans
CREATE INDEX idx_ev_viewed_at_brin ON event_views
  USING BRIN (viewed_at);

-- Immutable helper for hourly dedup index
-- date_trunc on timestamptz is STABLE (tz-dependent), so we need an
-- IMMUTABLE wrapper that truncates in UTC explicitly.
CREATE OR REPLACE FUNCTION trunc_hour_utc(ts TIMESTAMPTZ)
RETURNS TIMESTAMP
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT date_trunc('hour', ts AT TIME ZONE 'UTC')
$$;

-- Hourly dedup: one view per user per event per hour (UTC)
CREATE UNIQUE INDEX idx_ev_hourly_dedup
  ON event_views (viewer_id, event_id, trunc_hour_utc(viewed_at))
  WHERE viewer_id IS NOT NULL;

-- ── RLS for event_views ──────────────────────────────────────

ALTER TABLE event_views ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert own views"
  ON event_views FOR INSERT
  TO authenticated
  WITH CHECK (viewer_id = auth.uid());

CREATE POLICY "Users can read own view history"
  ON event_views FOR SELECT
  TO authenticated
  USING (viewer_id = auth.uid());

CREATE POLICY "Service role full access on event_views"
  ON event_views FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ── analytics_engagement_daily ───────────────────────────────
-- Pre-computed daily cache. Refreshed by cron every 6 hours.

CREATE TABLE analytics_engagement_daily (
  id BIGSERIAL PRIMARY KEY,
  day DATE NOT NULL,
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  total_views INT NOT NULL DEFAULT 0,
  unique_viewers INT NOT NULL DEFAULT 0,
  purchasers INT NOT NULL DEFAULT 0,
  UNIQUE (day, event_id)
);

COMMENT ON TABLE analytics_engagement_daily IS 'Pre-computed daily engagement cache for platform-wide queries';

ALTER TABLE analytics_engagement_daily ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read engagement cache"
  ON analytics_engagement_daily FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Service role full access on engagement cache"
  ON analytics_engagement_daily FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Add engagement_last_refresh key to existing cache meta table
INSERT INTO analytics_cache_meta (key) VALUES ('engagement_last_refresh')
  ON CONFLICT (key) DO NOTHING;

-- ── get_event_engagement(p_event_id) ─────────────────────────
-- Live per-event engagement query. Returns JSONB with views,
-- conversion rate, viewer spending habits, daily breakdown, sources.

CREATE OR REPLACE FUNCTION get_event_engagement(p_event_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result JSONB;
  v_total_views BIGINT;
  v_unique_viewers BIGINT;
  v_views_7d BIGINT;
  v_views_30d BIGINT;
  v_unique_purchasers BIGINT;
  v_conversion_rate NUMERIC(5,2);
  v_viewer_avg_price NUMERIC;
  v_viewer_avg_monthly NUMERIC;
  v_daily_views JSONB;
  v_source_breakdown JSONB;
BEGIN
  -- Total & unique views
  SELECT COUNT(*), COUNT(DISTINCT viewer_id)
  INTO v_total_views, v_unique_viewers
  FROM event_views
  WHERE event_id = p_event_id;

  -- Views in last 7 days
  SELECT COUNT(*)
  INTO v_views_7d
  FROM event_views
  WHERE event_id = p_event_id
    AND viewed_at >= now() - interval '7 days';

  -- Views in last 30 days
  SELECT COUNT(*)
  INTO v_views_30d
  FROM event_views
  WHERE event_id = p_event_id
    AND viewed_at >= now() - interval '30 days';

  -- Unique purchasers (viewers who also bought a ticket for THIS event)
  SELECT COUNT(DISTINCT t.sold_by)
  INTO v_unique_purchasers
  FROM tickets t
  WHERE t.event_id = p_event_id
    AND t.status NOT IN ('cancelled', 'refunded')
    AND t.sold_by IN (
      SELECT DISTINCT viewer_id FROM event_views
      WHERE event_id = p_event_id AND viewer_id IS NOT NULL
    );

  -- Conversion rate
  v_conversion_rate := CASE
    WHEN v_unique_viewers > 0
    THEN ROUND((v_unique_purchasers::numeric / v_unique_viewers * 100), 2)
    ELSE 0
  END;

  -- Viewer average ticket price (across ALL platform purchases by these viewers)
  SELECT COALESCE(AVG(p.amount_cents), 0)
  INTO v_viewer_avg_price
  FROM payments p
  WHERE p.user_id IN (
    SELECT DISTINCT viewer_id FROM event_views
    WHERE event_id = p_event_id AND viewer_id IS NOT NULL
  )
  AND p.status = 'completed';

  -- Viewer average monthly purchases
  SELECT COALESCE(AVG(monthly_count), 0)
  INTO v_viewer_avg_monthly
  FROM (
    SELECT
      t.sold_by,
      COUNT(t.id)::numeric / GREATEST(
        EXTRACT(EPOCH FROM (now() - MIN(t.sold_at))) / (30 * 86400),
        1
      ) AS monthly_count
    FROM tickets t
    WHERE t.sold_by IN (
      SELECT DISTINCT viewer_id FROM event_views
      WHERE event_id = p_event_id AND viewer_id IS NOT NULL
    )
    AND t.status NOT IN ('cancelled', 'refunded')
    GROUP BY t.sold_by
  ) sub;

  -- Daily views (last 30 days)
  SELECT COALESCE(jsonb_agg(row_to_json(sub)::jsonb ORDER BY sub.date), '[]'::jsonb)
  INTO v_daily_views
  FROM (
    SELECT
      viewed_at::date AS date,
      COUNT(*) AS views
    FROM event_views
    WHERE event_id = p_event_id
      AND viewed_at >= now() - interval '30 days'
    GROUP BY viewed_at::date
    ORDER BY viewed_at::date
  ) sub;

  -- Source breakdown
  SELECT COALESCE(jsonb_agg(row_to_json(sub)::jsonb ORDER BY sub.count DESC), '[]'::jsonb)
  INTO v_source_breakdown
  FROM (
    SELECT source, COUNT(*) AS count
    FROM event_views
    WHERE event_id = p_event_id
    GROUP BY source
    ORDER BY count DESC
  ) sub;

  result := jsonb_build_object(
    'total_views', v_total_views,
    'unique_viewers', v_unique_viewers,
    'views_7d', v_views_7d,
    'views_30d', v_views_30d,
    'conversion_rate', v_conversion_rate,
    'unique_purchasers', v_unique_purchasers,
    'viewer_avg_ticket_price_cents', ROUND(v_viewer_avg_price),
    'viewer_avg_monthly_purchases', ROUND(v_viewer_avg_monthly, 1),
    'daily_views', v_daily_views,
    'source_breakdown', v_source_breakdown
  );

  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_event_engagement(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_event_engagement(UUID) TO service_role;

-- ── get_platform_engagement_summary(p_city) ──────────────────
-- Reads from cache table for fast platform-wide queries.
-- Optional city filter.

CREATE OR REPLACE FUNCTION get_platform_engagement_summary(p_city TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result JSONB;
  v_total_views_30d BIGINT;
  v_unique_viewers_30d BIGINT;
  v_avg_conversion NUMERIC(5,2);
  v_weekly_views JSONB;
  v_top_events JSONB;
  v_top_tags JSONB;
  v_city_breakdown JSONB;
BEGIN
  -- Total views & unique viewers (30d) from cache
  SELECT
    COALESCE(SUM(total_views), 0),
    COALESCE(SUM(unique_viewers), 0)
  INTO v_total_views_30d, v_unique_viewers_30d
  FROM analytics_engagement_daily aed
  JOIN events e ON e.id = aed.event_id
  WHERE aed.day >= (now() - interval '30 days')::date
    AND (p_city IS NULL OR e.city = p_city);

  -- Average conversion rate (30d)
  SELECT COALESCE(
    ROUND(
      SUM(purchasers)::numeric / NULLIF(SUM(unique_viewers), 0) * 100,
      1
    ), 0
  )
  INTO v_avg_conversion
  FROM analytics_engagement_daily aed
  JOIN events e ON e.id = aed.event_id
  WHERE aed.day >= (now() - interval '30 days')::date
    AND (p_city IS NULL OR e.city = p_city);

  -- Weekly views (12 weeks)
  SELECT COALESCE(jsonb_agg(row_to_json(sub)::jsonb ORDER BY sub.week_start), '[]'::jsonb)
  INTO v_weekly_views
  FROM (
    SELECT
      date_trunc('week', aed.day)::date AS week_start,
      SUM(aed.total_views) AS views
    FROM analytics_engagement_daily aed
    JOIN events e ON e.id = aed.event_id
    WHERE aed.day >= (now() - interval '84 days')::date
      AND (p_city IS NULL OR e.city = p_city)
    GROUP BY date_trunc('week', aed.day)::date
    ORDER BY week_start
  ) sub;

  -- Top events (top 10 by views in 30d)
  SELECT COALESCE(jsonb_agg(row_to_json(sub)::jsonb ORDER BY sub.total_views DESC), '[]'::jsonb)
  INTO v_top_events
  FROM (
    SELECT
      e.id AS event_id,
      e.title,
      SUM(aed.total_views) AS total_views,
      SUM(aed.unique_viewers) AS unique_viewers,
      CASE
        WHEN SUM(aed.unique_viewers) > 0
        THEN ROUND(SUM(aed.purchasers)::numeric / SUM(aed.unique_viewers) * 100, 1)
        ELSE 0
      END AS conversion_rate
    FROM analytics_engagement_daily aed
    JOIN events e ON e.id = aed.event_id
    WHERE aed.day >= (now() - interval '30 days')::date
      AND e.deleted_at IS NULL
      AND (p_city IS NULL OR e.city = p_city)
    GROUP BY e.id, e.title
    ORDER BY SUM(aed.total_views) DESC
    LIMIT 10
  ) sub;

  -- Top tags (top 10 by views in 30d)
  SELECT COALESCE(jsonb_agg(row_to_json(sub)::jsonb ORDER BY sub.views DESC), '[]'::jsonb)
  INTO v_top_tags
  FROM (
    SELECT
      t.tag_id AS tag,
      SUM(aed.total_views) AS views
    FROM analytics_engagement_daily aed
    JOIN events e ON e.id = aed.event_id
    CROSS JOIN LATERAL UNNEST(e.tags) AS t(tag_id)
    WHERE aed.day >= (now() - interval '30 days')::date
      AND e.deleted_at IS NULL
      AND e.tags IS NOT NULL
      AND (p_city IS NULL OR e.city = p_city)
    GROUP BY t.tag_id
    ORDER BY SUM(aed.total_views) DESC
    LIMIT 10
  ) sub;

  -- City breakdown (top 10)
  SELECT COALESCE(jsonb_agg(row_to_json(sub)::jsonb ORDER BY sub.views DESC), '[]'::jsonb)
  INTO v_city_breakdown
  FROM (
    SELECT
      e.city,
      SUM(aed.total_views) AS views
    FROM analytics_engagement_daily aed
    JOIN events e ON e.id = aed.event_id
    WHERE aed.day >= (now() - interval '30 days')::date
      AND e.deleted_at IS NULL
      AND e.city IS NOT NULL
      AND p_city IS NULL  -- Skip city breakdown when filtering by city
    GROUP BY e.city
    ORDER BY SUM(aed.total_views) DESC
    LIMIT 10
  ) sub;

  result := jsonb_build_object(
    'total_views_30d', v_total_views_30d,
    'total_unique_viewers_30d', v_unique_viewers_30d,
    'avg_conversion_rate', v_avg_conversion,
    'weekly_views', v_weekly_views,
    'top_events', v_top_events,
    'top_tags', v_top_tags,
    'city_breakdown', v_city_breakdown
  );

  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_platform_engagement_summary(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_platform_engagement_summary(TEXT) TO service_role;

-- ── refresh_engagement_cache() ───────────────────────────────
-- Upserts last 7 days of engagement data from event_views.
-- Deletes cache rows older than 90 days. Called by cron.

CREATE OR REPLACE FUNCTION refresh_engagement_cache()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Delete stale cache rows (older than 90 days)
  DELETE FROM analytics_engagement_daily
  WHERE day < (now() - interval '90 days')::date;

  -- Upsert last 7 days from event_views
  INSERT INTO analytics_engagement_daily (day, event_id, total_views, unique_viewers, purchasers)
  SELECT
    ev.viewed_at::date AS day,
    ev.event_id,
    COUNT(*) AS total_views,
    COUNT(DISTINCT ev.viewer_id) AS unique_viewers,
    COUNT(DISTINCT t.sold_by) AS purchasers
  FROM event_views ev
  LEFT JOIN tickets t
    ON t.event_id = ev.event_id
    AND t.sold_by = ev.viewer_id
    AND t.status NOT IN ('cancelled', 'refunded')
  WHERE ev.viewed_at >= (now() - interval '7 days')::date
  GROUP BY ev.viewed_at::date, ev.event_id
  ON CONFLICT (day, event_id) DO UPDATE SET
    total_views = EXCLUDED.total_views,
    unique_viewers = EXCLUDED.unique_viewers,
    purchasers = EXCLUDED.purchasers;

  -- Update refresh timestamp
  UPDATE analytics_cache_meta
  SET refreshed_at = now()
  WHERE key = 'engagement_last_refresh';
END;
$$;

GRANT EXECUTE ON FUNCTION refresh_engagement_cache() TO service_role;
