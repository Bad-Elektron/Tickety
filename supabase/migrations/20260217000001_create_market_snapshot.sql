-- External market data snapshot from Ticketmaster + SeatGeek
-- Populated by the refresh-market-analytics edge function (daily via pg_cron chain)

CREATE TABLE IF NOT EXISTS analytics_market_snapshot (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tag_id     TEXT NOT NULL,
  source     TEXT NOT NULL CHECK (source IN ('ticketmaster', 'seatgeek')),

  event_count     INT,
  avg_price_cents INT,
  min_price_cents INT,
  max_price_cents INT,

  fetched_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  error_message TEXT,

  UNIQUE (tag_id, source)
);

-- Index for fast lookups by tag
CREATE INDEX idx_market_snapshot_tag ON analytics_market_snapshot (tag_id);

-- RLS: read-only for authenticated users
ALTER TABLE analytics_market_snapshot ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read market snapshots"
  ON analytics_market_snapshot
  FOR SELECT
  TO authenticated
  USING (true);

-- Seed the meta key so the edge function can UPDATE it
INSERT INTO analytics_cache_meta (key, refreshed_at)
VALUES ('market_last_refresh', '1970-01-01T00:00:00Z')
ON CONFLICT (key) DO NOTHING;
