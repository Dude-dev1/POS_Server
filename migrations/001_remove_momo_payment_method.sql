-- Migration: Remove MOBILE_MONEY Payment Method from POS System
-- Created: 2026-04-07
-- Description: Remove MoMo/MOBILE_MONEY payment method option
-- This migration:
-- 1. Converts any existing MOBILE_MONEY payments to CARD
-- 2. Removes MOBILE_MONEY from the payment_method enum
-- 3. Keeps only: CASH, CARD, STORE_BALANCE

BEGIN;

-- Step 1: Create backup of payments with MOBILE_MONEY (optional but recommended for audit)
-- This records which payments were migrated
CREATE TABLE IF NOT EXISTS payment_migration_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  original_payment_id UUID NOT NULL,
  original_method TEXT NOT NULL,
  new_method TEXT NOT NULL,
  migrated_at TIMESTAMPTZ DEFAULT NOW(),
  notes TEXT
);

-- Step 2: Log all MOBILE_MONEY payments before conversion
INSERT INTO payment_migration_log (original_payment_id, original_method, new_method, notes)
SELECT id, 'MOBILE_MONEY', 'CARD', 'Converted from MoMo during MOBILE_MONEY removal'
FROM payments 
WHERE method::text = 'MOBILE_MONEY';

-- Step 3: Create new enum type without MOBILE_MONEY
CREATE TYPE payment_method_new AS ENUM ('CASH', 'CARD', 'STORE_BALANCE');

-- Step 4: Convert MOBILE_MONEY payments to CARD
UPDATE payments 
SET method = 'CARD'::payment_method_new 
WHERE method::text = 'MOBILE_MONEY';

-- Step 5: Alter the payments table column type
ALTER TABLE payments 
ALTER COLUMN method TYPE payment_method_new USING method::text::payment_method_new;

-- Step 6: Drop old enum and rename new one
DROP TYPE payment_method;
ALTER TYPE payment_method_new RENAME TO payment_method;

-- Step 7: Add a flag to track migrated payments (optional but useful for reporting)
ALTER TABLE payments 
ADD COLUMN IF NOT EXISTS was_momo_payment BOOLEAN DEFAULT FALSE;

-- Mark all migrated payments
UPDATE payments 
SET was_momo_payment = TRUE 
WHERE id IN (SELECT original_payment_id FROM payment_migration_log);

COMMIT;

-- Rollback instructions (if needed):
-- You will need to manually restore the MOBILE_MONEY enum value
-- and restore the original payment method values from the payment_migration_log table.
--
-- Query to check migrated payments:
-- SELECT * FROM payment_migration_log;
-- SELECT COUNT(*) as total_momo_payments_converted FROM payments WHERE was_momo_payment = TRUE;
