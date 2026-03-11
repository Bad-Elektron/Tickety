-- ACH Direct Purchase
-- Allows users to pay for tickets directly from their linked bank account.
-- Tickets are issued immediately; ACH settles in 4-5 business days.
-- If ACH fails, tickets are revoked.

-- Add 'ach_purchase' to payments type constraint
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_type_check;
ALTER TABLE payments ADD CONSTRAINT payments_type_check
  CHECK (type IN (
    'primary_purchase', 'resale_purchase', 'vendor_pos',
    'subscription', 'favor_ticket_purchase',
    'wallet_purchase', 'wallet_top_up',
    'ach_purchase'
  ));
