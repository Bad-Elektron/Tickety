-- Fix: Remove hide_location column that doesn't exist in the events table

-- Must drop first because we're changing the return type
DROP FUNCTION IF EXISTS get_my_events(UUID, TEXT, TEXT, INT, INT);

CREATE OR REPLACE FUNCTION get_my_events(
  p_user_id UUID,
  p_date_filter TEXT DEFAULT 'recent',  -- 'recent', 'upcoming', 'all', 'past'
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
  total_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_now TIMESTAMPTZ := NOW();
  v_one_week_ago TIMESTAMPTZ := NOW() - INTERVAL '7 days';
  v_total BIGINT;
BEGIN
  -- Get total count first (for pagination info)
  SELECT COUNT(*) INTO v_total
  FROM events e
  WHERE e.organizer_id = p_user_id
    AND e.deleted_at IS NULL
    AND (
      CASE p_date_filter
        WHEN 'recent' THEN e.date >= v_one_week_ago
        WHEN 'upcoming' THEN e.date >= v_now
        WHEN 'past' THEN e.date < v_now
        ELSE TRUE  -- 'all'
      END
    )
    AND (
      p_search_query IS NULL
      OR e.title ILIKE '%' || p_search_query || '%'
      OR e.subtitle ILIKE '%' || p_search_query || '%'
      OR e.venue ILIKE '%' || p_search_query || '%'
      OR e.city ILIKE '%' || p_search_query || '%'
    );

  -- Return results with smart sorting
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
    v_total AS total_count
  FROM events e
  WHERE e.organizer_id = p_user_id
    AND e.deleted_at IS NULL
    AND (
      CASE p_date_filter
        WHEN 'recent' THEN e.date >= v_one_week_ago
        WHEN 'upcoming' THEN e.date >= v_now
        WHEN 'past' THEN e.date < v_now
        ELSE TRUE  -- 'all'
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
    -- Upcoming events come first
    CASE WHEN e.date >= v_now THEN 0 ELSE 1 END,
    -- Within upcoming: soonest first (ascending)
    -- Within past: most recent first (descending)
    CASE WHEN e.date >= v_now THEN e.date END ASC NULLS LAST,
    CASE WHEN e.date < v_now THEN e.date END DESC NULLS LAST
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;
