-- Fix RLS policy on tickets table to allow buyers to see their purchased tickets
-- Previously, users could only see tickets for events they organized

-- Drop all existing policies we might recreate (safe - IF EXISTS)
DROP POLICY IF EXISTS "Users can view their purchased tickets" ON tickets;
DROP POLICY IF EXISTS "Users can view tickets for events they organize" ON tickets;
DROP POLICY IF EXISTS "Organizers can view event tickets" ON tickets;
DROP POLICY IF EXISTS "Staff can view event tickets" ON tickets;

-- Allow users to see tickets they purchased (sold_by = their user ID)
CREATE POLICY "Users can view their purchased tickets"
ON tickets FOR SELECT
USING (sold_by = auth.uid());

-- Allow event organizers to see all tickets for their events
CREATE POLICY "Organizers can view event tickets"
ON tickets FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM events
    WHERE events.id = tickets.event_id
    AND events.organizer_id = auth.uid()
  )
);

-- Allow event staff to see tickets for events they're assigned to
CREATE POLICY "Staff can view event tickets"
ON tickets FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM event_staff
    WHERE event_staff.event_id = tickets.event_id
    AND event_staff.user_id = auth.uid()
  )
);
