-- NFT Ticket System: CIP-68 minting infrastructure
-- Platform-controlled minting wallet, mint queue, and NFT tracking columns

-- ============================================================================
-- Platform Cardano Config
-- ============================================================================
-- Stores the platform minting address (mnemonic kept as Edge Function secret)
CREATE TABLE IF NOT EXISTS platform_cardano_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE platform_cardano_config ENABLE ROW LEVEL SECURITY;

-- Only service role can access platform config
CREATE POLICY "Service role only"
  ON platform_cardano_config FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- ============================================================================
-- NFT Mint Queue
-- ============================================================================
CREATE TABLE IF NOT EXISTS nft_mint_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  buyer_address TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'minting', 'minted', 'failed', 'skipped')),
  policy_id TEXT,
  reference_asset_id TEXT,
  user_asset_id TEXT,
  tx_hash TEXT,
  error_message TEXT,
  retry_count INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE nft_mint_queue ENABLE ROW LEVEL SECURITY;

-- Users can view their own mint queue entries
CREATE POLICY "Users can view own mint queue"
  ON nft_mint_queue FOR SELECT
  USING (
    buyer_address IN (
      SELECT cardano_address FROM user_wallets WHERE user_id = auth.uid()
    )
  );

-- Service role full access
CREATE POLICY "Service role full access on mint queue"
  ON nft_mint_queue FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

CREATE INDEX idx_nft_mint_queue_ticket ON nft_mint_queue(ticket_id);
CREATE INDEX idx_nft_mint_queue_status ON nft_mint_queue(status);
CREATE INDEX idx_nft_mint_queue_event ON nft_mint_queue(event_id);

-- ============================================================================
-- Tickets table: NFT tracking columns
-- ============================================================================
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS nft_minted BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS nft_asset_id TEXT;
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS nft_minted_at TIMESTAMPTZ;
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS nft_policy_id TEXT;
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS nft_tx_hash TEXT;

-- ============================================================================
-- Events table: NFT policy columns
-- ============================================================================
ALTER TABLE events ADD COLUMN IF NOT EXISTS nft_enabled BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE events ADD COLUMN IF NOT EXISTS nft_policy_id TEXT;

-- ============================================================================
-- Updated_at trigger for nft_mint_queue
-- ============================================================================
CREATE OR REPLACE FUNCTION update_nft_mint_queue_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_nft_mint_queue_updated_at
  BEFORE UPDATE ON nft_mint_queue
  FOR EACH ROW
  EXECUTE FUNCTION update_nft_mint_queue_updated_at();
