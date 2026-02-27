-- Add unique handle system to profiles
-- Format: lowercase_username#XXXX (4-digit random suffix)

-- 1. Create function to generate unique handles
CREATE OR REPLACE FUNCTION generate_unique_handle(p_username TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_base TEXT;
    v_handle TEXT;
    v_suffix INT;
    v_attempts INT := 0;
BEGIN
    -- Strip non-alphanumeric, lowercase
    v_base := lower(regexp_replace(COALESCE(p_username, ''), '[^a-zA-Z0-9]', '', 'g'));

    -- Fallback if empty after stripping
    IF v_base = '' THEN
        v_base := 'user';
    END IF;

    -- Try up to 50 times with 4-digit suffix
    LOOP
        v_attempts := v_attempts + 1;
        v_suffix := 1000 + floor(random() * 9000)::int; -- 1000-9999
        v_handle := v_base || '#' || v_suffix::text;

        -- Check uniqueness
        IF NOT EXISTS (SELECT 1 FROM profiles WHERE handle = v_handle) THEN
            RETURN v_handle;
        END IF;

        -- After 50 attempts, switch to 5-digit suffix for more space
        IF v_attempts >= 50 THEN
            v_suffix := 10000 + floor(random() * 90000)::int; -- 10000-99999
            v_handle := v_base || '#' || v_suffix::text;

            IF NOT EXISTS (SELECT 1 FROM profiles WHERE handle = v_handle) THEN
                RETURN v_handle;
            END IF;
        END IF;

        -- Safety valve
        IF v_attempts >= 100 THEN
            -- Last resort: use timestamp-based suffix
            v_handle := v_base || '#' || extract(epoch from now())::bigint % 100000;
            RETURN v_handle;
        END IF;
    END LOOP;
END;
$$;

-- 2. Add handle column (nullable first for backfill)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS handle TEXT;

-- 3. Backfill existing profiles
UPDATE profiles
SET handle = generate_unique_handle(COALESCE(display_name, split_part(email, '@', 1)))
WHERE handle IS NULL;

-- 4. Add constraints after backfill
ALTER TABLE profiles ALTER COLUMN handle SET NOT NULL;
ALTER TABLE profiles ADD CONSTRAINT profiles_handle_unique UNIQUE (handle);

-- 5. Create index for fast lookups
CREATE INDEX IF NOT EXISTS idx_profiles_handle ON profiles (handle);

-- 6. Update handle_new_user trigger to also generate handle
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_referral_code TEXT;
    v_referrer_id UUID;
    v_display_name TEXT;
    v_handle TEXT;
BEGIN
    v_referral_code := NEW.raw_user_meta_data->>'referral_code';
    v_display_name := COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1));
    v_handle := generate_unique_handle(v_display_name);

    IF v_referral_code IS NOT NULL AND v_referral_code != '' THEN
        SELECT id INTO v_referrer_id
        FROM profiles
        WHERE referral_code = upper(v_referral_code);
    END IF;

    INSERT INTO profiles (id, display_name, email, handle, referral_code, referred_by, referred_at)
    VALUES (
        NEW.id,
        v_display_name,
        NEW.email,
        v_handle,
        upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
        v_referrer_id,
        CASE WHEN v_referrer_id IS NOT NULL THEN now() ELSE NULL END
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        display_name = COALESCE(profiles.display_name, EXCLUDED.display_name),
        handle = COALESCE(profiles.handle, EXCLUDED.handle),
        referral_code = COALESCE(profiles.referral_code, EXCLUDED.referral_code),
        referred_by = COALESCE(profiles.referred_by, EXCLUDED.referred_by),
        referred_at = COALESCE(profiles.referred_at, EXCLUDED.referred_at);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
