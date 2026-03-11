-- NFT Burn & ADA Reclaim System
-- Automatically burns expired ticket NFTs and reclaims locked ADA to platform wallet.
-- Runs via daily cron job, 60 days after event ends.

-- ============================================================================
-- Extend nft_mint_queue for burn operations
-- ============================================================================

-- Add 'burn' action type
ALTER TABLE nft_mint_queue DROP CONSTRAINT IF EXISTS nft_mint_queue_action_check;
ALTER TABLE nft_mint_queue ADD CONSTRAINT nft_mint_queue_action_check
  CHECK (action IN ('mint', 'transfer', 'burn'));

-- Add 'burning' and 'burned' status values
ALTER TABLE nft_mint_queue DROP CONSTRAINT IF EXISTS nft_mint_queue_status_check;
ALTER TABLE nft_mint_queue ADD CONSTRAINT nft_mint_queue_status_check
  CHECK (status IN (
    'queued', 'minting', 'minted', 'failed', 'skipped',
    'transferring', 'transferred',
    'burning', 'burned'
  ));

-- ============================================================================
-- Tickets: burn tracking columns
-- ============================================================================

ALTER TABLE tickets ADD COLUMN IF NOT EXISTS nft_burned BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS nft_burned_at TIMESTAMPTZ;
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS nft_burn_tx_hash TEXT;

-- ============================================================================
-- Find tickets eligible for NFT burn
-- ============================================================================
-- Eligible: event ended 60+ days ago, NFT minted, not yet burned
CREATE OR REPLACE FUNCTION get_burn_eligible_tickets(grace_days INT DEFAULT 60)
RETURNS TABLE (
  ticket_id UUID,
  event_id UUID,
  nft_policy_id TEXT,
  nft_asset_id TEXT,
  ticket_number TEXT,
  buyer_address TEXT,
  user_id UUID
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    t.id AS ticket_id,
    t.event_id,
    t.nft_policy_id,
    t.nft_asset_id,
    t.ticket_number,
    uw.cardano_address AS buyer_address,
    t.user_id
  FROM tickets t
  JOIN events e ON e.id = t.event_id
  LEFT JOIN user_wallets uw ON uw.user_id = t.user_id
  WHERE t.nft_minted = TRUE
    AND t.nft_burned = FALSE
    AND e.date IS NOT NULL
    AND (e.date::TIMESTAMPTZ + (grace_days || ' days')::INTERVAL) < NOW()
    -- Don't pick up tickets already queued for burn
    AND NOT EXISTS (
      SELECT 1 FROM nft_mint_queue q
      WHERE q.ticket_id = t.id
        AND q.action = 'burn'
        AND q.status IN ('queued', 'burning')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- Enqueue burn jobs for expired NFTs
-- ============================================================================
-- Called by daily cron. Returns count of newly enqueued burns.
CREATE OR REPLACE FUNCTION enqueue_expired_nft_burns(grace_days INT DEFAULT 60)
RETURNS INT AS $$
DECLARE
  burn_count INT := 0;
  rec RECORD;
BEGIN
  FOR rec IN SELECT * FROM get_burn_eligible_tickets(grace_days) LOOP
    INSERT INTO nft_mint_queue (
      ticket_id, event_id, buyer_address, action, status
    ) VALUES (
      rec.ticket_id,
      rec.event_id,
      COALESCE(rec.buyer_address, 'no_wallet'),
      'burn',
      'queued'
    );
    burn_count := burn_count + 1;
  END LOOP;

  IF burn_count > 0 THEN
    RAISE NOTICE 'Enqueued % NFT burns', burn_count;
  END IF;

  RETURN burn_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- Schedule daily burn check (midnight UTC + 1 hour, after analytics refresh)
-- ============================================================================
SELECT cron.schedule(
  'enqueue-expired-nft-burns',
  '0 1 * * *',
  $$SELECT enqueue_expired_nft_burns(60)$$
);

-- ============================================================================
-- Index for burn lookups
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_tickets_nft_burn_eligible
  ON tickets (event_id)
  WHERE nft_minted = TRUE AND nft_burned = FALSE;

-- ============================================================================
-- Update resale trigger to also block burned NFT tickets
-- ============================================================================
CREATE OR REPLACE FUNCTION block_private_ticket_resale()
RETURNS TRIGGER AS $$
DECLARE
    t_mode TEXT;
    t_nft_minted BOOLEAN;
    t_nft_burned BOOLEAN;
    e_nft_enabled BOOLEAN;
BEGIN
    SELECT t.ticket_mode, t.nft_minted, t.nft_burned, e.nft_enabled
    INTO t_mode, t_nft_minted, t_nft_burned, e_nft_enabled
    FROM tickets t
    JOIN events e ON e.id = t.event_id
    WHERE t.id = NEW.ticket_id;

    IF t_mode = 'private' THEN
        RAISE EXCEPTION 'Private tickets cannot be listed for resale';
    END IF;

    IF t_nft_burned = true THEN
        RAISE EXCEPTION 'This ticket NFT has expired and cannot be resold';
    END IF;

    IF (t_mode = 'public' OR e_nft_enabled = true)
       AND (t_nft_minted IS NULL OR t_nft_minted = false) THEN
        RAISE EXCEPTION 'Ticket is still being prepared and cannot be resold yet';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
