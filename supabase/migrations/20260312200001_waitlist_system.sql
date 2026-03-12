-- ============================================================
-- Waitlist System
-- ============================================================
-- Two modes:
--   'notify'   — User wants a notification when tickets become available
--   'auto_buy' — User wants automatic purchase when a ticket is available under max_price_cents
-- FIFO queue ordering by created_at.

-- ============================================================
-- TABLE: waitlist_entries
-- ============================================================
CREATE TABLE IF NOT EXISTS waitlist_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- 'notify' or 'auto_buy'
  mode TEXT NOT NULL CHECK (mode IN ('notify', 'auto_buy')),

  -- For auto_buy: maximum price user is willing to pay (in cents, includes fees)
  max_price_cents INT,

  -- For auto_buy: saved Stripe payment method ID for off-session charge
  payment_method_id TEXT,

  -- For auto_buy: Stripe customer ID (needed for off-session PaymentIntents)
  stripe_customer_id TEXT,

  -- Status lifecycle
  -- active     → waiting in queue
  -- notified   → user was notified (notify mode complete)
  -- purchased  → auto-buy succeeded
  -- cancelled  → user left the waitlist
  -- expired    → event ended or entry timed out
  -- failed     → auto-buy payment failed
  status TEXT NOT NULL DEFAULT 'active' CHECK (
    status IN ('active', 'notified', 'purchased', 'cancelled', 'expired', 'failed')
  ),

  -- Reference to the payment created by auto-buy (if any)
  payment_id UUID REFERENCES payments(id),

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- One active entry per user per event (can re-join after cancelling)
  CONSTRAINT waitlist_one_active_per_user UNIQUE (event_id, user_id)
    -- Partial unique index created below instead
);

-- Drop the table-level constraint and use a partial unique index instead
-- (only enforced for active entries)
ALTER TABLE waitlist_entries DROP CONSTRAINT IF EXISTS waitlist_one_active_per_user;

CREATE UNIQUE INDEX IF NOT EXISTS idx_waitlist_one_active_per_user
  ON waitlist_entries (event_id, user_id)
  WHERE status = 'active';

-- Index for FIFO queue processing
CREATE INDEX IF NOT EXISTS idx_waitlist_fifo
  ON waitlist_entries (event_id, created_at ASC)
  WHERE status = 'active';

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_waitlist_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_waitlist_updated_at ON waitlist_entries;
CREATE TRIGGER trg_waitlist_updated_at
  BEFORE UPDATE ON waitlist_entries
  FOR EACH ROW EXECUTE FUNCTION update_waitlist_updated_at();

-- ============================================================
-- RLS POLICIES
-- ============================================================
ALTER TABLE waitlist_entries ENABLE ROW LEVEL SECURITY;

-- Users can see their own entries
CREATE POLICY waitlist_select_own ON waitlist_entries
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Users can insert their own entries
CREATE POLICY waitlist_insert_own ON waitlist_entries
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- Users can update (cancel) their own entries
CREATE POLICY waitlist_update_own ON waitlist_entries
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid());

-- Organizers can view waitlist for their events
CREATE POLICY waitlist_select_organizer ON waitlist_entries
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM events
      WHERE events.id = waitlist_entries.event_id
      AND events.organizer_id = auth.uid()
    )
  );

-- Service role: full access (for edge functions)
CREATE POLICY waitlist_service_all ON waitlist_entries
  FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

-- ============================================================
-- SQL FUNCTIONS
-- ============================================================

-- Get the active waitlist queue for an event (FIFO order)
CREATE OR REPLACE FUNCTION get_waitlist_queue(
  p_event_id UUID,
  p_mode TEXT DEFAULT NULL,
  p_limit INT DEFAULT 50
)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  mode TEXT,
  max_price_cents INT,
  payment_method_id TEXT,
  stripe_customer_id TEXT,
  created_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    w.id,
    w.user_id,
    w.mode,
    w.max_price_cents,
    w.payment_method_id,
    w.stripe_customer_id,
    w.created_at
  FROM waitlist_entries w
  WHERE w.event_id = p_event_id
    AND w.status = 'active'
    AND (p_mode IS NULL OR w.mode = p_mode)
  ORDER BY w.created_at ASC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get waitlist count for an event (for UI display)
CREATE OR REPLACE FUNCTION get_waitlist_count(p_event_id UUID)
RETURNS JSON AS $$
DECLARE
  total_count INT;
  notify_count INT;
  auto_buy_count INT;
BEGIN
  SELECT COUNT(*) INTO total_count
  FROM waitlist_entries
  WHERE event_id = p_event_id AND status = 'active';

  SELECT COUNT(*) INTO notify_count
  FROM waitlist_entries
  WHERE event_id = p_event_id AND status = 'active' AND mode = 'notify';

  SELECT COUNT(*) INTO auto_buy_count
  FROM waitlist_entries
  WHERE event_id = p_event_id AND status = 'active' AND mode = 'auto_buy';

  RETURN json_build_object(
    'total', total_count,
    'notify', notify_count,
    'auto_buy', auto_buy_count
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Expire waitlist entries for past events (called by pg_cron)
CREATE OR REPLACE FUNCTION expire_past_event_waitlists()
RETURNS INT AS $$
DECLARE
  expired_count INT;
BEGIN
  UPDATE waitlist_entries
  SET status = 'expired'
  WHERE status = 'active'
    AND event_id IN (
      SELECT id FROM events
      WHERE date < now() - INTERVAL '1 hour'
    );

  GET DIAGNOSTICS expired_count = ROW_COUNT;
  RETURN expired_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- PAYMENTS: Add waitlist_auto_purchase type
-- ============================================================
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_type_check;
ALTER TABLE payments ADD CONSTRAINT payments_type_check
  CHECK (type IN (
    'primary_purchase', 'resale_purchase', 'vendor_pos',
    'subscription', 'favor_ticket_purchase',
    'wallet_purchase', 'wallet_top_up',
    'ach_purchase', 'waitlist_auto_purchase'
  ));

-- ============================================================
-- CRON: Expire waitlists for past events (daily at 2am UTC)
-- ============================================================
SELECT cron.schedule(
  'expire-past-event-waitlists',
  '0 2 * * *',
  $$SELECT expire_past_event_waitlists()$$
);
