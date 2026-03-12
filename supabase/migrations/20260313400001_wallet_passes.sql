-- ============================================================
-- Wallet Passes (Apple Wallet & Google Wallet)
-- ============================================================
-- Stores pass metadata for tickets delivered to native wallets.

-- Pass type enum
CREATE TYPE wallet_pass_type AS ENUM ('apple', 'google');

-- Main wallet passes table
CREATE TABLE IF NOT EXISTS wallet_passes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  pass_type wallet_pass_type NOT NULL,
  pass_url TEXT,
  -- Apple-specific
  apple_serial TEXT,
  apple_auth_token TEXT,
  apple_push_token TEXT,
  -- Google-specific
  google_object_id TEXT,
  -- Status
  status TEXT NOT NULL DEFAULT 'created' CHECK (status IN ('created', 'delivered', 'updated', 'expired', 'revoked')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- One pass per type per ticket
  UNIQUE (ticket_id, pass_type)
);

-- Apple webServiceURL device registrations
-- Apple pushes pass updates to registered devices
CREATE TABLE IF NOT EXISTS wallet_pass_registrations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  serial_number TEXT NOT NULL,
  device_id TEXT NOT NULL,
  push_token TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (serial_number, device_id)
);

-- Indexes
CREATE INDEX idx_wallet_passes_ticket_id ON wallet_passes(ticket_id);
CREATE INDEX idx_wallet_passes_apple_serial ON wallet_passes(apple_serial) WHERE apple_serial IS NOT NULL;
CREATE INDEX idx_wallet_pass_registrations_serial ON wallet_pass_registrations(serial_number);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_wallet_passes_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER wallet_passes_updated_at
  BEFORE UPDATE ON wallet_passes
  FOR EACH ROW
  EXECUTE FUNCTION update_wallet_passes_updated_at();

-- RLS
ALTER TABLE wallet_passes ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallet_pass_registrations ENABLE ROW LEVEL SECURITY;

-- Users can read their own passes (via ticket ownership)
CREATE POLICY wallet_passes_select ON wallet_passes
  FOR SELECT USING (
    ticket_id IN (
      SELECT id FROM tickets WHERE sold_by = auth.uid()
    )
  );

-- Service role can insert/update (edge functions)
CREATE POLICY wallet_passes_service_insert ON wallet_passes
  FOR INSERT WITH CHECK (true);

CREATE POLICY wallet_passes_service_update ON wallet_passes
  FOR UPDATE USING (true);

-- Registrations are managed by edge functions only (service role)
CREATE POLICY wallet_pass_registrations_service ON wallet_pass_registrations
  FOR ALL USING (true);
