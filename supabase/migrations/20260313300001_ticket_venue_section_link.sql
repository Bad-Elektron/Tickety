-- Link ticket types to specific venue sections
-- Allows organizers to map ticket types (e.g., "VIP") to venue sections (e.g., "VIP Balcony")

ALTER TABLE event_ticket_types
ADD COLUMN IF NOT EXISTS venue_section_id TEXT;

-- Add a comment for clarity (venue_section_id references the section id within the venue's layout_data JSONB, not a separate table)
COMMENT ON COLUMN event_ticket_types.venue_section_id IS 'References a section id within the linked venue layout_data JSONB. NULL means general/unassigned.';
