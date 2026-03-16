-- Redeemable Tickets: Add category support to event_ticket_types and tickets
-- Allows ticket types to be either 'entry' (event admission) or 'redeemable' (single-use item)

-- Add category fields to event_ticket_types
ALTER TABLE event_ticket_types
  ADD COLUMN IF NOT EXISTS category TEXT DEFAULT 'entry' CHECK (category IN ('entry', 'redeemable')),
  ADD COLUMN IF NOT EXISTS item_icon TEXT,
  ADD COLUMN IF NOT EXISTS item_description TEXT;

-- Add denormalized category to tickets for fast queries
ALTER TABLE tickets
  ADD COLUMN IF NOT EXISTS category TEXT DEFAULT 'entry' CHECK (category IN ('entry', 'redeemable')),
  ADD COLUMN IF NOT EXISTS item_icon TEXT;

-- Index for filtering tickets by category
CREATE INDEX IF NOT EXISTS idx_tickets_category ON tickets (category);
CREATE INDEX IF NOT EXISTS idx_event_ticket_types_category ON event_ticket_types (category);

COMMENT ON COLUMN event_ticket_types.category IS 'entry = event admission, redeemable = single-use item (merch pickup, drink token, etc.)';
COMMENT ON COLUMN event_ticket_types.item_icon IS 'Emoji icon for redeemable items (e.g. 🎸, 🍺, 👕)';
COMMENT ON COLUMN event_ticket_types.item_description IS 'Short description of the redeemable item';
COMMENT ON COLUMN tickets.category IS 'Denormalized from ticket_type for fast queries';
COMMENT ON COLUMN tickets.item_icon IS 'Denormalized from ticket_type for display';
