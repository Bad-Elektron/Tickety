-- Add 'favor_ticket_purchase' to payments type check constraint
-- This was missing when the favor ticket system was implemented
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_type_check;
ALTER TABLE payments ADD CONSTRAINT payments_type_check
  CHECK (type IN ('primary_purchase', 'resale_purchase', 'vendor_pos', 'subscription', 'favor_ticket_purchase'));
