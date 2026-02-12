-- Create ticket_offers table for favor/comp ticket system
CREATE TABLE IF NOT EXISTS ticket_offers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    organizer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    recipient_email TEXT NOT NULL,
    recipient_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    price_cents INTEGER NOT NULL DEFAULT 0,
    currency TEXT NOT NULL DEFAULT 'USD',
    ticket_mode TEXT NOT NULL DEFAULT 'private' CHECK (ticket_mode IN ('private', 'public')),
    message TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled', 'expired')),
    ticket_id UUID REFERENCES tickets(id) ON DELETE SET NULL,
    ticket_type_id UUID,
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '7 days'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_ticket_offers_recipient_email ON ticket_offers(recipient_email);
CREATE INDEX idx_ticket_offers_recipient_user_id ON ticket_offers(recipient_user_id);
CREATE INDEX idx_ticket_offers_event_id ON ticket_offers(event_id);
CREATE INDEX idx_ticket_offers_organizer_id ON ticket_offers(organizer_id);
CREATE INDEX idx_ticket_offers_status ON ticket_offers(status);

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_ticket_offers_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_ticket_offers_updated_at
    BEFORE UPDATE ON ticket_offers
    FOR EACH ROW
    EXECUTE FUNCTION update_ticket_offers_updated_at();

-- RLS
ALTER TABLE ticket_offers ENABLE ROW LEVEL SECURITY;

-- Organizers can manage their own offers
CREATE POLICY "organizers_manage_own_offers" ON ticket_offers
    FOR ALL
    USING (auth.uid() = organizer_id)
    WITH CHECK (auth.uid() = organizer_id);

-- Recipients can view offers sent to them (by user_id or email)
CREATE POLICY "recipients_view_their_offers" ON ticket_offers
    FOR SELECT
    USING (
        auth.uid() = recipient_user_id
        OR recipient_email = (SELECT email FROM auth.users WHERE id = auth.uid())
    );

-- Recipients can update offers sent to them (accept/decline)
CREATE POLICY "recipients_update_their_offers" ON ticket_offers
    FOR UPDATE
    USING (
        auth.uid() = recipient_user_id
        OR recipient_email = (SELECT email FROM auth.users WHERE id = auth.uid())
    )
    WITH CHECK (
        auth.uid() = recipient_user_id
        OR recipient_email = (SELECT email FROM auth.users WHERE id = auth.uid())
    );

-- Service role has full access (handled automatically by Supabase)

COMMENT ON TABLE ticket_offers IS 'Favor/comp ticket offers sent by organizers to recipients';
