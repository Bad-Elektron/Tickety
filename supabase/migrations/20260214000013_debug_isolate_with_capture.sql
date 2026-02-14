-- No-op the other two triggers, capture exact error from handle_new_user

CREATE OR REPLACE FUNCTION create_default_subscription()
RETURNS TRIGGER AS $$
BEGIN RETURN NEW; END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION check_pending_offers_on_signup()
RETURNS TRIGGER AS $$
BEGIN RETURN NEW; END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- handle_new_user with error capture into debug_errors (RLS disabled)
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    err_msg text;
    err_state text;
    err_detail text;
    err_hint text;
    err_context text;
BEGIN
    INSERT INTO public.profiles (id, display_name, email)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1)),
        NEW.email
    );
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        err_msg = MESSAGE_TEXT,
        err_state = RETURNED_SQLSTATE,
        err_detail = PG_EXCEPTION_DETAIL,
        err_hint = PG_EXCEPTION_HINT,
        err_context = PG_EXCEPTION_CONTEXT;

    INSERT INTO public.debug_errors (error_message, error_state, error_detail, error_hint)
    VALUES (err_msg, err_state, err_detail || E'\nCONTEXT: ' || err_context, err_hint);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
