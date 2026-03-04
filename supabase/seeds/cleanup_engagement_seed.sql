-- ============================================================
-- CLEANUP: Remove Dev Engagement Seed Data
-- ============================================================
-- Run this before going to production or when you want to
-- start fresh with only real organic view data.
--
-- Safe to run multiple times (idempotent).
-- ============================================================

-- Remove all view telemetry (dev + any real views)
TRUNCATE event_views;

-- Clear the derived cache
TRUNCATE analytics_engagement_daily;

-- Remove the dev seed marker
DELETE FROM analytics_cache_meta WHERE key = 'dev_seed_marker';

-- Reset the refresh timestamp
UPDATE analytics_cache_meta
SET refreshed_at = now()
WHERE key = 'engagement_last_refresh';

-- Confirm
DO $$ BEGIN RAISE NOTICE 'Engagement seed data removed. Tables are clean.'; END; $$;
