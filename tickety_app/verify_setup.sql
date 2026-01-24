-- ============================================================
-- TICKETY SETUP VERIFICATION
-- Run this to confirm everything is configured correctly
-- ============================================================

SELECT '=== PROFILES TABLE ===' AS check_section;

SELECT
    CASE WHEN COUNT(*) > 0 THEN '✓ profiles table exists' ELSE '✗ profiles table MISSING' END AS status
FROM information_schema.tables
WHERE table_name = 'profiles';

SELECT
    CASE WHEN COUNT(*) > 0 THEN '✓ email column exists' ELSE '✗ email column MISSING' END AS status
FROM information_schema.columns
WHERE table_name = 'profiles' AND column_name = 'email';

SELECT '=== EVENT_STAFF TABLE ===' AS check_section;

SELECT
    CASE WHEN COUNT(*) > 0 THEN '✓ event_staff table exists' ELSE '✗ event_staff table MISSING' END AS status
FROM information_schema.tables
WHERE table_name = 'event_staff';

SELECT '=== TICKETS TABLE ===' AS check_section;

SELECT
    CASE WHEN COUNT(*) > 0 THEN '✓ tickets table exists' ELSE '✗ tickets table MISSING' END AS status
FROM information_schema.tables
WHERE table_name = 'tickets';

SELECT '=== EVENTS TABLE ===' AS check_section;

SELECT
    CASE WHEN COUNT(*) > 0 THEN '✓ events table exists' ELSE '✗ events table MISSING' END AS status
FROM information_schema.tables
WHERE table_name = 'events';

SELECT '=== TEST USERS ===' AS check_section;

SELECT
    COALESCE(display_name, '(no name)') AS name,
    COALESCE(email, '(no email)') AS email,
    CASE WHEN email IS NOT NULL THEN '✓' ELSE '✗' END AS has_email
FROM profiles
WHERE email LIKE '%@test.com'
ORDER BY email;

SELECT
    CASE
        WHEN COUNT(*) >= 4 THEN '✓ All 4 test users found'
        WHEN COUNT(*) > 0 THEN '⚠ Only ' || COUNT(*) || ' test user(s) found'
        ELSE '✗ No test users found - create them in Auth > Users'
    END AS status
FROM profiles
WHERE email LIKE '%@test.com';

SELECT '=== ALL PROFILES ===' AS check_section;

SELECT id, email, display_name, created_at
FROM profiles
ORDER BY created_at DESC
LIMIT 10;

SELECT '=== SUMMARY ===' AS check_section;

SELECT
    (SELECT COUNT(*) FROM profiles) AS total_profiles,
    (SELECT COUNT(*) FROM profiles WHERE email IS NOT NULL) AS profiles_with_email,
    (SELECT COUNT(*) FROM events) AS total_events,
    (SELECT COUNT(*) FROM event_staff) AS total_staff_assignments,
    (SELECT COUNT(*) FROM tickets) AS total_tickets;
