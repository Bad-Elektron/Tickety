-- ============================================================
-- TICKETY DATABASE SETUP
-- Run this in your Supabase SQL Editor (Dashboard > SQL Editor)
-- ============================================================

-- 1. PROFILES TABLE (extends auth.users with app-specific data)
-- ============================================================

-- First, update profiles table to include email for easier searches
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS email TEXT;

-- Create index for email search
CREATE INDEX IF NOT EXISTS idx_profiles_email ON profiles(email);

-- Update existing profiles to have email from auth.users
UPDATE profiles p
SET email = u.email
FROM auth.users u
WHERE p.id = u.id AND p.email IS NULL;

-- Update the trigger to include email
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO profiles (id, display_name, email)
    VALUES (
        NEW.id,
        NEW.raw_user_meta_data->>'display_name',
        NEW.email
    );
    RETURN NEW;
END;
$$ language 'plpgsql' security definer;

-- RLS for profiles (if not already set)
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Profiles are viewable by everyone" ON profiles;
CREATE POLICY "Profiles are viewable by everyone"
ON profiles FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
CREATE POLICY "Users can update own profile"
ON profiles FOR UPDATE TO authenticated USING (auth.uid() = id);


-- 2. EVENT_STAFF TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS event_staff (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'usher' CHECK (role IN ('usher', 'seller', 'manager')),
    invited_email TEXT,
    accepted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Each user can only have one role per event
    UNIQUE(event_id, user_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_event_staff_event_id ON event_staff(event_id);
CREATE INDEX IF NOT EXISTS idx_event_staff_user_id ON event_staff(user_id);

-- RLS
ALTER TABLE event_staff ENABLE ROW LEVEL SECURITY;

-- Event organizers can manage staff
DROP POLICY IF EXISTS "Organizers can manage staff" ON event_staff;
CREATE POLICY "Organizers can manage staff"
ON event_staff FOR ALL TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM events
        WHERE events.id = event_staff.event_id
        AND events.organizer_id = auth.uid()
    )
);

-- Staff can view their own assignments
DROP POLICY IF EXISTS "Users can view own staff assignments" ON event_staff;
CREATE POLICY "Users can view own staff assignments"
ON event_staff FOR SELECT TO authenticated
USING (user_id = auth.uid());

-- Managers can view all staff for their events
DROP POLICY IF EXISTS "Managers can view event staff" ON event_staff;
CREATE POLICY "Managers can view event staff"
ON event_staff FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM event_staff es
        WHERE es.event_id = event_staff.event_id
        AND es.user_id = auth.uid()
        AND es.role = 'manager'
    )
);


-- 3. TICKETS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS tickets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    ticket_number TEXT NOT NULL UNIQUE,
    owner_email TEXT,
    owner_name TEXT,
    owner_wallet_address TEXT,
    price_paid_cents INTEGER NOT NULL DEFAULT 0,
    currency TEXT NOT NULL DEFAULT 'USD',
    status TEXT NOT NULL DEFAULT 'valid' CHECK (status IN ('valid', 'used', 'cancelled', 'refunded')),
    sold_by UUID REFERENCES auth.users(id),
    sold_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    checked_in_at TIMESTAMPTZ,
    checked_in_by UUID REFERENCES auth.users(id),
    metadata JSONB DEFAULT '{}'
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_tickets_event_id ON tickets(event_id);
CREATE INDEX IF NOT EXISTS idx_tickets_status ON tickets(status);
CREATE INDEX IF NOT EXISTS idx_tickets_ticket_number ON tickets(ticket_number);

-- RLS
ALTER TABLE tickets ENABLE ROW LEVEL SECURITY;

-- Organizers can view all tickets for their events
DROP POLICY IF EXISTS "Organizers can view event tickets" ON tickets;
CREATE POLICY "Organizers can view event tickets"
ON tickets FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM events
        WHERE events.id = tickets.event_id
        AND events.organizer_id = auth.uid()
    )
);

-- Staff can view and manage tickets for their events
DROP POLICY IF EXISTS "Staff can view event tickets" ON tickets;
CREATE POLICY "Staff can view event tickets"
ON tickets FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM event_staff
        WHERE event_staff.event_id = tickets.event_id
        AND event_staff.user_id = auth.uid()
    )
);

-- Sellers can create tickets
DROP POLICY IF EXISTS "Sellers can create tickets" ON tickets;
CREATE POLICY "Sellers can create tickets"
ON tickets FOR INSERT TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM event_staff
        WHERE event_staff.event_id = tickets.event_id
        AND event_staff.user_id = auth.uid()
        AND event_staff.role IN ('seller', 'manager')
    )
    OR
    EXISTS (
        SELECT 1 FROM events
        WHERE events.id = tickets.event_id
        AND events.organizer_id = auth.uid()
    )
);

-- Ushers can update tickets (check-in)
DROP POLICY IF EXISTS "Staff can update tickets" ON tickets;
CREATE POLICY "Staff can update tickets"
ON tickets FOR UPDATE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM event_staff
        WHERE event_staff.event_id = tickets.event_id
        AND event_staff.user_id = auth.uid()
    )
    OR
    EXISTS (
        SELECT 1 FROM events
        WHERE events.id = tickets.event_id
        AND events.organizer_id = auth.uid()
    )
);


-- ============================================================
-- 4. CREATE TEST USERS
-- ============================================================
-- NOTE: These must be created through Supabase Auth, not directly in the database.
--
-- Go to Authentication > Users in your Supabase Dashboard and create these users:
--
-- Test User 1 (Usher):
--   Email: usher1@test.com
--   Password: TestPassword123!
--   (After creating, note the user ID)
--
-- Test User 2 (Usher):
--   Email: usher2@test.com
--   Password: TestPassword123!
--
-- Test User 3 (Seller):
--   Email: seller1@test.com
--   Password: TestPassword123!
--
-- Test User 4 (Manager):
--   Email: manager1@test.com
--   Password: TestPassword123!
--
-- After creating users in the Auth dashboard, run the following to update their display names:

-- UPDATE profiles SET display_name = 'Alex Usher' WHERE email = 'usher1@test.com';
-- UPDATE profiles SET display_name = 'Sam Usher' WHERE email = 'usher2@test.com';
-- UPDATE profiles SET display_name = 'Jordan Seller' WHERE email = 'seller1@test.com';
-- UPDATE profiles SET display_name = 'Taylor Manager' WHERE email = 'manager1@test.com';


-- ============================================================
-- 5. HELPER FUNCTION: Get staff count for an event
-- ============================================================

CREATE OR REPLACE FUNCTION get_event_staff_count(p_event_id UUID)
RETURNS INTEGER AS $$
    SELECT COUNT(*)::INTEGER
    FROM event_staff
    WHERE event_id = p_event_id;
$$ LANGUAGE sql STABLE;


-- ============================================================
-- VERIFICATION QUERIES (run after setup to check everything works)
-- ============================================================

-- Check profiles table structure
-- SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'profiles';

-- Check event_staff table structure
-- SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'event_staff';

-- Check tickets table structure
-- SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'tickets';

-- List all profiles (should show test users after they're created)
-- SELECT id, email, display_name, tier FROM profiles;
