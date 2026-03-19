-- Add NFC signature column to tickets table.
-- HMAC-SHA256 signature generated at ticket creation for Layer 0 NFC verification.
-- Allows ushers to verify ticket authenticity with zero network/cache.

ALTER TABLE tickets ADD COLUMN IF NOT EXISTS nfc_signature TEXT;

-- Backfill: leave NULL for existing tickets. They'll fall through to Layer 1+.
-- New tickets get signatures from the stripe-webhook on creation.
