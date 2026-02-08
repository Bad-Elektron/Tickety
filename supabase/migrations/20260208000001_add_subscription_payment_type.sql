-- Add 'subscription' payment type and make event_id nullable for subscription payments

-- Drop and recreate the type check constraint to include 'subscription'
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_type_check;
ALTER TABLE payments ADD CONSTRAINT payments_type_check
  CHECK (type IN ('primary_purchase', 'resale_purchase', 'vendor_pos', 'subscription'));

-- Make event_id nullable (subscription payments don't have an event)
ALTER TABLE payments ALTER COLUMN event_id DROP NOT NULL;

-- Add stripe_invoice_id column for tracking subscription invoices
ALTER TABLE payments ADD COLUMN IF NOT EXISTS stripe_invoice_id VARCHAR(255);

-- Index for deduplicating subscription invoice payments
CREATE INDEX IF NOT EXISTS idx_payments_stripe_invoice_id ON payments(stripe_invoice_id) WHERE stripe_invoice_id IS NOT NULL;
