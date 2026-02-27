-- ============================================================================
-- Admin Announcements / Broadcast System
-- ============================================================================

CREATE TABLE public.admin_announcements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    audience TEXT NOT NULL DEFAULT 'all',        -- all, organizers, subscribers
    severity TEXT NOT NULL DEFAULT 'info',       -- info, warning, critical, success
    sent_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_admin_announcements_created ON public.admin_announcements(created_at DESC);
CREATE INDEX idx_admin_announcements_audience ON public.admin_announcements(audience);

ALTER TABLE public.admin_announcements ENABLE ROW LEVEL SECURITY;

-- Only admin staff can read announcements
CREATE POLICY "Staff can read announcements"
    ON public.admin_announcements FOR SELECT
    USING ((SELECT public.is_staff_role()));

-- Only admins can create announcements
CREATE POLICY "Admins can create announcements"
    ON public.admin_announcements FOR INSERT
    WITH CHECK ((SELECT public.is_admin()));

-- Service role can update sent_count
CREATE POLICY "Admins can update announcements"
    ON public.admin_announcements FOR UPDATE
    USING ((SELECT public.is_admin()))
    WITH CHECK ((SELECT public.is_admin()));
