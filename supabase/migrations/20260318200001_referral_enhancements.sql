-- Referral System Enhancements
-- Adds: payout tracking, channel tracking, referred-user subscription benefits

-- ============================================================
-- 1. Payout tracking on referral_earnings
-- ============================================================
ALTER TABLE referral_earnings ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;
ALTER TABLE referral_earnings ADD COLUMN IF NOT EXISTS channel TEXT;

CREATE INDEX IF NOT EXISTS idx_referral_earnings_status ON referral_earnings(status);

-- ============================================================
-- 2. Channel tracking table
-- ============================================================
CREATE TABLE IF NOT EXISTS referral_channels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id),
    channel TEXT NOT NULL,
    click_count INTEGER NOT NULL DEFAULT 0,
    signup_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, channel)
);

ALTER TABLE referral_channels ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own channel stats"
    ON referral_channels FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Service role manages channel stats"
    ON referral_channels FOR ALL
    USING (auth.uid() = user_id);

-- ============================================================
-- 3. Channel on referred user profile
-- ============================================================
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS referral_channel TEXT;

-- ============================================================
-- 4. Subscription benefit config
-- ============================================================
ALTER TABLE referral_config
    ADD COLUMN IF NOT EXISTS referee_sub_discount_percent NUMERIC(5,4) DEFAULT 0.50,
    ADD COLUMN IF NOT EXISTS referee_sub_benefit_months INTEGER DEFAULT 6;

-- ============================================================
-- 5. Coupon tracking on profiles
-- ============================================================
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS referral_coupon_id TEXT;

-- ============================================================
-- 6. Set referee_discount_percent to 5% (was 0%)
-- ============================================================
UPDATE referral_config SET referee_discount_percent = 0.05 WHERE id = 1;

-- ============================================================
-- 7. Balance query function (7-day hold for refund window)
-- ============================================================
CREATE OR REPLACE FUNCTION get_referral_balance(p_user_id UUID)
RETURNS TABLE (
    total_cents BIGINT,
    pending_cents BIGINT,
    paid_cents BIGINT,
    withdrawable_cents BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(SUM(CASE WHEN re.status != 'cancelled' THEN re.earning_cents ELSE 0 END), 0)::BIGINT AS total_cents,
        COALESCE(SUM(CASE WHEN re.status = 'pending' THEN re.earning_cents ELSE 0 END), 0)::BIGINT AS pending_cents,
        COALESCE(SUM(CASE WHEN re.status = 'paid' THEN re.earning_cents ELSE 0 END), 0)::BIGINT AS paid_cents,
        COALESCE(SUM(CASE WHEN re.status = 'pending'
            AND re.created_at < now() - INTERVAL '7 days'
            THEN re.earning_cents ELSE 0 END), 0)::BIGINT AS withdrawable_cents
    FROM referral_earnings re
    WHERE re.referrer_id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 8. FIFO payout marking
-- ============================================================
CREATE OR REPLACE FUNCTION mark_referral_earnings_paid(p_user_id UUID, p_amount_cents INTEGER)
RETURNS INTEGER AS $$
DECLARE
    v_remaining INTEGER := p_amount_cents;
    v_row RECORD;
    v_rows_updated INTEGER := 0;
BEGIN
    -- Mark oldest withdrawable rows first (FIFO)
    FOR v_row IN
        SELECT id, earning_cents
        FROM referral_earnings
        WHERE referrer_id = p_user_id
          AND status = 'pending'
          AND created_at < now() - INTERVAL '7 days'
        ORDER BY created_at ASC
    LOOP
        EXIT WHEN v_remaining <= 0;

        UPDATE referral_earnings
        SET status = 'paid', paid_at = now()
        WHERE id = v_row.id;

        v_remaining := v_remaining - v_row.earning_cents;
        v_rows_updated := v_rows_updated + 1;
    END LOOP;

    RETURN v_rows_updated;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 9. Update handle_new_user trigger for channel tracking
-- ============================================================
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_referral_code TEXT;
    v_referral_channel TEXT;
    v_referrer_id UUID;
BEGIN
    -- Check if a referral code was provided during signup
    v_referral_code := NEW.raw_user_meta_data->>'referral_code';
    v_referral_channel := NEW.raw_user_meta_data->>'referral_channel';

    IF v_referral_code IS NOT NULL AND v_referral_code != '' THEN
        -- Look up the referrer by their referral_code
        SELECT id INTO v_referrer_id
        FROM profiles
        WHERE referral_code = upper(v_referral_code);
    END IF;

    INSERT INTO profiles (id, display_name, email, referral_code, referred_by, referred_at, referral_channel)
    VALUES (
        NEW.id,
        NEW.raw_user_meta_data->>'display_name',
        NEW.email,
        upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
        v_referrer_id,
        CASE WHEN v_referrer_id IS NOT NULL THEN now() ELSE NULL END,
        CASE WHEN v_referrer_id IS NOT NULL THEN v_referral_channel ELSE NULL END
    );

    -- Increment signup_count in referral_channels if channel was provided
    IF v_referrer_id IS NOT NULL AND v_referral_channel IS NOT NULL AND v_referral_channel != '' THEN
        UPDATE referral_channels
        SET signup_count = signup_count + 1
        WHERE user_id = v_referrer_id AND channel = v_referral_channel;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 10. Dashboard RPCs
-- ============================================================

-- Top referrers leaderboard
CREATE OR REPLACE FUNCTION get_referral_leaderboard(p_limit INTEGER DEFAULT 20)
RETURNS TABLE (
    user_id UUID,
    display_name TEXT,
    total_referrals BIGINT,
    total_earnings_cents BIGINT,
    top_channel TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id AS user_id,
        p.display_name,
        (SELECT COUNT(*) FROM profiles p2 WHERE p2.referred_by = p.id) AS total_referrals,
        COALESCE(SUM(CASE WHEN re.status != 'cancelled' THEN re.earning_cents ELSE 0 END), 0)::BIGINT AS total_earnings_cents,
        (SELECT rc.channel FROM referral_channels rc
         WHERE rc.user_id = p.id ORDER BY rc.signup_count DESC LIMIT 1) AS top_channel
    FROM profiles p
    LEFT JOIN referral_earnings re ON re.referrer_id = p.id
    WHERE EXISTS (SELECT 1 FROM profiles p3 WHERE p3.referred_by = p.id)
    GROUP BY p.id, p.display_name
    ORDER BY total_earnings_cents DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Per-channel funnel stats for a user
CREATE OR REPLACE FUNCTION get_referral_funnel_stats(p_user_id UUID)
RETURNS TABLE (
    channel TEXT,
    clicks BIGINT,
    signups BIGINT,
    purchases BIGINT,
    earnings_cents BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        rc.channel,
        rc.click_count::BIGINT AS clicks,
        rc.signup_count::BIGINT AS signups,
        COALESCE((
            SELECT COUNT(DISTINCT re.payment_id)
            FROM referral_earnings re
            WHERE re.referrer_id = p_user_id
              AND re.channel = rc.channel
              AND re.status != 'cancelled'
        ), 0)::BIGINT AS purchases,
        COALESCE((
            SELECT SUM(re.earning_cents)
            FROM referral_earnings re
            WHERE re.referrer_id = p_user_id
              AND re.channel = rc.channel
              AND re.status != 'cancelled'
        ), 0)::BIGINT AS earnings_cents
    FROM referral_channels rc
    WHERE rc.user_id = p_user_id
    ORDER BY earnings_cents DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Platform-wide funnel stats (admin only, called via service_role)
CREATE OR REPLACE FUNCTION get_platform_referral_stats()
RETURNS TABLE (
    total_referrers BIGINT,
    total_referred BIGINT,
    total_earnings_cents BIGINT,
    total_paid_cents BIGINT,
    total_channels BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        (SELECT COUNT(DISTINCT referred_by) FROM profiles WHERE referred_by IS NOT NULL)::BIGINT,
        (SELECT COUNT(*) FROM profiles WHERE referred_by IS NOT NULL)::BIGINT,
        COALESCE((SELECT SUM(earning_cents) FROM referral_earnings WHERE status != 'cancelled'), 0)::BIGINT,
        COALESCE((SELECT SUM(earning_cents) FROM referral_earnings WHERE status = 'paid'), 0)::BIGINT,
        (SELECT COUNT(DISTINCT channel) FROM referral_channels)::BIGINT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_referral_balance(UUID) IS 'Returns total/pending/paid/withdrawable earnings with 7-day hold';
COMMENT ON FUNCTION mark_referral_earnings_paid(UUID, INTEGER) IS 'FIFO marks oldest pending earnings as paid up to amount';
COMMENT ON FUNCTION get_referral_leaderboard(INTEGER) IS 'Top referrers by earnings for admin dashboard';
COMMENT ON FUNCTION get_referral_funnel_stats(UUID) IS 'Per-channel click→signup→purchase→earnings funnel';
-- ============================================================
-- 11. Increment click count helper (upsert + increment)
-- ============================================================
CREATE OR REPLACE FUNCTION increment_referral_click(p_user_id UUID, p_channel TEXT)
RETURNS VOID AS $$
BEGIN
    INSERT INTO referral_channels (user_id, channel, click_count)
    VALUES (p_user_id, p_channel, 1)
    ON CONFLICT (user_id, channel)
    DO UPDATE SET click_count = referral_channels.click_count + 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON TABLE referral_channels IS 'Tracks clicks and signups per referral channel per user';
