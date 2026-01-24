-- ============================================================
-- TICKETY DATABASE SETUP - FIXED VERSION
-- Run this in your Supabase SQL Editor (Dashboard > SQL Editor)
-- ============================================================

-- 1. ADD EMAIL COLUMN TO PROFILES
-- ============================================================

-- Check if email column exists and add it if not
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'profiles' AND column_name = 'email'
    ) THEN
        ALTER TABLE profiles ADD COLUMN email TEXT;
    END IF;
END $$;

-- Create index for email search (ignore if exists)
CREATE INDEX IF NOT EXISTS idx_profiles_email ON profiles(email);

-- Sync emails from auth.users to profiles
UPDATE profiles p
SET email = u.email
FROM auth.users u
WHERE p.id = u.id AND (p.email IS NULL OR p.email = '');

-- Update the trigger to include email on new user creation
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO profiles (id, display_name, email)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1)),
        NEW.email
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        display_name = COALESCE(profiles.display_name, EXCLUDED.display_name);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION handle_new_user();


-- 2. RLS FOR PROFILES
-- ============================================================

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Profiles are viewable by everyone" ON profiles;
CREATE POLICY "Profiles are viewable by everyone"
ON profiles FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
CREATE POLICY "Users can update own profile"
ON profiles FOR UPDATE TO authenticated USING (auth.uid() = id);


-- 3. EVENT_STAFF TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS event_staff (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'usher' CHECK (role IN ('usher', 'seller', 'manager')),
    invited_email TEXT,
    accepted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(event_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_event_staff_event_id ON event_staff(event_id);
CREATE INDEX IF NOT EXISTS idx_event_staff_user_id ON event_staff(user_id);

ALTER TABLE event_staff ENABLE ROW LEVEL SECURITY;

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

DROP POLICY IF EXISTS "Users can view own staff assignments" ON event_staff;
CREATE POLICY "Users can view own staff assignments"
ON event_staff FOR SELECT TO authenticated
USING (user_id = auth.uid());


-- 4. TICKETS TABLE
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

CREATE INDEX IF NOT EXISTS idx_tickets_event_id ON tickets(event_id);
CREATE INDEX IF NOT EXISTS idx_tickets_status ON tickets(status);
CREATE INDEX IF NOT EXISTS idx_tickets_ticket_number ON tickets(ticket_number);

ALTER TABLE tickets ENABLE ROW LEVEL SECURITY;

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
-- VERIFY: Check that email column now exists
-- ============================================================
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'profiles' AND column_name = 'email';
