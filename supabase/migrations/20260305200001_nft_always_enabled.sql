-- Make NFT tickets always enabled by default
ALTER TABLE events ALTER COLUMN nft_enabled SET DEFAULT TRUE;

-- Enable NFTs for all existing events
UPDATE events SET nft_enabled = TRUE WHERE nft_enabled = FALSE;
