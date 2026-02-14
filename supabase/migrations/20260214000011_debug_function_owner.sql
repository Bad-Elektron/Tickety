-- Check function ownership and role capabilities
CREATE OR REPLACE FUNCTION debug_function_owner()
RETURNS jsonb AS $$
DECLARE
    func_owner text;
    func_owner_is_super boolean;
    current_role_name text;
    has_bypassrls boolean;
BEGIN
    -- Who owns handle_new_user?
    SELECT rolname INTO func_owner
    FROM pg_proc p
    JOIN pg_roles r ON p.proowner = r.oid
    WHERE p.proname = 'handle_new_user';

    -- Is the owner a superuser?
    SELECT rolsuper INTO func_owner_is_super
    FROM pg_roles WHERE rolname = func_owner;

    -- Does the owner have BYPASSRLS?
    SELECT rolbypassrls INTO has_bypassrls
    FROM pg_roles WHERE rolname = func_owner;

    -- What role are we right now?
    current_role_name := current_user;

    RETURN jsonb_build_object(
        'handle_new_user_owner', func_owner,
        'owner_is_superuser', func_owner_is_super,
        'owner_has_bypassrls', has_bypassrls,
        'current_user', current_role_name,
        'session_user', session_user
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
