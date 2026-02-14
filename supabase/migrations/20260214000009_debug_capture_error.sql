-- Create a debug table to capture the trigger error
CREATE TABLE IF NOT EXISTS debug_errors (
    id serial PRIMARY KEY,
    error_message text,
    error_state text,
    error_detail text,
    error_hint text,
    created_at timestamptz DEFAULT now()
);

-- Allow anyone to read it
ALTER TABLE debug_errors ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read debug" ON debug_errors FOR SELECT USING (true);

-- Capture the exact error from the INSERT
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    err_msg text;
    err_state text;
    err_detail text;
    err_hint text;
BEGIN
    INSERT INTO profiles (id, email)
    VALUES (NEW.id, NEW.email);
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        err_msg = MESSAGE_TEXT,
        err_state = RETURNED_SQLSTATE,
        err_detail = PG_EXCEPTION_DETAIL,
        err_hint = PG_EXCEPTION_HINT;

    INSERT INTO debug_errors (error_message, error_state, error_detail, error_hint)
    VALUES (err_msg, err_state, err_detail, err_hint);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
