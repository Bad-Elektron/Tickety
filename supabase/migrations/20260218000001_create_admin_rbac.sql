-- ============================================================================
-- Admin RBAC System for Tickety Super Admin Dashboard
-- ============================================================================

-- 1a. Create app_role enum and user_roles table
-- ============================================================================

CREATE TYPE public.app_role AS ENUM ('admin', 'moderator', 'support');

CREATE TABLE public.user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role public.app_role NOT NULL,
    granted_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, role)
);

CREATE INDEX idx_user_roles_user_id ON public.user_roles(user_id);
CREATE INDEX idx_user_roles_role ON public.user_roles(role);

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- Admins can read all roles
CREATE POLICY "Admins can read all roles"
    ON public.user_roles FOR SELECT
    USING (
        (SELECT (auth.jwt() ->> 'user_role') = 'admin')
    );

-- Admins can manage roles
CREATE POLICY "Admins can insert roles"
    ON public.user_roles FOR INSERT
    WITH CHECK (
        (SELECT (auth.jwt() ->> 'user_role') = 'admin')
    );

CREATE POLICY "Admins can delete roles"
    ON public.user_roles FOR DELETE
    USING (
        (SELECT (auth.jwt() ->> 'user_role') = 'admin')
    );

-- Service role (for auth hook) bypass RLS automatically

-- 1b. Custom Access Token Hook
-- ============================================================================
-- This function is called by Supabase Auth at token issuance to inject
-- the user's highest-priority role into the JWT claims.
--
-- MANUAL STEP REQUIRED: After applying this migration, enable the hook in:
--   Supabase Dashboard > Authentication > Hooks > Custom Access Token
--   Schema: public, Function: custom_access_token_hook

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    claims jsonb;
    user_role public.app_role;
BEGIN
    claims := event -> 'claims';

    -- Get the user's highest-priority role (admin > moderator > support)
    SELECT role INTO user_role
    FROM public.user_roles
    WHERE user_id = (event ->> 'user_id')::uuid
    ORDER BY
        CASE role
            WHEN 'admin' THEN 1
            WHEN 'moderator' THEN 2
            WHEN 'support' THEN 3
        END
    LIMIT 1;

    IF user_role IS NOT NULL THEN
        claims := jsonb_set(claims, '{user_role}', to_jsonb(user_role::text));
    ELSE
        claims := claims - 'user_role';
    END IF;

    event := jsonb_set(event, '{claims}', claims);
    RETURN event;
END;
$$;

-- Grant execute to supabase_auth_admin (required for auth hooks)
GRANT EXECUTE ON FUNCTION public.custom_access_token_hook TO supabase_auth_admin;

-- Revoke from public roles (security)
REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook FROM authenticated, anon, public;

-- Grant supabase_auth_admin read access to user_roles (needed by the hook)
GRANT SELECT ON TABLE public.user_roles TO supabase_auth_admin;

-- 1c. Helper functions for RLS policies
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT coalesce((auth.jwt() ->> 'user_role') = 'admin', false);
$$;

CREATE OR REPLACE FUNCTION public.is_admin_or_moderator()
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT coalesce((auth.jwt() ->> 'user_role') IN ('admin', 'moderator'), false);
$$;

CREATE OR REPLACE FUNCTION public.is_staff_role()
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT coalesce((auth.jwt() ->> 'user_role') IN ('admin', 'moderator', 'support'), false);
$$;

-- 1d. Admin RLS policies on existing tables
-- ============================================================================
-- These are ADDITIVE policies - they won't break existing access patterns.
-- Using (SELECT func()) pattern for optimal performance (evaluated once per query).

-- profiles
CREATE POLICY "Staff can read all profiles"
    ON public.profiles FOR SELECT
    USING ((SELECT public.is_staff_role()));

CREATE POLICY "Admins can update any profile"
    ON public.profiles FOR UPDATE
    USING ((SELECT public.is_admin()))
    WITH CHECK ((SELECT public.is_admin()));

-- events
CREATE POLICY "Staff can read all events"
    ON public.events FOR SELECT
    USING ((SELECT public.is_staff_role()));

CREATE POLICY "Admins can insert events"
    ON public.events FOR INSERT
    WITH CHECK ((SELECT public.is_admin()));

CREATE POLICY "Admins can update any event"
    ON public.events FOR UPDATE
    USING ((SELECT public.is_admin()))
    WITH CHECK ((SELECT public.is_admin()));

CREATE POLICY "Admins can delete any event"
    ON public.events FOR DELETE
    USING ((SELECT public.is_admin()));

-- tickets
CREATE POLICY "Staff can read all tickets"
    ON public.tickets FOR SELECT
    USING ((SELECT public.is_staff_role()));

CREATE POLICY "Admins can update any ticket"
    ON public.tickets FOR UPDATE
    USING ((SELECT public.is_admin()))
    WITH CHECK ((SELECT public.is_admin()));

-- event_staff
CREATE POLICY "Staff can read all event_staff"
    ON public.event_staff FOR SELECT
    USING ((SELECT public.is_staff_role()));

CREATE POLICY "Admins can insert event_staff"
    ON public.event_staff FOR INSERT
    WITH CHECK ((SELECT public.is_admin()));

CREATE POLICY "Admins can update any event_staff"
    ON public.event_staff FOR UPDATE
    USING ((SELECT public.is_admin()))
    WITH CHECK ((SELECT public.is_admin()));

CREATE POLICY "Admins can delete any event_staff"
    ON public.event_staff FOR DELETE
    USING ((SELECT public.is_admin()));

-- event_ticket_types
CREATE POLICY "Staff can read all event_ticket_types"
    ON public.event_ticket_types FOR SELECT
    USING ((SELECT public.is_staff_role()));

CREATE POLICY "Admins can insert event_ticket_types"
    ON public.event_ticket_types FOR INSERT
    WITH CHECK ((SELECT public.is_admin()));

CREATE POLICY "Admins can update any event_ticket_types"
    ON public.event_ticket_types FOR UPDATE
    USING ((SELECT public.is_admin()))
    WITH CHECK ((SELECT public.is_admin()));

CREATE POLICY "Admins can delete any event_ticket_types"
    ON public.event_ticket_types FOR DELETE
    USING ((SELECT public.is_admin()));

-- payments
CREATE POLICY "Staff can read all payments"
    ON public.payments FOR SELECT
    USING ((SELECT public.is_staff_role()));

CREATE POLICY "Admins can update any payment"
    ON public.payments FOR UPDATE
    USING ((SELECT public.is_admin()))
    WITH CHECK ((SELECT public.is_admin()));

-- subscriptions
CREATE POLICY "Staff can read all subscriptions"
    ON public.subscriptions FOR SELECT
    USING ((SELECT public.is_staff_role()));

CREATE POLICY "Admins can update any subscription"
    ON public.subscriptions FOR UPDATE
    USING ((SELECT public.is_admin()))
    WITH CHECK ((SELECT public.is_admin()));

-- resale_listings
CREATE POLICY "Staff can read all resale_listings"
    ON public.resale_listings FOR SELECT
    USING ((SELECT public.is_staff_role()));

CREATE POLICY "Admin or moderator can update resale_listings"
    ON public.resale_listings FOR UPDATE
    USING ((SELECT public.is_admin_or_moderator()))
    WITH CHECK ((SELECT public.is_admin_or_moderator()));

-- seller_balances (read only for staff)
CREATE POLICY "Staff can read all seller_balances"
    ON public.seller_balances FOR SELECT
    USING ((SELECT public.is_staff_role()));

-- cash_transactions
CREATE POLICY "Staff can read all cash_transactions"
    ON public.cash_transactions FOR SELECT
    USING ((SELECT public.is_staff_role()));

CREATE POLICY "Admins can update any cash_transaction"
    ON public.cash_transactions FOR UPDATE
    USING ((SELECT public.is_admin()))
    WITH CHECK ((SELECT public.is_admin()));

-- notifications
CREATE POLICY "Staff can read all notifications"
    ON public.notifications FOR SELECT
    USING ((SELECT public.is_staff_role()));

CREATE POLICY "Admin or moderator can insert notifications"
    ON public.notifications FOR INSERT
    WITH CHECK ((SELECT public.is_admin_or_moderator()));

-- notification_preferences (read only for staff)
CREATE POLICY "Staff can read all notification_preferences"
    ON public.notification_preferences FOR SELECT
    USING ((SELECT public.is_staff_role()));

-- ticket_offers
CREATE POLICY "Staff can read all ticket_offers"
    ON public.ticket_offers FOR SELECT
    USING ((SELECT public.is_staff_role()));

CREATE POLICY "Admins can update any ticket_offer"
    ON public.ticket_offers FOR UPDATE
    USING ((SELECT public.is_admin()))
    WITH CHECK ((SELECT public.is_admin()));

-- referral_config (already publicly readable per existing policy)
CREATE POLICY "Admins can update referral_config"
    ON public.referral_config FOR UPDATE
    USING ((SELECT public.is_admin()))
    WITH CHECK ((SELECT public.is_admin()));

-- referral_earnings (read only for staff)
CREATE POLICY "Staff can read all referral_earnings"
    ON public.referral_earnings FOR SELECT
    USING ((SELECT public.is_staff_role()));

-- 1e. Admin audit log table
-- ============================================================================

CREATE TABLE public.admin_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    target_table TEXT,
    target_id TEXT,
    old_values JSONB,
    new_values JSONB,
    details JSONB,
    ip_address TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_admin_user ON public.admin_audit_log(admin_user_id);
CREATE INDEX idx_audit_action ON public.admin_audit_log(action);
CREATE INDEX idx_audit_target ON public.admin_audit_log(target_table, target_id);
CREATE INDEX idx_audit_created ON public.admin_audit_log(created_at DESC);

ALTER TABLE public.admin_audit_log ENABLE ROW LEVEL SECURITY;

-- Admins can read all audit entries
CREATE POLICY "Admins can read audit log"
    ON public.admin_audit_log FOR SELECT
    USING ((SELECT public.is_admin()));

-- Admins can insert audit entries
CREATE POLICY "Admins can insert audit log"
    ON public.admin_audit_log FOR INSERT
    WITH CHECK ((SELECT public.is_admin()));

-- Service role can also insert (for API routes)
-- service_role bypasses RLS automatically

-- ============================================================================
-- 1f. Seed first admin
-- ============================================================================
-- Run this manually after applying the migration:
--
--   INSERT INTO public.user_roles (user_id, role)
--   VALUES ('<your-user-uuid>', 'admin');
--
-- Then sign out and back in to get the updated JWT with user_role claim.
-- ============================================================================

-- REMINDER: Enable the Custom Access Token Hook in Supabase Dashboard:
--   Authentication > Hooks > Custom Access Token
--   Schema: public
--   Function: custom_access_token_hook
