-- Fix: Add INSERT policy on profiles for the trigger function.
-- The profiles table has RLS enabled with SELECT and UPDATE policies
-- but NO INSERT policy. When handle_new_user runs as SECURITY DEFINER,
-- the INSERT is blocked by RLS if the function owner doesn't bypass RLS.

-- Allow inserts by the trigger (service role / function owner)
CREATE POLICY "Service role can insert profiles"
    ON profiles FOR INSERT
    WITH CHECK (true);

-- Also fix the debug_errors table
DROP POLICY IF EXISTS "Anyone can read debug" ON debug_errors;
ALTER TABLE debug_errors DISABLE ROW LEVEL SECURITY;

-- Restore handle_new_user with full referral logic
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

-- Restore create_default_subscription
CREATE OR REPLACE FUNCTION create_default_subscription()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.subscriptions (user_id, tier, status)
    VALUES (NEW.id, 'base', 'active')
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Restore check_pending_offers_on_signup
CREATE OR REPLACE FUNCTION check_pending_offers_on_signup()
RETURNS TRIGGER AS $$
DECLARE
    offer_record RECORD;
    event_record RECORD;
    organizer_record RECORD;
    price_label TEXT;
BEGIN
    FOR offer_record IN
        SELECT * FROM ticket_offers
        WHERE recipient_email = NEW.email
        AND status = 'pending'
        AND recipient_user_id IS NULL
    LOOP
        UPDATE ticket_offers
        SET recipient_user_id = NEW.id
        WHERE id = offer_record.id;

        SELECT title INTO event_record FROM events WHERE id = offer_record.event_id;
        SELECT display_name INTO organizer_record FROM profiles WHERE id = offer_record.organizer_id;

        IF offer_record.price_cents = 0 THEN
            price_label := 'Free';
        ELSE
            price_label := '$' || (offer_record.price_cents / 100.0)::NUMERIC(10,2)::TEXT;
        END IF;

        INSERT INTO notifications (user_id, type, title, body, data)
        VALUES (
            NEW.id,
            'favor_ticket_offer',
            'You received a ticket offer!',
            COALESCE(organizer_record.display_name, 'An organizer') || ' sent you a ' || price_label || ' ticket for ' || COALESCE(event_record.title, 'an event'),
            jsonb_build_object(
                'offer_id', offer_record.id,
                'event_id', offer_record.event_id,
                'event_title', event_record.title,
                'organizer_name', organizer_record.display_name,
                'price_cents', offer_record.price_cents,
                'ticket_mode', offer_record.ticket_mode,
                'message', offer_record.message
            )
        );
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
