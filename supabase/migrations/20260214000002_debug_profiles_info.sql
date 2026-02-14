-- Temporary debug function to check profiles table structure and trigger
-- DELETE THIS MIGRATION AFTER DEBUGGING

CREATE OR REPLACE FUNCTION debug_profiles_info()
RETURNS jsonb AS $$
DECLARE
    col_info jsonb;
    trigger_src text;
    constraint_info jsonb;
BEGIN
    -- Get column info
    SELECT jsonb_agg(jsonb_build_object(
        'column', column_name,
        'type', data_type,
        'nullable', is_nullable,
        'default', column_default
    ) ORDER BY ordinal_position)
    INTO col_info
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles';

    -- Get trigger function source
    SELECT prosrc INTO trigger_src
    FROM pg_proc WHERE proname = 'handle_new_user';

    -- Get check constraints
    SELECT jsonb_agg(jsonb_build_object(
        'name', conname,
        'definition', pg_get_constraintdef(oid)
    ))
    INTO constraint_info
    FROM pg_constraint
    WHERE conrelid = 'public.profiles'::regclass;

    RETURN jsonb_build_object(
        'columns', col_info,
        'trigger_source', trigger_src,
        'constraints', constraint_info
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
