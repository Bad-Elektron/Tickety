-- Update get_my_events to include series_id, occurrence_index, recurrence_type, access_password
-- so the app can group recurring events in My Events.

DROP FUNCTION IF EXISTS get_my_events(UUID, TEXT, TEXT, INT, INT);

CREATE OR REPLACE FUNCTION get_my_events(
  p_user_id UUID,
  p_date_filter TEXT DEFAULT 'recent',
  p_search_query TEXT DEFAULT NULL,
  p_limit INT DEFAULT 20,
  p_offset INT DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  title TEXT,
  subtitle TEXT,
  description TEXT,
  date TIMESTAMPTZ,
  location TEXT,
  venue TEXT,
  city TEXT,
  country TEXT,
  image_url TEXT,
  noise_seed INT,
  category TEXT,
  tags TEXT[],
  price_in_cents INT,
  currency TEXT,
  max_tickets INT,
  organizer_id UUID,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  is_upcoming BOOLEAN,
  total_count BIGINT,
  is_private BOOLEAN,
  invite_code VARCHAR(8),
  status TEXT,
  status_reason TEXT,
  series_id UUID,
  occurrence_index INT,
  recurrence_type TEXT,
  access_password VARCHAR(64)
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_now TIMESTAMPTZ := NOW();
  v_one_week_ago TIMESTAMPTZ := NOW() - INTERVAL '7 days';
  v_total BIGINT;
BEGIN
  SELECT COUNT(*) INTO v_total
  FROM events e
  WHERE e.organizer_id = p_user_id
    AND e.deleted_at IS NULL
    AND (
      CASE p_date_filter
        WHEN 'recent' THEN e.date >= v_one_week_ago
        WHEN 'upcoming' THEN e.date >= v_now
        WHEN 'past' THEN e.date < v_now
        ELSE TRUE
      END
    )
    AND (
      p_search_query IS NULL
      OR e.title ILIKE '%' || p_search_query || '%'
      OR e.subtitle ILIKE '%' || p_search_query || '%'
      OR e.venue ILIKE '%' || p_search_query || '%'
      OR e.city ILIKE '%' || p_search_query || '%'
    );

  RETURN QUERY
  SELECT
    e.id,
    e.title,
    e.subtitle,
    e.description,
    e.date,
    e.location,
    e.venue,
    e.city,
    e.country,
    e.image_url,
    e.noise_seed,
    e.category,
    e.tags,
    e.price_in_cents,
    e.currency,
    e.max_tickets,
    e.organizer_id,
    e.created_at,
    e.updated_at,
    (e.date >= v_now) AS is_upcoming,
    v_total AS total_count,
    e.is_private,
    e.invite_code,
    e.status,
    e.status_reason,
    e.series_id,
    e.occurrence_index,
    e.recurrence_type,
    e.access_password
  FROM events e
  WHERE e.organizer_id = p_user_id
    AND e.deleted_at IS NULL
    AND (
      CASE p_date_filter
        WHEN 'recent' THEN e.date >= v_one_week_ago
        WHEN 'upcoming' THEN e.date >= v_now
        WHEN 'past' THEN e.date < v_now
        ELSE TRUE
      END
    )
    AND (
      p_search_query IS NULL
      OR e.title ILIKE '%' || p_search_query || '%'
      OR e.subtitle ILIKE '%' || p_search_query || '%'
      OR e.venue ILIKE '%' || p_search_query || '%'
      OR e.city ILIKE '%' || p_search_query || '%'
    )
  ORDER BY
    CASE WHEN e.date >= v_now THEN 0 ELSE 1 END,
    CASE WHEN e.date >= v_now THEN e.date END ASC NULLS LAST,
    CASE WHEN e.date < v_now THEN e.date END DESC NULLS LAST
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;
