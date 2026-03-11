-- Change cash_sales_enabled default to TRUE so all new events have cash sales on automatically.
ALTER TABLE events ALTER COLUMN cash_sales_enabled SET DEFAULT TRUE;

-- Enable cash sales on all existing events that don't have it yet.
UPDATE events SET cash_sales_enabled = TRUE WHERE cash_sales_enabled = FALSE;
