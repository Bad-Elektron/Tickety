-- ============================================================
-- 1. WALLET BALANCES TABLE
-- ============================================================
-- One row per user, tracks available (cleared) + pending (in-flight ACH) funds.

CREATE TABLE IF NOT EXISTS wallet_balances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  available_cents INT NOT NULL DEFAULT 0,
  pending_cents INT NOT NULL DEFAULT 0,
  currency VARCHAR(3) NOT NULL DEFAULT 'usd',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT wallet_balances_available_non_negative CHECK (available_cents >= 0),
  CONSTRAINT wallet_balances_pending_non_negative CHECK (pending_cents >= 0)
);

COMMENT ON TABLE wallet_balances IS 'Tickety Wallet balances: available (cleared ACH) + pending (in-flight) funds per user.';
COMMENT ON COLUMN wallet_balances.available_cents IS 'Cleared funds that can be spent on ticket purchases.';
COMMENT ON COLUMN wallet_balances.pending_cents IS 'ACH top-ups in flight (4-5 business days settlement).';

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_wallet_balances_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_wallet_balances_updated_at ON wallet_balances;
CREATE TRIGGER trigger_wallet_balances_updated_at
  BEFORE UPDATE ON wallet_balances
  FOR EACH ROW
  EXECUTE FUNCTION update_wallet_balances_updated_at();

CREATE INDEX IF NOT EXISTS idx_wallet_balances_user_id ON wallet_balances(user_id);

-- ============================================================
-- 2. WALLET TRANSACTIONS TABLE
-- ============================================================
-- Double-entry ledger: every credit/debit is logged.

CREATE TABLE IF NOT EXISTS wallet_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN (
    'ach_top_up',
    'ach_top_up_pending',
    'ticket_purchase',
    'refund_credit',
    'admin_adjustment'
  )),
  amount_cents INT NOT NULL, -- positive = credit, negative = debit
  fee_cents INT NOT NULL DEFAULT 0,
  balance_after_cents INT NOT NULL, -- snapshot after this transaction
  stripe_payment_intent_id VARCHAR(255),
  payment_id UUID REFERENCES payments(id) ON DELETE SET NULL,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE wallet_transactions IS 'Ledger of all wallet credits and debits.';
COMMENT ON COLUMN wallet_transactions.amount_cents IS 'Positive = credit (top-up, refund), negative = debit (purchase).';
COMMENT ON COLUMN wallet_transactions.balance_after_cents IS 'Snapshot of available_cents after this transaction.';

CREATE INDEX IF NOT EXISTS idx_wallet_transactions_user_id ON wallet_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_created_at ON wallet_transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_stripe_pi ON wallet_transactions(stripe_payment_intent_id)
  WHERE stripe_payment_intent_id IS NOT NULL;

-- ============================================================
-- 3. LINKED BANK ACCOUNTS TABLE
-- ============================================================
-- Cached info about user's linked bank accounts (from Stripe Financial Connections).

CREATE TABLE IF NOT EXISTS linked_bank_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  stripe_payment_method_id VARCHAR(255) NOT NULL UNIQUE,
  bank_name VARCHAR(255),
  last4 VARCHAR(4),
  account_type VARCHAR(20) DEFAULT 'checking' CHECK (account_type IN ('checking', 'savings')),
  is_default BOOLEAN NOT NULL DEFAULT false,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'removed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE linked_bank_accounts IS 'User linked bank accounts for ACH wallet top-ups.';

CREATE INDEX IF NOT EXISTS idx_linked_bank_accounts_user_id ON linked_bank_accounts(user_id);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_linked_bank_accounts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_linked_bank_accounts_updated_at ON linked_bank_accounts;
CREATE TRIGGER trigger_linked_bank_accounts_updated_at
  BEFORE UPDATE ON linked_bank_accounts
  FOR EACH ROW
  EXECUTE FUNCTION update_linked_bank_accounts_updated_at();

-- ============================================================
-- 4. UPDATE PAYMENTS TYPE CONSTRAINT
-- ============================================================
-- Add 'wallet_purchase' and 'wallet_top_up' to the allowed payment types.

ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_type_check;
ALTER TABLE payments ADD CONSTRAINT payments_type_check
  CHECK (type IN (
    'primary_purchase',
    'resale_purchase',
    'vendor_pos',
    'subscription',
    'favor_ticket_purchase',
    'wallet_purchase',
    'wallet_top_up'
  ));

-- ============================================================
-- 5. RLS POLICIES
-- ============================================================

-- wallet_balances: users can read their own row, service_role has full access
ALTER TABLE wallet_balances ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own wallet balance"
  ON wallet_balances FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Service role full access on wallet_balances"
  ON wallet_balances FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- wallet_transactions: users can read their own rows
ALTER TABLE wallet_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own wallet transactions"
  ON wallet_transactions FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Service role full access on wallet_transactions"
  ON wallet_transactions FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- linked_bank_accounts: users can read their own rows
ALTER TABLE linked_bank_accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own linked bank accounts"
  ON linked_bank_accounts FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Service role full access on linked_bank_accounts"
  ON linked_bank_accounts FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- ============================================================
-- 6. ATOMIC WALLET PURCHASE FUNCTION
-- ============================================================
-- Locks wallet row, validates balance, debits wallet, creates payment + tickets.
-- Prevents double-spend via SELECT ... FOR UPDATE row lock.

CREATE OR REPLACE FUNCTION purchase_from_wallet(
  p_user_id UUID,
  p_event_id UUID,
  p_quantity INT,
  p_unit_price_cents INT,
  p_platform_fee_cents INT,
  p_total_debit_cents INT,
  p_event_title TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_wallet wallet_balances%ROWTYPE;
  v_payment_id UUID;
  v_new_balance INT;
  v_ticket_ids UUID[] := '{}';
  v_ticket_id UUID;
  v_ticket_number TEXT;
  v_owner_email TEXT;
  v_owner_name TEXT;
  v_i INT;
BEGIN
  -- 1. Lock the wallet row (prevents concurrent purchases)
  SELECT * INTO v_wallet
  FROM wallet_balances
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Wallet not found for user %', p_user_id;
  END IF;

  -- 2. Validate sufficient balance
  IF v_wallet.available_cents < p_total_debit_cents THEN
    RAISE EXCEPTION 'Insufficient wallet balance: have % cents, need %',
      v_wallet.available_cents, p_total_debit_cents;
  END IF;

  -- 3. Debit wallet
  v_new_balance := v_wallet.available_cents - p_total_debit_cents;

  UPDATE wallet_balances
  SET available_cents = v_new_balance
  WHERE user_id = p_user_id;

  -- 4. Create payment record
  INSERT INTO payments (
    user_id, event_id, amount_cents, platform_fee_cents,
    currency, status, type, metadata
  ) VALUES (
    p_user_id, p_event_id, p_total_debit_cents, p_platform_fee_cents,
    'usd', 'completed', 'wallet_purchase',
    jsonb_build_object(
      'event_title', COALESCE(p_event_title, ''),
      'wallet_purchase', true,
      'quantity', p_quantity
    )
  )
  RETURNING id INTO v_payment_id;

  -- 5. Get user info for tickets
  SELECT email, display_name INTO v_owner_email, v_owner_name
  FROM profiles
  WHERE id = p_user_id;

  -- 6. Create tickets
  FOR v_i IN 1..p_quantity LOOP
    v_ticket_number := 'TKT-' ||
      SUBSTRING(EXTRACT(EPOCH FROM NOW())::TEXT FROM 8 FOR 6) || '-' ||
      LPAD(FLOOR(RANDOM() * 9999)::TEXT, 4, '0');

    INSERT INTO tickets (
      event_id, ticket_number, owner_email, owner_name,
      price_paid_cents, currency, status, sold_by
    ) VALUES (
      p_event_id, v_ticket_number, v_owner_email, v_owner_name,
      p_unit_price_cents, 'USD', 'valid', p_user_id
    )
    RETURNING id INTO v_ticket_id;

    v_ticket_ids := array_append(v_ticket_ids, v_ticket_id);
  END LOOP;

  -- 7. Link first ticket to payment
  IF array_length(v_ticket_ids, 1) > 0 THEN
    UPDATE payments SET ticket_id = v_ticket_ids[1] WHERE id = v_payment_id;
  END IF;

  -- 8. Create wallet transaction record
  INSERT INTO wallet_transactions (
    user_id, type, amount_cents, fee_cents,
    balance_after_cents, payment_id, description
  ) VALUES (
    p_user_id, 'ticket_purchase', -p_total_debit_cents, p_platform_fee_cents,
    v_new_balance, v_payment_id,
    'Purchased ' || p_quantity || 'x ticket for ' || COALESCE(p_event_title, 'event')
  );

  -- 9. Return result
  RETURN jsonb_build_object(
    'payment_id', v_payment_id,
    'ticket_ids', to_jsonb(v_ticket_ids),
    'new_balance_cents', v_new_balance,
    'tickets_created', array_length(v_ticket_ids, 1)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
