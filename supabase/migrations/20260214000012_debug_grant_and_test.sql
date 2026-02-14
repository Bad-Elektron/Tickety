-- Explicit grants + simplified function to isolate the issue

-- Ensure postgres can insert/update profiles
GRANT INSERT, UPDATE, SELECT ON profiles TO postgres;
GRANT USAGE ON SCHEMA public TO postgres;

-- Grant to supabase_auth_admin too (the role that fires auth triggers)
GRANT INSERT, UPDATE, SELECT ON profiles TO supabase_auth_admin;

-- Try with explicit search_path and no RLS issues
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.profiles (id, display_name, email)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1)),
        NEW.email
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        display_name = COALESCE(public.profiles.display_name, EXCLUDED.display_name);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
