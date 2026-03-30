-- Update the series materializer to copy access_password from template snapshot
-- into each generated event occurrence and ticket type.

CREATE OR REPLACE FUNCTION generate_series_occurrences(
  p_series_id UUID,
  p_min_future INT DEFAULT 8
)
RETURNS INT AS $$
DECLARE
  v_series RECORD;
  v_template JSONB;
  v_ticket_types JSONB;
  v_organizer_id UUID;
  v_last_date TIMESTAMPTZ;
  v_next_date TIMESTAMPTZ;
  v_created INT := 0;
  v_future_count INT;
  v_total_count INT;
  v_max_index INT;
  v_dom INT;
  v_new_event_id UUID;
BEGIN
  -- Fetch series info
  SELECT * INTO v_series FROM event_series WHERE id = p_series_id AND is_active = true;
  IF NOT FOUND THEN RETURN 0; END IF;

  v_template := v_series.template_snapshot;
  v_ticket_types := v_series.ticket_types_snapshot;
  v_organizer_id := v_series.organizer_id;

  -- Count existing occurrences
  SELECT COUNT(*), COUNT(*) FILTER (WHERE date >= NOW()),
         COALESCE(MAX(occurrence_index), -1)
  INTO v_total_count, v_future_count, v_max_index
  FROM events
  WHERE series_id = p_series_id AND deleted_at IS NULL;

  -- Find the last occurrence date
  SELECT COALESCE(MAX(date), v_series.starts_at - INTERVAL '1 day')
  INTO v_last_date
  FROM events
  WHERE series_id = p_series_id AND deleted_at IS NULL;

  -- Generate occurrences until we have enough future ones
  WHILE v_future_count + v_created < p_min_future LOOP
    IF v_series.max_occurrences IS NOT NULL
       AND v_total_count + v_created >= v_series.max_occurrences THEN
      EXIT;
    END IF;

    CASE v_series.recurrence_type
      WHEN 'daily' THEN
        v_next_date := v_last_date + INTERVAL '1 day';
        v_next_date := date_trunc('day', v_next_date) + v_series.recurrence_time;

      WHEN 'weekly' THEN
        v_next_date := v_last_date + INTERVAL '1 day';
        LOOP
          EXIT WHEN EXTRACT(DOW FROM v_next_date) = v_series.recurrence_day;
          v_next_date := v_next_date + INTERVAL '1 day';
        END LOOP;
        v_next_date := date_trunc('day', v_next_date) + v_series.recurrence_time;

      WHEN 'biweekly' THEN
        v_next_date := v_last_date + INTERVAL '8 days';
        LOOP
          EXIT WHEN EXTRACT(DOW FROM v_next_date) = v_series.recurrence_day;
          v_next_date := v_next_date + INTERVAL '1 day';
        END LOOP;
        v_next_date := date_trunc('day', v_next_date) + v_series.recurrence_time;

      WHEN 'monthly' THEN
        v_dom := COALESCE(v_series.recurrence_day, 1);
        v_next_date := (date_trunc('month', v_last_date) + INTERVAL '1 month');
        v_next_date := v_next_date +
          (LEAST(v_dom, EXTRACT(DAY FROM (date_trunc('month', v_next_date) + INTERVAL '1 month' - INTERVAL '1 day'))::INT) - 1) * INTERVAL '1 day';
        v_next_date := date_trunc('day', v_next_date) + v_series.recurrence_time;

        IF v_next_date <= v_last_date THEN
          v_next_date := (date_trunc('month', v_last_date) + INTERVAL '2 months');
          v_next_date := v_next_date +
            (LEAST(v_dom, EXTRACT(DAY FROM (date_trunc('month', v_next_date) + INTERVAL '1 month' - INTERVAL '1 day'))::INT) - 1) * INTERVAL '1 day';
          v_next_date := date_trunc('day', v_next_date) + v_series.recurrence_time;
        END IF;
    END CASE;

    IF v_series.ends_at IS NOT NULL AND v_next_date > v_series.ends_at THEN
      EXIT;
    END IF;

    v_max_index := v_max_index + 1;

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
      recurrence_type,
      access_password
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
      v_series.recurrence_type,
      v_template->>'access_password'
    )
    RETURNING id INTO v_new_event_id;

    -- Clone ticket types if present (now with access_password)
    IF v_ticket_types IS NOT NULL AND jsonb_array_length(v_ticket_types) > 0 THEN
      INSERT INTO event_ticket_types (event_id, name, description, price_cents, max_quantity, sort_order, access_password)
      SELECT
        v_new_event_id,
        tt->>'name',
        tt->>'description',
        COALESCE((tt->>'price_cents')::INT, 0),
        (tt->>'max_quantity')::INT,
        (tt->>'sort_order')::INT,
        tt->>'access_password'
      FROM jsonb_array_elements(v_ticket_types) AS tt;
    END IF;

    v_last_date := v_next_date;
    v_created := v_created + 1;
  END LOOP;

  RETURN v_created;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
