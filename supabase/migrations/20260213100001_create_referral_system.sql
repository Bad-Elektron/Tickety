-- Referral System Migration
-- Users share referral codes. New users who sign up with a code get discounted
-- platform fees, and the referrer earns a share of platform revenue.

-- ============================================================
-- 1a. referral_config (singleton for global settings)
-- ============================================================
CREATE TABLE referral_config (
    id INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    referee_discount_percent NUMERIC(5,4) NOT NULL DEFAULT 0.00,
    referrer_revenue_share_percent NUMERIC(5,4) NOT NULL DEFAULT 0.10,
    benefit_duration_days INTEGER NOT NULL DEFAULT 365,
    referral_enabled BOOLEAN NOT NULL DEFAULT true,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Seed with defaults
INSERT INTO referral_config (id) VALUES (1);

-- RLS: everyone can read, only service_role can update
ALTER TABLE referral_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read referral config"
    ON referral_config FOR SELECT
    USING (true);

-- ============================================================
-- 1b. Add columns to profiles
-- ============================================================
ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS referral_code VARCHAR(8) UNIQUE,
    ADD COLUMN IF NOT EXISTS referred_by UUID REFERENCES profiles(id),
    ADD COLUMN IF NOT EXISTS referred_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_profiles_referral_code ON profiles(referral_code);
CREATE INDEX IF NOT EXISTS idx_profiles_referred_by ON profiles(referred_by);

-- ============================================================
-- 1c. referral_earnings table (append-only audit trail)
-- ============================================================
CREATE TABLE referral_earnings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_id UUID NOT NULL REFERENCES profiles(id),
    referred_user_id UUID NOT NULL REFERENCES profiles(id),
    payment_id UUID REFERENCES payments(id),
    platform_fee_cents INTEGER NOT NULL DEFAULT 0,
    discount_cents INTEGER NOT NULL DEFAULT 0,
    earning_cents INTEGER NOT NULL DEFAULT 0,
    discount_percent_applied NUMERIC(5,4) NOT NULL DEFAULT 0,
    revenue_share_percent_applied NUMERIC(5,4) NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_referral_earnings_referrer ON referral_earnings(referrer_id);
CREATE INDEX IF NOT EXISTS idx_referral_earnings_referred ON referral_earnings(referred_user_id);
CREATE INDEX IF NOT EXISTS idx_referral_earnings_payment ON referral_earnings(payment_id);

-- RLS: users can view own earnings (as referrer or referee)
ALTER TABLE referral_earnings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own referral earnings"
    ON referral_earnings FOR SELECT
    USING (
        auth.uid() = referrer_id
        OR auth.uid() = referred_user_id
    );

-- ============================================================
-- 1d. Backfill referral codes for existing profiles
-- ============================================================
UPDATE profiles
SET referral_code = upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))
WHERE referral_code IS NULL;

-- ============================================================
-- 1e. get_referral_discount_info RPC function
-- ============================================================
CREATE OR REPLACE FUNCTION get_referral_discount_info(p_user_id UUID)
RETURNS TABLE (
    has_referral BOOLEAN,
    referrer_id UUID,
    discount_percent NUMERIC(5,4),
    revenue_share_percent NUMERIC(5,4),
    referral_active BOOLEAN
) AS $$
DECLARE
    v_referred_by UUID;
    v_referred_at TIMESTAMPTZ;
    v_config referral_config%ROWTYPE;
    v_active BOOLEAN;
BEGIN
    -- Get user's referral info
    SELECT p.referred_by, p.referred_at
    INTO v_referred_by, v_referred_at
    FROM profiles p
    WHERE p.id = p_user_id;

    -- If no referral, return defaults
    IF v_referred_by IS NULL THEN
        RETURN QUERY SELECT false, NULL::UUID, 0::NUMERIC(5,4), 0::NUMERIC(5,4), false;
        RETURN;
    END IF;

    -- Get config
    SELECT * INTO v_config FROM referral_config WHERE id = 1;

    -- Check if referral is still active (within benefit window and enabled)
    v_active := v_config.referral_enabled
        AND v_referred_at IS NOT NULL
        AND (now() - v_referred_at) < (v_config.benefit_duration_days || ' days')::INTERVAL;

    RETURN QUERY SELECT
        true,
        v_referred_by,
        CASE WHEN v_active THEN v_config.referee_discount_percent ELSE 0::NUMERIC(5,4) END,
        CASE WHEN v_active THEN v_config.referrer_revenue_share_percent ELSE 0::NUMERIC(5,4) END,
        v_active;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 1f. Update handle_new_user trigger to generate referral codes
--     and process referral_code from signup metadata
-- ============================================================
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_referral_code TEXT;
    v_referrer_id UUID;
BEGIN
    -- Check if a referral code was provided during signup
    v_referral_code := NEW.raw_user_meta_data->>'referral_code';

    IF v_referral_code IS NOT NULL AND v_referral_code != '' THEN
        -- Look up the referrer by their referral_code
        SELECT id INTO v_referrer_id
        FROM profiles
        WHERE referral_code = upper(v_referral_code);
    END IF;

    INSERT INTO profiles (id, display_name, email, referral_code, referred_by, referred_at)
    VALUES (
        NEW.id,
        NEW.raw_user_meta_data->>'display_name',
        NEW.email,
        upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
        v_referrer_id,
        CASE WHEN v_referrer_id IS NOT NULL THEN now() ELSE NULL END
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON TABLE referral_config IS 'Global referral system configuration (singleton)';
COMMENT ON TABLE referral_earnings IS 'Audit trail of referral earnings from platform fees';
COMMENT ON FUNCTION get_referral_discount_info(UUID) IS 'Returns referral discount info for a user, used by edge functions';
