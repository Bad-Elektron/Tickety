-- NFT Transfer Support: Add action column to mint queue for mint vs transfer operations
-- Also add seller_address column for tracking the previous owner on transfers

-- Add action column (mint = new NFT, transfer = resale ownership change)
ALTER TABLE nft_mint_queue ADD COLUMN IF NOT EXISTS action TEXT NOT NULL DEFAULT 'mint';
ALTER TABLE nft_mint_queue DROP CONSTRAINT IF EXISTS nft_mint_queue_action_check;
ALTER TABLE nft_mint_queue ADD CONSTRAINT nft_mint_queue_action_check
  CHECK (action IN ('mint', 'transfer'));

-- Add seller_address for transfer operations (previous owner's Cardano address)
ALTER TABLE nft_mint_queue ADD COLUMN IF NOT EXISTS seller_address TEXT;

-- Add resale_listing_id for linking transfers to resale transactions
ALTER TABLE nft_mint_queue ADD COLUMN IF NOT EXISTS resale_listing_id UUID REFERENCES resale_listings(id);

-- Update status check to include 'transferring' state
ALTER TABLE nft_mint_queue DROP CONSTRAINT IF EXISTS nft_mint_queue_status_check;
ALTER TABLE nft_mint_queue ADD CONSTRAINT nft_mint_queue_status_check
  CHECK (status IN ('queued', 'minting', 'minted', 'failed', 'skipped', 'transferring', 'transferred'));

-- Add nft_transfer_tx_hash to tickets for tracking the latest transfer
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS nft_transfer_tx_hash TEXT;

-- Index for finding queue entries by resale listing
CREATE INDEX IF NOT EXISTS idx_nft_mint_queue_resale ON nft_mint_queue(resale_listing_id) WHERE resale_listing_id IS NOT NULL;
