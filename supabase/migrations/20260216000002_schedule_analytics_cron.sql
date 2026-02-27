-- Enable pg_cron extension if not already enabled.
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

-- Grant usage so cron schema is accessible.
GRANT USAGE ON SCHEMA cron TO postgres;

-- Schedule analytics cache refresh every 24 hours (midnight UTC).
SELECT cron.schedule(
  'refresh-analytics-cache',
  '0 0 * * *',
  $$SELECT refresh_analytics_cache()$$
);
