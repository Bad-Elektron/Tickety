-- Add max_tickets column to events table for capacity tracking
ALTER TABLE events ADD COLUMN IF NOT EXISTS max_tickets INTEGER;

-- Add comment for documentation
COMMENT ON COLUMN events.max_tickets IS 'Maximum number of tickets available for this event. NULL means unlimited.';

-- Create function to get ticket availability using SQL aggregation
CREATE OR REPLACE FUNCTION get_ticket_availability(p_event_id UUID)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT json_build_object(
    'max_tickets', e.max_tickets,
    'sold_count', COALESCE(t.sold_count, 0),
    'available', CASE
      WHEN e.max_tickets IS NULL THEN NULL
      ELSE GREATEST(0, e.max_tickets - COALESCE(t.sold_count, 0))
    END
  )
  FROM events e
  LEFT JOIN (
    SELECT event_id, COUNT(*) as sold_count
    FROM tickets
    WHERE event_id = p_event_id
    GROUP BY event_id
  ) t ON t.event_id = e.id
  WHERE e.id = p_event_id;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_ticket_availability(UUID) TO authenticated;

-- Add comment for documentation
COMMENT ON FUNCTION get_ticket_availability(UUID) IS
  'Returns ticket availability (max_tickets, sold_count, available) using SQL aggregation.';
