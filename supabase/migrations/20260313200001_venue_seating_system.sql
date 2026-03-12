-- Venue/Seating Chart System
-- Phase 1: Builder + Data Model (enterprise-only)

-- ── venues table ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS venues (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  canvas_width INT NOT NULL DEFAULT 1200,
  canvas_height INT NOT NULL DEFAULT 800,
  layout_data JSONB NOT NULL DEFAULT '{"sections": [], "elements": [], "gridSize": 12, "version": 1}'::jsonb,
  total_capacity INT NOT NULL DEFAULT 0,
  thumbnail_url TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- layout_data JSONB structure:
-- {
--   "sections": [
--     {
--       "id": "uuid",
--       "name": "Section A",
--       "type": "seated" | "standing" | "table",
--       "shape": { "x": 0, "y": 0, "width": 200, "height": 150, "rotation": 0, "shapeType": "rectangle", "points": [] },
--       "color": "#6366F1",
--       "pricingTier": "vip",
--       "capacity": 100,
--       "rows": [
--         {
--           "id": "uuid",
--           "label": "A",
--           "curveRadius": 0,
--           "spacing": 1.0,
--           "seats": [
--             { "id": "uuid", "number": 1, "x": 10, "y": 10, "status": "available" }
--           ]
--         }
--       ],
--       "tableConfig": { "shape": "round", "seatsPerTable": 8, "tableCount": 10 }
--     }
--   ],
--   "elements": [
--     {
--       "id": "uuid",
--       "type": "stage" | "bar" | "entrance" | "restroom" | "label",
--       "label": "Main Stage",
--       "shape": { "x": 100, "y": 50, "width": 300, "height": 80, "rotation": 0, "shapeType": "rectangle" }
--     }
--   ],
--   "gridSize": 12,
--   "version": 1
-- }

-- ── venue_seats table (Phase 2 prep, empty) ────────────────────
CREATE TABLE IF NOT EXISTS venue_seats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
  section_id TEXT NOT NULL,
  row_label TEXT NOT NULL,
  seat_number INT NOT NULL,
  status TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'blocked', 'accessible')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (venue_id, section_id, row_label, seat_number)
);

-- ── Link events to venues ──────────────────────────────────────
ALTER TABLE events ADD COLUMN IF NOT EXISTS venue_id UUID REFERENCES venues(id) ON DELETE SET NULL;

-- ── RLS ────────────────────────────────────────────────────────
ALTER TABLE venues ENABLE ROW LEVEL SECURITY;
ALTER TABLE venue_seats ENABLE ROW LEVEL SECURITY;

-- Organizers can CRUD their own venues
CREATE POLICY "Organizers manage own venues" ON venues
  FOR ALL
  USING (organizer_id = auth.uid())
  WITH CHECK (organizer_id = auth.uid());

-- Public can view active venues
CREATE POLICY "Public can view active venues" ON venues
  FOR SELECT
  USING (is_active = true);

-- venue_seats inherits venue ownership
CREATE POLICY "Organizers manage own venue seats" ON venue_seats
  FOR ALL
  USING (
    venue_id IN (SELECT id FROM venues WHERE organizer_id = auth.uid())
  )
  WITH CHECK (
    venue_id IN (SELECT id FROM venues WHERE organizer_id = auth.uid())
  );

CREATE POLICY "Public can view venue seats" ON venue_seats
  FOR SELECT
  USING (
    venue_id IN (SELECT id FROM venues WHERE is_active = true)
  );

-- ── Updated_at trigger ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_venues_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER venues_updated_at
  BEFORE UPDATE ON venues
  FOR EACH ROW
  EXECUTE FUNCTION update_venues_updated_at();

-- ── Indexes ────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_venues_organizer ON venues(organizer_id);
CREATE INDEX IF NOT EXISTS idx_venues_active ON venues(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_events_venue ON events(venue_id) WHERE venue_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_venue_seats_venue ON venue_seats(venue_id);
