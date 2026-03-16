-- Fix event price_in_cents to reflect cheapest ENTRY ticket, not redeemable add-ons.
-- Also adds ticket_type_name to tickets for display purposes.

-- 1. Fix existing events: set price_in_cents to cheapest active entry ticket type
UPDATE events e
SET price_in_cents = sub.min_price
FROM (
  SELECT event_id, MIN(price_cents) as min_price
  FROM event_ticket_types
  WHERE is_active = true
    AND (category IS NULL OR category != 'redeemable')
    AND price_cents > 0
  GROUP BY event_id
) sub
WHERE e.id = sub.event_id
  AND sub.min_price IS NOT NULL;

-- 2. Create trigger function to auto-update event price on ticket type changes
CREATE OR REPLACE FUNCTION update_event_entry_price()
RETURNS TRIGGER AS $$
DECLARE
  target_event_id UUID;
  min_price INTEGER;
BEGIN
  -- Determine which event to update
  IF TG_OP = 'DELETE' THEN
    target_event_id := OLD.event_id;
  ELSE
    target_event_id := NEW.event_id;
  END IF;

  -- Get cheapest active entry ticket price
  SELECT MIN(price_cents) INTO min_price
  FROM event_ticket_types
  WHERE event_id = target_event_id
    AND is_active = true
    AND (category IS NULL OR category != 'redeemable')
    AND price_cents > 0;

  -- Update the event's display price
  IF min_price IS NOT NULL THEN
    UPDATE events SET price_in_cents = min_price WHERE id = target_event_id;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Attach trigger to event_ticket_types
DROP TRIGGER IF EXISTS trg_update_event_entry_price ON event_ticket_types;
CREATE TRIGGER trg_update_event_entry_price
  AFTER INSERT OR UPDATE OR DELETE ON event_ticket_types
  FOR EACH ROW EXECUTE FUNCTION update_event_entry_price();

-- 4. Add ticket_type_name to tickets table for display
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS ticket_type_name TEXT;
