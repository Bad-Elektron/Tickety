-- ============================================================
-- External Events Aggregation System
-- ============================================================

CREATE TABLE IF NOT EXISTS external_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source TEXT NOT NULL CHECK (source IN ('ticketmaster', 'seatgeek', 'predicthq')),
    external_id TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    start_date TIMESTAMPTZ NOT NULL,
    end_date TIMESTAMPTZ,
    venue_name TEXT,
    venue_address TEXT,
    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION,
    image_url TEXT,
    category TEXT,
    genre TEXT,
    price_range_min INT,   -- cents
    price_range_max INT,   -- cents
    ticket_url TEXT NOT NULL,
    source_updated_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (source, external_id)
);

CREATE TABLE IF NOT EXISTS external_event_sync_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source TEXT NOT NULL,
    last_sync_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    events_added INT DEFAULT 0,
    events_updated INT DEFAULT 0,
    events_removed INT DEFAULT 0,
    next_cursor TEXT,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_external_events_active_date ON external_events(start_date) WHERE is_active = true;
CREATE INDEX idx_external_events_source_extid ON external_events(source, external_id);
CREATE INDEX idx_external_events_category ON external_events(category) WHERE is_active = true;
CREATE INDEX idx_external_events_location ON external_events(lat, lng) WHERE is_active = true AND lat IS NOT NULL;

-- RLS
ALTER TABLE external_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE external_event_sync_log ENABLE ROW LEVEL SECURITY;

-- Public read for active future events (discovery feed)
CREATE POLICY "Public read active external events"
    ON external_events FOR SELECT
    USING (is_active = true AND start_date > NOW());

-- Sync log: service role only
CREATE POLICY "Service role only sync log"
    ON external_event_sync_log FOR ALL
    USING (false);

-- Cleanup function: mark past events inactive
CREATE OR REPLACE FUNCTION cleanup_external_events()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    UPDATE external_events
    SET is_active = false, updated_at = NOW()
    WHERE is_active = true
      AND start_date < NOW() - INTERVAL '1 day';

    -- Remove very old inactive events (>30 days past)
    DELETE FROM external_events
    WHERE is_active = false
      AND start_date < NOW() - INTERVAL '30 days';
END;
$$;

-- Dedup helper: find potential duplicate from another source
CREATE OR REPLACE FUNCTION find_duplicate_external_event(
    p_source TEXT,
    p_title TEXT,
    p_venue_name TEXT,
    p_start_date TIMESTAMPTZ
) RETURNS UUID LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_id UUID;
BEGIN
    SELECT id INTO v_id
    FROM external_events
    WHERE source != p_source
      AND lower(title) = lower(p_title)
      AND lower(COALESCE(venue_name, '')) = lower(COALESCE(p_venue_name, ''))
      AND ABS(EXTRACT(EPOCH FROM start_date - p_start_date)) < 7200
      AND is_active = true
    LIMIT 1;

    RETURN v_id;
END;
$$;

-- pg_cron: daily cleanup at 3am UTC
SELECT cron.schedule(
    'cleanup-external-events',
    '0 3 * * *',
    $$SELECT cleanup_external_events()$$
);
