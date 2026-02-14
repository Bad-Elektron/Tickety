-- Absolute bare minimum - just insert id and email, no ON CONFLICT
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO profiles (id, email)
    VALUES (NEW.id, NEW.email);
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Swallow error and log it by storing in a debug table
    RAISE LOG 'handle_new_user failed: % %', SQLERRM, SQLSTATE;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
