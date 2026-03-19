-- Organizer branding: custom colors + logo for Pro/Enterprise organizers.

CREATE TABLE organizer_branding (
    organizer_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    primary_color VARCHAR(7) DEFAULT '#6366F1',
    accent_color VARCHAR(7),
    logo_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS: organizers manage their own row, anyone can read (app needs branding for display)
ALTER TABLE organizer_branding ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Organizers can manage their own branding"
    ON organizer_branding
    FOR ALL
    USING (auth.uid() = organizer_id)
    WITH CHECK (auth.uid() = organizer_id);

CREATE POLICY "Anyone can read branding"
    ON organizer_branding
    FOR SELECT
    USING (true);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_organizer_branding_updated_at
    BEFORE UPDATE ON organizer_branding
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

-- Storage bucket for organizer logos
INSERT INTO storage.buckets (id, name, public) VALUES ('organizer-logos', 'organizer-logos', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies: organizers upload to their own folder, public read
CREATE POLICY "Organizers upload their own logos"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'organizer-logos'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Organizers update their own logos"
    ON storage.objects FOR UPDATE
    USING (
        bucket_id = 'organizer-logos'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Organizers delete their own logos"
    ON storage.objects FOR DELETE
    USING (
        bucket_id = 'organizer-logos'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Public read for organizer logos"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'organizer-logos');
