-- Server-side mnemonic storage for auto-created Cardano wallets.
-- Each user gets one wallet, auto-created on first wallet screen visit.
-- RLS ensures users can only access their own wallet data.

CREATE TABLE user_wallets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  mnemonic TEXT NOT NULL,
  cardano_address TEXT NOT NULL,
  network TEXT NOT NULL DEFAULT 'preview',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE user_wallets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own wallet"
  ON user_wallets FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own wallet"
  ON user_wallets FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Service role full access"
  ON user_wallets FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

CREATE INDEX idx_user_wallets_user_id ON user_wallets(user_id);
