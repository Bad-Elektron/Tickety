-- ============================================================
-- Embeddable Checkout Widget System
-- ============================================================

-- Widget API keys for organizers
CREATE TABLE widget_api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organizer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    key_prefix VARCHAR(10) NOT NULL DEFAULT 'twk_live_',
    key_hash VARCHAR(64) NOT NULL,  -- SHA-256 hash of full key
    label VARCHAR(100),
    allowed_event_ids UUID[],       -- NULL = all organizer events
    allowed_origins TEXT[],         -- CORS origins (e.g. ['https://myband.com'])
    is_active BOOLEAN NOT NULL DEFAULT true,
    rate_limit_per_minute INTEGER NOT NULL DEFAULT 100,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ
);

CREATE INDEX idx_widget_api_keys_hash ON widget_api_keys(key_hash);
CREATE INDEX idx_widget_api_keys_organizer ON widget_api_keys(organizer_id);

-- Widget customization per organizer
CREATE TABLE widget_configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organizer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    primary_color VARCHAR(7) DEFAULT '#6366F1',
    accent_color VARCHAR(7),
    font_family VARCHAR(100) DEFAULT 'Inter',
    logo_url TEXT,
    button_style VARCHAR(20) DEFAULT 'rounded',  -- rounded, square, pill
    show_powered_by BOOLEAN NOT NULL DEFAULT true,
    custom_css TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(organizer_id)
);

-- Guest checkout buyers (no full Supabase auth required)
CREATE TABLE widget_guest_buyers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL,
    name VARCHAR(255),
    stripe_customer_id VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(email)
);

-- Widget checkout sessions
CREATE TABLE widget_checkout_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    widget_key_id UUID NOT NULL REFERENCES widget_api_keys(id),
    event_id UUID NOT NULL REFERENCES events(id),
    guest_buyer_id UUID REFERENCES widget_guest_buyers(id),
    user_id UUID REFERENCES auth.users(id),
    ticket_selections JSONB NOT NULL,  -- [{ticket_type_id, quantity}]
    amount_cents INTEGER NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'usd',
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    stripe_payment_intent_id VARCHAR(255),
    promo_code_id UUID,
    promo_discount_cents INTEGER DEFAULT 0,
    metadata JSONB,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '30 minutes'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_widget_sessions_event ON widget_checkout_sessions(event_id, status);
CREATE INDEX idx_widget_sessions_stripe ON widget_checkout_sessions(stripe_payment_intent_id);

-- ── RLS ──────────────────────────────────────────────────────

ALTER TABLE widget_api_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE widget_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE widget_guest_buyers ENABLE ROW LEVEL SECURITY;
ALTER TABLE widget_checkout_sessions ENABLE ROW LEVEL SECURITY;

-- Organizers manage their own API keys
CREATE POLICY "Organizers manage own widget keys"
    ON widget_api_keys FOR ALL
    USING (organizer_id = auth.uid())
    WITH CHECK (organizer_id = auth.uid());

-- Organizers manage their own config
CREATE POLICY "Organizers manage own widget config"
    ON widget_configs FOR ALL
    USING (organizer_id = auth.uid())
    WITH CHECK (organizer_id = auth.uid());

-- Public read for widget rendering (edge functions read config to style the widget)
CREATE POLICY "Public read widget config"
    ON widget_configs FOR SELECT
    USING (true);

-- Guest buyers: service role only (no direct user access)
-- No public policies — only service role key can access

-- Checkout sessions: service role only
-- No public policies — only edge functions with service role access

-- ── Cleanup cron ─────────────────────────────────────────────

-- Expire stale checkout sessions every 15 minutes
SELECT cron.schedule(
    'expire-widget-sessions',
    '*/15 * * * *',
    $$
    UPDATE widget_checkout_sessions
    SET status = 'expired', updated_at = NOW()
    WHERE status = 'pending'
      AND expires_at < NOW();
    $$
);
