-- Create event_ticket_types table for multiple ticket tiers per event
CREATE TABLE IF NOT EXISTS event_ticket_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    price_cents INTEGER NOT NULL DEFAULT 0,
    currency VARCHAR(3) NOT NULL DEFAULT 'USD',
    max_quantity INTEGER,
    sold_count INTEGER NOT NULL DEFAULT 0,
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Ensure non-negative values
    CONSTRAINT price_non_negative CHECK (price_cents >= 0),
    CONSTRAINT sold_count_non_negative CHECK (sold_count >= 0),
    CONSTRAINT max_quantity_positive CHECK (max_quantity IS NULL OR max_quantity > 0)
);

-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS idx_ticket_types_event_id ON event_ticket_types(event_id);
CREATE INDEX IF NOT EXISTS idx_ticket_types_active ON event_ticket_types(event_id, is_active) WHERE is_active = true;

-- Add ticket_type_id to tickets table
ALTER TABLE tickets
ADD COLUMN IF NOT EXISTS ticket_type_id UUID REFERENCES event_ticket_types(id);

-- Create index for ticket type lookups
CREATE INDEX IF NOT EXISTS idx_tickets_type_id ON tickets(ticket_type_id);

-- RLS Policies for event_ticket_types

-- Enable RLS
ALTER TABLE event_ticket_types ENABLE ROW LEVEL SECURITY;

-- Anyone can view active ticket types for any event
CREATE POLICY "Anyone can view active ticket types"
    ON event_ticket_types
    FOR SELECT
    USING (is_active = true);

-- Event organizers can view all ticket types for their events
CREATE POLICY "Organizers can view all ticket types for their events"
    ON event_ticket_types
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM events
            WHERE events.id = event_ticket_types.event_id
            AND events.organizer_id = auth.uid()
        )
    );

-- Event organizers can create ticket types for their events
CREATE POLICY "Organizers can create ticket types"
    ON event_ticket_types
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM events
            WHERE events.id = event_ticket_types.event_id
            AND events.organizer_id = auth.uid()
        )
    );

-- Event organizers can update ticket types for their events
CREATE POLICY "Organizers can update ticket types"
    ON event_ticket_types
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM events
            WHERE events.id = event_ticket_types.event_id
            AND events.organizer_id = auth.uid()
        )
    );

-- Event organizers can delete ticket types for their events (soft delete preferred via is_active)
CREATE POLICY "Organizers can delete ticket types"
    ON event_ticket_types
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM events
            WHERE events.id = event_ticket_types.event_id
            AND events.organizer_id = auth.uid()
        )
    );

-- Staff with seller role can view ticket types for events they're assigned to
CREATE POLICY "Staff can view ticket types for assigned events"
    ON event_ticket_types
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM event_staff
            WHERE event_staff.event_id = event_ticket_types.event_id
            AND event_staff.user_id = auth.uid()
        )
    );

-- Function to increment sold_count when a ticket is sold
CREATE OR REPLACE FUNCTION increment_ticket_type_sold_count()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.ticket_type_id IS NOT NULL THEN
        UPDATE event_ticket_types
        SET sold_count = sold_count + 1,
            updated_at = NOW()
        WHERE id = NEW.ticket_type_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to auto-increment sold_count on ticket insert
DROP TRIGGER IF EXISTS trigger_increment_ticket_type_sold ON tickets;
CREATE TRIGGER trigger_increment_ticket_type_sold
    AFTER INSERT ON tickets
    FOR EACH ROW
    EXECUTE FUNCTION increment_ticket_type_sold_count();

-- Function to decrement sold_count when a ticket is refunded/cancelled
CREATE OR REPLACE FUNCTION decrement_ticket_type_sold_count()
RETURNS TRIGGER AS $$
BEGIN
    -- Only decrement if status changed to cancelled or refunded
    IF NEW.status IN ('cancelled', 'refunded') AND OLD.status NOT IN ('cancelled', 'refunded') THEN
        IF OLD.ticket_type_id IS NOT NULL THEN
            UPDATE event_ticket_types
            SET sold_count = GREATEST(0, sold_count - 1),
                updated_at = NOW()
            WHERE id = OLD.ticket_type_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to auto-decrement sold_count on ticket status change
DROP TRIGGER IF EXISTS trigger_decrement_ticket_type_sold ON tickets;
CREATE TRIGGER trigger_decrement_ticket_type_sold
    AFTER UPDATE OF status ON tickets
    FOR EACH ROW
    EXECUTE FUNCTION decrement_ticket_type_sold_count();

-- Function to get ticket types with availability for an event
CREATE OR REPLACE FUNCTION get_event_ticket_types(p_event_id UUID)
RETURNS TABLE (
    id UUID,
    event_id UUID,
    name VARCHAR(100),
    description TEXT,
    price_cents INTEGER,
    currency VARCHAR(3),
    max_quantity INTEGER,
    sold_count INTEGER,
    sort_order INTEGER,
    is_active BOOLEAN,
    created_at TIMESTAMPTZ,
    remaining_quantity INTEGER,
    is_available BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.id,
        t.event_id,
        t.name,
        t.description,
        t.price_cents,
        t.currency,
        t.max_quantity,
        t.sold_count,
        t.sort_order,
        t.is_active,
        t.created_at,
        CASE
            WHEN t.max_quantity IS NULL THEN NULL
            ELSE t.max_quantity - t.sold_count
        END::INTEGER AS remaining_quantity,
        CASE
            WHEN NOT t.is_active THEN false
            WHEN t.max_quantity IS NULL THEN true
            ELSE t.sold_count < t.max_quantity
        END AS is_available
    FROM event_ticket_types t
    WHERE t.event_id = p_event_id
    ORDER BY t.sort_order, t.price_cents;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add updated_at trigger
CREATE OR REPLACE FUNCTION update_ticket_types_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_ticket_types_timestamp ON event_ticket_types;
CREATE TRIGGER trigger_update_ticket_types_timestamp
    BEFORE UPDATE ON event_ticket_types
    FOR EACH ROW
    EXECUTE FUNCTION update_ticket_types_updated_at();
