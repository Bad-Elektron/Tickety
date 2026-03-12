-- ============================================================
-- Promo Code System
-- ============================================================

-- Promo codes table
CREATE TABLE IF NOT EXISTS promo_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  discount_type TEXT NOT NULL CHECK (discount_type IN ('percentage', 'fixed')),
  discount_value INT NOT NULL CHECK (discount_value > 0),
  max_uses INT, -- NULL = unlimited
  current_uses INT NOT NULL DEFAULT 0,
  valid_from TIMESTAMPTZ,
  valid_until TIMESTAMPTZ,
  ticket_type_id UUID REFERENCES event_ticket_types(id) ON DELETE SET NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (event_id, code)
);

-- Case-insensitive lookup index
CREATE INDEX idx_promo_codes_event_upper_code ON promo_codes (event_id, UPPER(code));

-- Generic updated_at trigger function (create if not exists)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Updated_at trigger
CREATE TRIGGER set_promo_codes_updated_at
  BEFORE UPDATE ON promo_codes
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Promo code usage tracking
CREATE TABLE IF NOT EXISTS promo_code_uses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  promo_code_id UUID NOT NULL REFERENCES promo_codes(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  payment_id UUID REFERENCES payments(id) ON DELETE SET NULL,
  discount_cents INT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (promo_code_id, user_id)
);

-- Add promo_code_id to payments
ALTER TABLE payments ADD COLUMN IF NOT EXISTS promo_code_id UUID REFERENCES promo_codes(id) ON DELETE SET NULL;

-- ============================================================
-- RLS Policies
-- ============================================================

ALTER TABLE promo_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE promo_code_uses ENABLE ROW LEVEL SECURITY;

-- Organizers: full CRUD on own event codes
CREATE POLICY "Organizers can manage their event promo codes"
  ON promo_codes FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM events
      WHERE events.id = promo_codes.event_id
        AND events.organizer_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM events
      WHERE events.id = promo_codes.event_id
        AND events.organizer_id = auth.uid()
    )
  );

-- Buyers: can read active codes (for validation)
CREATE POLICY "Authenticated users can read active promo codes"
  ON promo_codes FOR SELECT
  USING (auth.role() = 'authenticated' AND is_active = true);

-- Service role: ALL
CREATE POLICY "Service role full access to promo codes"
  ON promo_codes FOR ALL
  USING (auth.role() = 'service_role');

-- Promo code uses: users see own
CREATE POLICY "Users can see their own promo code uses"
  ON promo_code_uses FOR SELECT
  USING (user_id = auth.uid());

-- Organizers can see usage of their codes
CREATE POLICY "Organizers can see usage of their event codes"
  ON promo_code_uses FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM promo_codes
      JOIN events ON events.id = promo_codes.event_id
      WHERE promo_codes.id = promo_code_uses.promo_code_id
        AND events.organizer_id = auth.uid()
    )
  );

-- Service role: ALL on uses
CREATE POLICY "Service role full access to promo code uses"
  ON promo_code_uses FOR ALL
  USING (auth.role() = 'service_role');

-- ============================================================
-- SQL Functions
-- ============================================================

-- Validate a promo code: checks active, dates, max uses, per-user use, ticket type
CREATE OR REPLACE FUNCTION validate_promo_code(
  p_event_id UUID,
  p_code TEXT,
  p_user_id UUID,
  p_base_price_cents INT,
  p_ticket_type_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_promo promo_codes%ROWTYPE;
  v_discount_cents INT;
  v_already_used BOOLEAN;
BEGIN
  -- Case-insensitive lookup
  SELECT * INTO v_promo
  FROM promo_codes
  WHERE event_id = p_event_id
    AND UPPER(code) = UPPER(p_code);

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Invalid promo code');
  END IF;

  -- Check active
  IF NOT v_promo.is_active THEN
    RETURN jsonb_build_object('valid', false, 'error', 'This code is no longer active');
  END IF;

  -- Check date range
  IF v_promo.valid_from IS NOT NULL AND now() < v_promo.valid_from THEN
    RETURN jsonb_build_object('valid', false, 'error', 'This code is not yet valid');
  END IF;

  IF v_promo.valid_until IS NOT NULL AND now() > v_promo.valid_until THEN
    RETURN jsonb_build_object('valid', false, 'error', 'This code has expired');
  END IF;

  -- Check max uses
  IF v_promo.max_uses IS NOT NULL AND v_promo.current_uses >= v_promo.max_uses THEN
    RETURN jsonb_build_object('valid', false, 'error', 'This code has reached its usage limit');
  END IF;

  -- Check per-user use
  SELECT EXISTS(
    SELECT 1 FROM promo_code_uses
    WHERE promo_code_id = v_promo.id AND user_id = p_user_id
  ) INTO v_already_used;

  IF v_already_used THEN
    RETURN jsonb_build_object('valid', false, 'error', 'You have already used this code');
  END IF;

  -- Check ticket type restriction
  IF v_promo.ticket_type_id IS NOT NULL AND p_ticket_type_id IS NOT NULL
     AND v_promo.ticket_type_id != p_ticket_type_id THEN
    RETURN jsonb_build_object('valid', false, 'error', 'This code does not apply to this ticket type');
  END IF;

  -- Calculate discount
  IF v_promo.discount_type = 'percentage' THEN
    v_discount_cents := LEAST(
      CEIL(p_base_price_cents * v_promo.discount_value / 100.0)::INT,
      p_base_price_cents
    );
  ELSE
    v_discount_cents := LEAST(v_promo.discount_value, p_base_price_cents);
  END IF;

  RETURN jsonb_build_object(
    'valid', true,
    'promo_code_id', v_promo.id,
    'discount_type', v_promo.discount_type,
    'discount_value', v_promo.discount_value,
    'discount_cents', v_discount_cents,
    'discounted_price_cents', p_base_price_cents - v_discount_cents
  );
END;
$$;

-- Redeem a promo code: insert use record, increment counter
CREATE OR REPLACE FUNCTION redeem_promo_code(
  p_promo_code_id UUID,
  p_user_id UUID,
  p_payment_id UUID,
  p_discount_cents INT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Insert use record (unique constraint prevents double-use)
  INSERT INTO promo_code_uses (promo_code_id, user_id, payment_id, discount_cents)
  VALUES (p_promo_code_id, p_user_id, p_payment_id, p_discount_cents);

  -- Increment current_uses
  UPDATE promo_codes
  SET current_uses = current_uses + 1
  WHERE id = p_promo_code_id;

  RETURN true;
EXCEPTION
  WHEN unique_violation THEN
    RETURN false;
END;
$$;
