-- Restore ONLY handle_new_user, keep others as no-op

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_referral_code TEXT;
    v_referrer_id UUID;
BEGIN
    v_referral_code := NEW.raw_user_meta_data->>'referral_code';

    IF v_referral_code IS NOT NULL AND v_referral_code != '' THEN
        SELECT id INTO v_referrer_id
        FROM profiles
        WHERE referral_code = upper(v_referral_code);
    END IF;

    INSERT INTO profiles (id, display_name, email, referral_code, referred_by, referred_at)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1)),
        NEW.email,
        upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
        v_referrer_id,
        CASE WHEN v_referrer_id IS NOT NULL THEN now() ELSE NULL END
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        display_name = COALESCE(profiles.display_name, EXCLUDED.display_name),
        referral_code = COALESCE(profiles.referral_code, EXCLUDED.referral_code),
        referred_by = COALESCE(profiles.referred_by, EXCLUDED.referred_by),
        referred_at = COALESCE(profiles.referred_at, EXCLUDED.referred_at);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
