-- Create function to get basic ticket stats without fetching all rows
-- This is a lightweight version of get_event_analytics for just counts

CREATE OR REPLACE FUNCTION get_ticket_stats(p_event_id UUID)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT COALESCE(
    json_build_object(
      'total_sold', COUNT(*),
      'checked_in', COUNT(*) FILTER (WHERE status = 'used'),
      'revenue_cents', COALESCE(SUM(price_paid_cents), 0)
    ),
    json_build_object(
      'total_sold', 0,
      'checked_in', 0,
      'revenue_cents', 0
    )
  )
  FROM tickets
  WHERE event_id = p_event_id;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_ticket_stats(UUID) TO authenticated;

-- Add comment for documentation
COMMENT ON FUNCTION get_ticket_stats(UUID) IS
  'Returns basic ticket stats (total sold, checked in, revenue) using SQL aggregation instead of fetching all rows.';
