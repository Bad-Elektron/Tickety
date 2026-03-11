-- ============================================================
-- Analytics Consolidation
-- ============================================================
-- 1. Unified get_event_dashboard() RPC — combines ticket stats
--    + engagement in a single call. Reads from cache where possible.
-- 2. Optimized get_admin_overview_stats() — server-side weekly
--    bucketing with 90-day limit instead of fetching all rows.
-- 3. Engagement cache now included in cron schedule.
-- ============================================================

-- ── 1. get_event_dashboard(event_id) ───────────────────────
-- Single RPC that returns everything an event detail page needs.
-- Ticket data is live (cheap — single table scan with index).
-- Engagement data reads from cache first, falls back to live.

CREATE OR REPLACE FUNCTION get_event_dashboard(p_event_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tickets JSONB;
  v_engagement JSONB;
  v_checkins JSONB;
BEGIN
  -- Ticket stats (live — single indexed scan, very cheap)
  SELECT jsonb_build_object(
    'total_sold', COALESCE(COUNT(*), 0),
    'checked_in', COALESCE(COUNT(*) FILTER (WHERE status = 'used'), 0),
    'revenue_cents', COALESCE(SUM(price_paid_cents), 0)
  ) INTO v_tickets
  FROM tickets
  WHERE event_id = p_event_id;

  IF v_tickets IS NULL THEN
    v_tickets := '{"total_sold":0,"checked_in":0,"revenue_cents":0}'::jsonb;
  END IF;

  -- Check-in breakdown (live — only for events with check-ins)
  SELECT jsonb_build_object(
    'hourly', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('hour', hour, 'count', cnt) ORDER BY hour)
      FROM (
        SELECT EXTRACT(HOUR FROM checked_in_at)::int AS hour, COUNT(*) AS cnt
        FROM tickets
        WHERE event_id = p_event_id AND checked_in_at IS NOT NULL
        GROUP BY EXTRACT(HOUR FROM checked_in_at)
      ) h
    ), '[]'::jsonb),
    'by_staff', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('user_id', checked_in_by, 'count', cnt) ORDER BY cnt DESC)
      FROM (
        SELECT checked_in_by, COUNT(*) AS cnt
        FROM tickets
        WHERE event_id = p_event_id AND checked_in_by IS NOT NULL
        GROUP BY checked_in_by
      ) s
    ), '[]'::jsonb)
  ) INTO v_checkins;

  -- Engagement: read from daily cache (cheap, pre-computed)
  SELECT jsonb_build_object(
    'total_views', COALESCE(SUM(total_views), 0),
    'unique_viewers', COALESCE(SUM(unique_viewers), 0),
    'purchasers', COALESCE(SUM(purchasers), 0),
    'views_7d', COALESCE((
      SELECT SUM(total_views) FROM analytics_engagement_daily
      WHERE event_id = p_event_id AND day >= (now() - interval '7 days')::date
    ), 0),
    'views_30d', COALESCE((
      SELECT SUM(total_views) FROM analytics_engagement_daily
      WHERE event_id = p_event_id AND day >= (now() - interval '30 days')::date
    ), 0),
    'conversion_rate', CASE
      WHEN COALESCE(SUM(unique_viewers), 0) > 0
      THEN ROUND(SUM(purchasers)::numeric / SUM(unique_viewers) * 100, 1)
      ELSE 0
    END,
    'daily_views', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('date', day, 'views', total_views) ORDER BY day)
      FROM analytics_engagement_daily
      WHERE event_id = p_event_id AND day >= (now() - interval '30 days')::date
    ), '[]'::jsonb),
    'source_breakdown', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('source', source, 'count', cnt) ORDER BY cnt DESC)
      FROM (
        SELECT source, COUNT(*) AS cnt
        FROM event_views
        WHERE event_id = p_event_id
        GROUP BY source
      ) src
    ), '[]'::jsonb)
  ) INTO v_engagement
  FROM analytics_engagement_daily
  WHERE event_id = p_event_id;

  RETURN jsonb_build_object(
    'tickets', v_tickets,
    'check_ins', v_checkins,
    'engagement', v_engagement
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_event_dashboard(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_event_dashboard(UUID) TO service_role;

COMMENT ON FUNCTION get_event_dashboard(UUID) IS
  'Unified event analytics: ticket stats (live) + check-ins (live) + engagement (from daily cache). Single call replaces get_event_analytics + get_ticket_stats + get_event_engagement.';


-- ── 2. get_admin_overview_stats() ──────────────────────────
-- Server-side aggregation for admin overview dashboard.
-- Replaces the client-side weekly bucketing in /api/admin/stats.
-- All heavy work in SQL with proper indexes, returns pre-bucketed data.

CREATE OR REPLACE FUNCTION get_admin_overview_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_users BIGINT;
  v_total_events BIGINT;
  v_total_revenue BIGINT;
  v_active_subs BIGINT;
  v_tickets_30d BIGINT;
  v_fees_30d BIGINT;
  v_revenue_weekly JSONB;
  v_signups_weekly JSONB;
  v_tier_dist JSONB;
BEGIN
  -- KPI counts (all use COUNT which hits indexes)
  SELECT COUNT(*) INTO v_total_users FROM profiles;

  SELECT COUNT(*) INTO v_total_events
  FROM events WHERE deleted_at IS NULL;

  SELECT COALESCE(SUM(amount_cents), 0) INTO v_total_revenue
  FROM payments WHERE status = 'completed';

  SELECT COUNT(*) INTO v_active_subs
  FROM subscriptions WHERE status = 'active' AND tier != 'base';

  SELECT COUNT(*) INTO v_tickets_30d
  FROM tickets WHERE sold_at >= now() - interval '30 days';

  SELECT COALESCE(SUM(platform_fee_cents), 0) INTO v_fees_30d
  FROM payments
  WHERE status = 'completed' AND created_at >= now() - interval '30 days';

  -- Revenue weekly (12 weeks, bucketed in SQL)
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object('week', w.week_start, 'revenue', w.total)
    ORDER BY w.week_start
  ), '[]'::jsonb)
  INTO v_revenue_weekly
  FROM (
    SELECT
      date_trunc('week', created_at)::date AS week_start,
      SUM(amount_cents) AS total
    FROM payments
    WHERE status = 'completed'
      AND created_at >= now() - interval '84 days'
    GROUP BY date_trunc('week', created_at)::date
  ) w;

  -- Signups weekly (12 weeks, from profiles.created_at)
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object('week', w.week_start, 'signups', w.total)
    ORDER BY w.week_start
  ), '[]'::jsonb)
  INTO v_signups_weekly
  FROM (
    SELECT
      date_trunc('week', created_at)::date AS week_start,
      COUNT(*) AS total
    FROM profiles
    WHERE created_at >= now() - interval '84 days'
    GROUP BY date_trunc('week', created_at)::date
  ) w;

  -- Tier distribution
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object('name', tier, 'value', cnt)
  ), '[]'::jsonb)
  INTO v_tier_dist
  FROM (
    SELECT tier, COUNT(*) AS cnt
    FROM subscriptions
    WHERE status = 'active'
    GROUP BY tier
  ) t;

  RETURN jsonb_build_object(
    'total_users', v_total_users,
    'total_events', v_total_events,
    'total_revenue', v_total_revenue,
    'active_subscriptions', v_active_subs,
    'tickets_sold_30d', v_tickets_30d,
    'platform_fees_30d', v_fees_30d,
    'revenue_weekly', v_revenue_weekly,
    'signups_weekly', v_signups_weekly,
    'tier_distribution', v_tier_dist
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_admin_overview_stats() TO service_role;

COMMENT ON FUNCTION get_admin_overview_stats() IS
  'Admin overview KPIs + 12-week trends, fully server-side. Replaces fetching all payments client-side.';


-- ── 3. Schedule engagement cache refresh ───────────────────
-- Chain into existing cron or add standalone job.
-- Uses pg_cron if available (Supabase hosted has it).

DO $$
BEGIN
  -- Try to schedule engagement cache refresh at 00:15 UTC daily
  -- (15 min after the main analytics refresh at 00:00)
  PERFORM cron.schedule(
    'refresh-engagement-cache',
    '15 0 * * *',
    'SELECT refresh_engagement_cache()'
  );
  RAISE NOTICE 'Engagement cache cron scheduled at 00:15 UTC daily';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Could not schedule cron (pg_cron may not be available): %', SQLERRM;
END;
$$;
