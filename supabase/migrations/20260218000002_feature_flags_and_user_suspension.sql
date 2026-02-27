-- ============================================================================
-- Feature Flags + User Suspension for Admin Dashboard
-- ============================================================================

-- 1. Feature flags table
-- ============================================================================

CREATE TABLE public.feature_flags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT NOT NULL UNIQUE,
    enabled BOOLEAN NOT NULL DEFAULT false,
    description TEXT,
    updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_feature_flags_key ON public.feature_flags(key);

ALTER TABLE public.feature_flags ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can read flags (app needs to check them)
CREATE POLICY "Authenticated users can read feature flags"
    ON public.feature_flags FOR SELECT
    TO authenticated
    USING (true);

-- Only admins can modify
CREATE POLICY "Admins can insert feature flags"
    ON public.feature_flags FOR INSERT
    WITH CHECK ((SELECT public.is_admin()));

CREATE POLICY "Admins can update feature flags"
    ON public.feature_flags FOR UPDATE
    USING ((SELECT public.is_admin()))
    WITH CHECK ((SELECT public.is_admin()));

CREATE POLICY "Admins can delete feature flags"
    ON public.feature_flags FOR DELETE
    USING ((SELECT public.is_admin()));

-- Seed default feature flags
INSERT INTO public.feature_flags (key, enabled, description) VALUES
    ('referral_system', true, 'Enable the referral system for new user signups'),
    ('resale_marketplace', true, 'Enable ticket resale marketplace'),
    ('cash_sales', true, 'Allow organizers to enable cash sales at events'),
    ('public_tickets', true, 'Allow public (on-chain) ticket mode for favor tickets'),
    ('crypto_payments', false, 'Enable Cardano ADA cryptocurrency payments'),
    ('nfc_transfers', true, 'Enable NFC-based ticket transfers'),
    ('favor_tickets', true, 'Enable organizer comp/gift ticket system'),
    ('stripe_connect', true, 'Enable Stripe Connect for seller payouts');

-- 2. User suspension columns on profiles
-- ============================================================================

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS suspended_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS suspended_reason TEXT,
    ADD COLUMN IF NOT EXISTS suspended_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

-- 3. Webhook events log table (for tracking Stripe webhook processing)
-- ============================================================================

CREATE TABLE public.webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stripe_event_id TEXT NOT NULL,
    event_type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'received',  -- received, processing, succeeded, failed
    payload JSONB,
    error_message TEXT,
    processing_time_ms INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at TIMESTAMPTZ
);

CREATE INDEX idx_webhook_events_stripe_id ON public.webhook_events(stripe_event_id);
CREATE INDEX idx_webhook_events_type ON public.webhook_events(event_type);
CREATE INDEX idx_webhook_events_status ON public.webhook_events(status);
CREATE INDEX idx_webhook_events_created ON public.webhook_events(created_at DESC);

ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

-- Only staff can read webhook events
CREATE POLICY "Staff can read webhook events"
    ON public.webhook_events FOR SELECT
    USING ((SELECT public.is_staff_role()));

-- Service role inserts (from edge functions) bypass RLS automatically

-- Admin RLS for feature_flags read (staff_role already covered by authenticated policy)
-- Admin RLS for webhook_events already handled above
