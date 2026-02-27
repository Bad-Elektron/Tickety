-- ============================================================
-- Pre-computed Analytics Cache Tables
-- ============================================================
-- Aggregated data from events + tickets for fast dashboard reads.
-- Populated by refresh_analytics_cache() called via cron every 6 hours.

-- ── analytics_tag_weekly ────────────────────────────────────
-- One row per (tag, week, city/country) combination.
-- city=NULL / country=NULL rows represent global (all locations).

CREATE TABLE analytics_tag_weekly (
  id BIGSERIAL PRIMARY KEY,
  tag_id TEXT NOT NULL,
  week_start DATE NOT NULL,
  city TEXT,
  country TEXT,
  event_count INT NOT NULL DEFAULT 0,
  avg_price_cents INT NOT NULL DEFAULT 0,
  total_tickets_sold INT NOT NULL DEFAULT 0,
  total_revenue_cents BIGINT NOT NULL DEFAULT 0,
  UNIQUE(tag_id, week_start, city, country)
);

CREATE INDEX idx_atw_tag_week ON analytics_tag_weekly (tag_id, week_start DESC);
CREATE INDEX idx_atw_week_city ON analytics_tag_weekly (week_start DESC, city);
CREATE INDEX idx_atw_tag_city ON analytics_tag_weekly (tag_id, city);

-- ── analytics_trending_tags ─────────────────────────────────
-- Current trending snapshot with week-over-week trend scores.

CREATE TABLE analytics_trending_tags (
  id BIGSERIAL PRIMARY KEY,
  tag_id TEXT NOT NULL,
  tag_label TEXT NOT NULL,
  city TEXT,
  country TEXT,
  current_week_count INT NOT NULL DEFAULT 0,
  prev_week_count INT NOT NULL DEFAULT 0,
  trend_score NUMERIC(6,2) NOT NULL DEFAULT 0,
  avg_price_cents INT NOT NULL DEFAULT 0,
  total_events_30d INT NOT NULL DEFAULT 0,
  UNIQUE(tag_id, city, country)
);

CREATE INDEX idx_att_trending ON analytics_trending_tags (trend_score DESC);
CREATE INDEX idx_att_city ON analytics_trending_tags (city, trend_score DESC);

-- ── analytics_cache_meta ────────────────────────────────────
-- Tracks when the cache was last refreshed.

CREATE TABLE analytics_cache_meta (
  key TEXT PRIMARY KEY,
  refreshed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO analytics_cache_meta (key) VALUES ('last_refresh');

-- ── RLS Policies ────────────────────────────────────────────
-- Read-only for authenticated users. Writes only via SECURITY DEFINER function.

ALTER TABLE analytics_tag_weekly ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics_trending_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics_cache_meta ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read analytics_tag_weekly"
  ON analytics_tag_weekly FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can read analytics_trending_tags"
  ON analytics_trending_tags FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can read analytics_cache_meta"
  ON analytics_cache_meta FOR SELECT
  TO authenticated
  USING (true);

-- ── refresh_analytics_cache() ───────────────────────────────
-- Aggregates events + tickets into the cache tables.
-- Called by cron edge function every 6 hours.

CREATE OR REPLACE FUNCTION refresh_analytics_cache()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- 1. Refresh analytics_tag_weekly
  TRUNCATE analytics_tag_weekly;

  -- Global aggregation (city=NULL, country=NULL)
  INSERT INTO analytics_tag_weekly
    (tag_id, week_start, city, country, event_count, avg_price_cents, total_tickets_sold, total_revenue_cents)
  SELECT
    t.tag_id,
    date_trunc('week', e.date)::date AS week_start,
    NULL AS city,
    NULL AS country,
    COUNT(DISTINCT e.id) AS event_count,
    COALESCE(AVG(e.price_in_cents) FILTER (WHERE e.price_in_cents > 0), 0)::int AS avg_price_cents,
    COALESCE(SUM(tk.sold_count), 0)::int AS total_tickets_sold,
    COALESCE(SUM(tk.revenue_cents), 0) AS total_revenue_cents
  FROM events e
  CROSS JOIN LATERAL UNNEST(e.tags) AS t(tag_id)
  LEFT JOIN (
    SELECT event_id, COUNT(*) AS sold_count, SUM(price_paid_cents) AS revenue_cents
    FROM tickets
    WHERE status != 'cancelled' AND status != 'refunded'
    GROUP BY event_id
  ) tk ON tk.event_id = e.id
  WHERE e.deleted_at IS NULL
    AND e.tags IS NOT NULL
    AND array_length(e.tags, 1) > 0
  GROUP BY t.tag_id, week_start;

  -- Per-city aggregation
  INSERT INTO analytics_tag_weekly
    (tag_id, week_start, city, country, event_count, avg_price_cents, total_tickets_sold, total_revenue_cents)
  SELECT
    t.tag_id,
    date_trunc('week', e.date)::date AS week_start,
    e.city,
    e.country,
    COUNT(DISTINCT e.id) AS event_count,
    COALESCE(AVG(e.price_in_cents) FILTER (WHERE e.price_in_cents > 0), 0)::int AS avg_price_cents,
    COALESCE(SUM(tk.sold_count), 0)::int AS total_tickets_sold,
    COALESCE(SUM(tk.revenue_cents), 0) AS total_revenue_cents
  FROM events e
  CROSS JOIN LATERAL UNNEST(e.tags) AS t(tag_id)
  LEFT JOIN (
    SELECT event_id, COUNT(*) AS sold_count, SUM(price_paid_cents) AS revenue_cents
    FROM tickets
    WHERE status != 'cancelled' AND status != 'refunded'
    GROUP BY event_id
  ) tk ON tk.event_id = e.id
  WHERE e.deleted_at IS NULL
    AND e.tags IS NOT NULL
    AND array_length(e.tags, 1) > 0
    AND e.city IS NOT NULL
  GROUP BY t.tag_id, week_start, e.city, e.country;

  -- 2. Refresh analytics_trending_tags
  TRUNCATE analytics_trending_tags;

  INSERT INTO analytics_trending_tags
    (tag_id, tag_label, city, country, current_week_count, prev_week_count, trend_score, avg_price_cents, total_events_30d)
  SELECT
    tag_id,
    tag_id AS tag_label,
    city,
    country,
    COALESCE(SUM(event_count) FILTER (
      WHERE week_start = date_trunc('week', now())::date
    ), 0) AS current_week_count,
    COALESCE(SUM(event_count) FILTER (
      WHERE week_start = (date_trunc('week', now()) - interval '1 week')::date
    ), 0) AS prev_week_count,
    CASE
      WHEN COALESCE(SUM(event_count) FILTER (
        WHERE week_start = (date_trunc('week', now()) - interval '1 week')::date
      ), 0) = 0
      THEN COALESCE(SUM(event_count) FILTER (
        WHERE week_start = date_trunc('week', now())::date
      ), 0) * 100.0
      ELSE (
        (COALESCE(SUM(event_count) FILTER (
          WHERE week_start = date_trunc('week', now())::date
        ), 0)::numeric
         - SUM(event_count) FILTER (
          WHERE week_start = (date_trunc('week', now()) - interval '1 week')::date
        )::numeric)
        / SUM(event_count) FILTER (
          WHERE week_start = (date_trunc('week', now()) - interval '1 week')::date
        )::numeric
        * 100.0
      )
    END AS trend_score,
    COALESCE(AVG(avg_price_cents), 0)::int AS avg_price_cents,
    COALESCE(SUM(event_count) FILTER (
      WHERE week_start >= (now() - interval '30 days')::date
    ), 0) AS total_events_30d
  FROM analytics_tag_weekly
  GROUP BY tag_id, city, country;

  -- 3. Update refresh timestamp
  UPDATE analytics_cache_meta SET refreshed_at = now() WHERE key = 'last_refresh';
END;
$$;

-- Initial population
SELECT refresh_analytics_cache();
