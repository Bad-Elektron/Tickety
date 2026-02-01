-- Create function to get event analytics without fetching all ticket rows
-- This returns pre-aggregated stats for the analytics dashboard

CREATE OR REPLACE FUNCTION get_event_analytics(p_event_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result JSON;
BEGIN
  SELECT json_build_object(
    'total_sold', COALESCE(COUNT(*), 0),
    'checked_in', COALESCE(COUNT(*) FILTER (WHERE status = 'used'), 0),
    'revenue_cents', COALESCE(SUM(price_paid_cents), 0),
    'hourly_checkins', (
      SELECT COALESCE(json_agg(
        json_build_object(
          'hour', hour,
          'count', cnt
        ) ORDER BY hour
      ), '[]'::json)
      FROM (
        SELECT
          EXTRACT(HOUR FROM checked_in_at)::int AS hour,
          COUNT(*) AS cnt
        FROM tickets
        WHERE event_id = p_event_id
          AND checked_in_at IS NOT NULL
        GROUP BY EXTRACT(HOUR FROM checked_in_at)
      ) hourly
    ),
    'usher_stats', (
      SELECT COALESCE(json_agg(
        json_build_object(
          'user_id', checked_in_by,
          'count', cnt
        ) ORDER BY cnt DESC
      ), '[]'::json)
      FROM (
        SELECT
          checked_in_by,
          COUNT(*) AS cnt
        FROM tickets
        WHERE event_id = p_event_id
          AND checked_in_by IS NOT NULL
        GROUP BY checked_in_by
      ) ushers
    )
  ) INTO result
  FROM tickets
  WHERE event_id = p_event_id;

  -- Handle case where no tickets exist
  IF result IS NULL THEN
    result := json_build_object(
      'total_sold', 0,
      'checked_in', 0,
      'revenue_cents', 0,
      'hourly_checkins', '[]'::json,
      'usher_stats', '[]'::json
    );
  END IF;

  RETURN result;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_event_analytics(UUID) TO authenticated;

-- Add comment for documentation
COMMENT ON FUNCTION get_event_analytics(UUID) IS
  'Returns pre-aggregated analytics for an event: total sold, checked in count, revenue, hourly check-in breakdown, and usher performance stats.';
