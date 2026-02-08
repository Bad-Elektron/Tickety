-- Clear old Stripe Connect account references that were created under a different platform account.
-- These need to be recreated under the correct Stripe platform.

-- Clear Connect account IDs from profiles
UPDATE profiles
SET stripe_connect_account_id = NULL
WHERE stripe_connect_account_id IS NOT NULL;

-- Clear seller balances (they reference the old Connect accounts)
DELETE FROM seller_balances
WHERE stripe_account_id IS NOT NULL;
