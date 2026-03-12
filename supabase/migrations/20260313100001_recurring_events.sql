-- ============================================================
-- Recurring Events System
-- ============================================================
-- Each occurrence is a real events row. A parent event_series table
-- holds the recurrence rule. All existing infrastructure works unchanged.

-- ============================================================
-- TABLE: event_series
-- ============================================================
CREATE TABLE IF NOT EXISTS event_series (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Recurrence pattern
  recurrence_type TEXT NOT NULL CHECK (recurrence_type IN ('daily', 'weekly', 'biweekly', 'monthly')),
  -- For weekly/biweekly: 0=Sunday..6=Saturday. For monthly: 1-31 (day of month). For daily: ignored.
  recurrence_day INT,
  -- Time of day for all occurrences
  recurrence_time TIME NOT NULL,

  -- Bounds
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ, -- null = no end date
  max_occurrences INT, -- null = unlimited

  -- Template used to generate new occurrence rows
  template_snapshot JSONB NOT NULL,
  -- Ticket types to clone for each new occurrence
  ticket_types_snapshot JSONB,

  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_event_series_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_event_series_updated_at
  BEFORE UPDATE ON event_series
  FOR EACH ROW EXECUTE FUNCTION update_event_series_updated_at();

-- ============================================================
-- RLS for event_series
-- ============================================================
ALTER TABLE event_series ENABLE ROW LEVEL SECURITY;

CREATE POLICY series_select_own ON event_series
  FOR SELECT TO authenticated
  USING (organizer_id = auth.uid());

CREATE POLICY series_insert_own ON event_series
  FOR INSERT TO authenticated
  WITH CHECK (organizer_id = auth.uid());

CREATE POLICY series_update_own ON event_series
  FOR UPDATE TO authenticated
  USING (organizer_id = auth.uid());

CREATE POLICY series_service_all ON event_series
  FOR ALL TO service_role
  USING (true) WITH CHECK (true);

-- ============================================================
-- ALTER events table
-- ============================================================
ALTER TABLE events ADD COLUMN IF NOT EXISTS series_id UUID REFERENCES event_series(id) ON DELETE SET NULL;
ALTER TABLE events ADD COLUMN IF NOT EXISTS occurrence_index INT;
ALTER TABLE events ADD COLUMN IF NOT EXISTS series_edited BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE events ADD COLUMN IF NOT EXISTS recurrence_type TEXT;

CREATE INDEX IF NOT EXISTS idx_events_series_id ON events(series_id) WHERE series_id IS NOT NULL;

-- ============================================================
-- FUNCTION: generate_series_occurrences
-- Ensures at least p_min_future future occurrences exist for a series.
-- Returns the number of newly created occurrences.
-- ============================================================
CREATE OR REPLACE FUNCTION generate_series_occurrences(
  p_series_id UUID,
  p_min_future INT DEFAULT 4
)
RETURNS INT AS $$
DECLARE
  v_series RECORD;
  v_future_count INT;
  v_max_index INT;
  v_total_count INT;
  v_created INT := 0;
  v_next_date TIMESTAMPTZ;
  v_last_date TIMESTAMPTZ;
  v_template JSONB;
  v_ticket_types JSONB;
  v_new_event_id UUID;
  v_organizer_id UUID;
  v_dow INT; -- day of week
  v_dom INT; -- day of month
BEGIN
  -- Fetch series
  SELECT * INTO v_series FROM event_series WHERE id = p_series_id AND is_active = true;
  IF NOT FOUND THEN RETURN 0; END IF;

  v_template := v_series.template_snapshot;
  v_ticket_types := v_series.ticket_types_snapshot;
  v_organizer_id := v_series.organizer_id;

  -- Count future occurrences
  SELECT COUNT(*) INTO v_future_count
  FROM events
  WHERE series_id = p_series_id AND date > now() AND deleted_at IS NULL;

  -- Already have enough
  IF v_future_count >= p_min_future THEN RETURN 0; END IF;

  -- Get current max occurrence_index and total count
  SELECT COALESCE(MAX(occurrence_index), -1), COUNT(*)
  INTO v_max_index, v_total_count
  FROM events
  WHERE series_id = p_series_id AND deleted_at IS NULL;

  -- Check max_occurrences limit
  IF v_series.max_occurrences IS NOT NULL AND v_total_count >= v_series.max_occurrences THEN
    RETURN 0;
  END IF;

  -- Find the last occurrence date (or starts_at if none exist)
  SELECT COALESCE(MAX(date), v_series.starts_at - INTERVAL '1 day')
  INTO v_last_date
  FROM events
  WHERE series_id = p_series_id AND deleted_at IS NULL;

  -- Generate occurrences until we have enough future ones
  WHILE v_future_count + v_created < p_min_future LOOP
    -- Check max_occurrences
    IF v_series.max_occurrences IS NOT NULL
       AND v_total_count + v_created >= v_series.max_occurrences THEN
      EXIT;
    END IF;

    -- Calculate next date based on recurrence type
    CASE v_series.recurrence_type
      WHEN 'daily' THEN
        v_next_date := v_last_date + INTERVAL '1 day';
        -- Set the time
        v_next_date := date_trunc('day', v_next_date) + v_series.recurrence_time;

      WHEN 'weekly' THEN
        v_next_date := v_last_date + INTERVAL '1 day';
        -- Advance to the correct day of week (0=Sun..6=Sat)
        -- PostgreSQL: EXTRACT(DOW) returns 0=Sunday..6=Saturday
        LOOP
          EXIT WHEN EXTRACT(DOW FROM v_next_date) = v_series.recurrence_day;
          v_next_date := v_next_date + INTERVAL '1 day';
        END LOOP;
        v_next_date := date_trunc('day', v_next_date) + v_series.recurrence_time;

      WHEN 'biweekly' THEN
        -- Start from last date + 1 day, find next matching DOW that's >= 14 days from last
        v_next_date := v_last_date + INTERVAL '8 days'; -- at least 8 days out
        LOOP
          EXIT WHEN EXTRACT(DOW FROM v_next_date) = v_series.recurrence_day;
          v_next_date := v_next_date + INTERVAL '1 day';
        END LOOP;
        v_next_date := date_trunc('day', v_next_date) + v_series.recurrence_time;

      WHEN 'monthly' THEN
        -- Next month, clamped to last day if needed
        v_dom := COALESCE(v_series.recurrence_day, 1);
        v_next_date := (date_trunc('month', v_last_date) + INTERVAL '1 month');
        -- Clamp day to last day of month
        v_next_date := v_next_date +
          (LEAST(v_dom, EXTRACT(DAY FROM (date_trunc('month', v_next_date) + INTERVAL '1 month' - INTERVAL '1 day'))::INT) - 1) * INTERVAL '1 day';
        v_next_date := date_trunc('day', v_next_date) + v_series.recurrence_time;

        -- If this date is not after v_last_date, skip another month
        IF v_next_date <= v_last_date THEN
          v_next_date := (date_trunc('month', v_last_date) + INTERVAL '2 months');
          v_next_date := v_next_date +
            (LEAST(v_dom, EXTRACT(DAY FROM (date_trunc('month', v_next_date) + INTERVAL '1 month' - INTERVAL '1 day'))::INT) - 1) * INTERVAL '1 day';
          v_next_date := date_trunc('day', v_next_date) + v_series.recurrence_time;
        END IF;
    END CASE;

    -- Check ends_at
    IF v_series.ends_at IS NOT NULL AND v_next_date > v_series.ends_at THEN
      EXIT;
    END IF;

    -- Increment index
    v_max_index := v_max_index + 1;

    -- Insert the new occurrence
    INSERT INTO events (
      organizer_id,
      title,
      subtitle,
      description,
      date,
      location,
      venue,
      city,
      country,
      image_url,
      noise_seed,
      custom_noise_config,
      tags,
      category,
      price_in_cents,
      currency,
      hide_location,
      max_tickets,
      cash_sales_enabled,
      is_private,
      nft_enabled,
      latitude,
      longitude,
      formatted_address,
      series_id,
      occurrence_index,
      recurrence_type
    ) VALUES (
      v_organizer_id,
      v_template->>'title',
      v_template->>'subtitle',
      v_template->>'description',
      v_next_date,
      v_template->>'location',
      v_template->>'venue',
      v_template->>'city',
      v_template->>'country',
      v_template->>'image_url',
      COALESCE((v_template->>'noise_seed')::INT, floor(random() * 10000)::INT),
      v_template->'custom_noise_config',
      COALESCE((SELECT array_agg(t.value) FROM jsonb_array_elements_text(v_template->'tags') AS t(value)), ARRAY[]::TEXT[]),
      v_template->>'category',
      (v_template->>'price_in_cents')::INT,
      COALESCE(v_template->>'currency', 'USD'),
      COALESCE((v_template->>'hide_location')::BOOLEAN, false),
      (v_template->>'max_tickets')::INT,
      COALESCE((v_template->>'cash_sales_enabled')::BOOLEAN, true),
      COALESCE((v_template->>'is_private')::BOOLEAN, false),
      COALESCE((v_template->>'nft_enabled')::BOOLEAN, true),
      (v_template->>'latitude')::DOUBLE PRECISION,
      (v_template->>'longitude')::DOUBLE PRECISION,
      v_template->>'formatted_address',
      p_series_id,
      v_max_index,
      v_series.recurrence_type
    )
    RETURNING id INTO v_new_event_id;

    -- Clone ticket types if present
    IF v_ticket_types IS NOT NULL AND jsonb_array_length(v_ticket_types) > 0 THEN
      INSERT INTO event_ticket_types (event_id, name, description, price_cents, max_quantity, sort_order)
      SELECT
        v_new_event_id,
        tt->>'name',
        tt->>'description',
        COALESCE((tt->>'price_cents')::INT, 0),
        (tt->>'max_quantity')::INT,
        (tt->>'sort_order')::INT
      FROM jsonb_array_elements(v_ticket_types) AS tt;
    END IF;

    v_last_date := v_next_date;
    v_created := v_created + 1;
  END LOOP;

  RETURN v_created;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- FUNCTION: generate_all_series_occurrences
-- Called by cron to maintain all active series.
-- ============================================================
CREATE OR REPLACE FUNCTION generate_all_series_occurrences()
RETURNS INT AS $$
DECLARE
  v_series RECORD;
  v_total INT := 0;
  v_created INT;
BEGIN
  FOR v_series IN SELECT id FROM event_series WHERE is_active = true LOOP
    v_created := generate_series_occurrences(v_series.id);
    v_total := v_total + v_created;
  END LOOP;
  RETURN v_total;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- FUNCTION: get_series_occurrences
-- Returns all occurrences for a series, ordered by date.
-- ============================================================
CREATE OR REPLACE FUNCTION get_series_occurrences(p_series_id UUID)
RETURNS TABLE (
  id UUID,
  title TEXT,
  date TIMESTAMPTZ,
  occurrence_index INT,
  series_edited BOOLEAN,
  status TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT e.id, e.title, e.date, e.occurrence_index, e.series_edited, e.status
  FROM events e
  WHERE e.series_id = p_series_id
    AND e.deleted_at IS NULL
  ORDER BY e.date ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- CRON: Generate series occurrences daily at 3am UTC
-- ============================================================
SELECT cron.schedule(
  'generate-series-occurrences',
  '0 3 * * *',
  $$SELECT generate_all_series_occurrences()$$
);
