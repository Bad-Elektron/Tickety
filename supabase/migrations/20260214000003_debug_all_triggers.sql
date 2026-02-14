-- Debug: check all triggers on auth.users and test each trigger function
-- DELETE AFTER DEBUGGING

CREATE OR REPLACE FUNCTION debug_auth_triggers()
RETURNS jsonb AS $$
DECLARE
    trigger_info jsonb;
    func_sources jsonb;
    func_rec RECORD;
BEGIN
    -- Get all triggers on auth.users
    SELECT jsonb_agg(jsonb_build_object(
        'trigger_name', t.tgname,
        'function_name', p.proname,
        'function_schema', n.nspname,
        'enabled', t.tgenabled
    ) ORDER BY t.tgname)
    INTO trigger_info
    FROM pg_trigger t
    JOIN pg_proc p ON t.tgfoid = p.oid
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE t.tgrelid = 'auth.users'::regclass
    AND NOT t.tgisinternal;

    -- Get source code of all trigger functions
    func_sources := '[]'::jsonb;
    FOR func_rec IN
        SELECT DISTINCT p.proname, n.nspname, p.prosrc
        FROM pg_trigger t
        JOIN pg_proc p ON t.tgfoid = p.oid
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE t.tgrelid = 'auth.users'::regclass
        AND NOT t.tgisinternal
    LOOP
        func_sources := func_sources || jsonb_build_array(jsonb_build_object(
            'name', func_rec.proname,
            'schema', func_rec.nspname,
            'source', func_rec.prosrc
        ));
    END LOOP;

    -- Check if ticket_offers table exists and is accessible
    RETURN jsonb_build_object(
        'triggers', trigger_info,
        'function_sources', func_sources
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
