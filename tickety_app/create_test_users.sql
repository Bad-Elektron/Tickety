-- ============================================================
-- UPDATE TEST USER DISPLAY NAMES
-- Run this AFTER creating users in Authentication > Users
-- ============================================================

-- First, sync any missing emails from auth.users
UPDATE profiles p
SET email = u.email
FROM auth.users u
WHERE p.id = u.id AND (p.email IS NULL OR p.email = '');

-- Now update display names for test users
UPDATE profiles SET display_name = 'Alex Usher' WHERE email = 'usher1@test.com';
UPDATE profiles SET display_name = 'Sam Usher' WHERE email = 'usher2@test.com';
UPDATE profiles SET display_name = 'Jordan Seller' WHERE email = 'seller1@test.com';
UPDATE profiles SET display_name = 'Taylor Manager' WHERE email = 'manager1@test.com';

-- Verify the updates
SELECT id, email, display_name, tier, created_at
FROM profiles
WHERE email LIKE '%@test.com'
ORDER BY email;
