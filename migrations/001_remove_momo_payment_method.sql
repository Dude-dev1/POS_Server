-- Migration: Remove MOBILE_MONEY Payment Method from POS System
-- Created: 2026-04-07
-- Description: Remove MoMo/MOBILE_MONEY payment method option
-- This migration:
-- 1. Converts any existing MOBILE_MONEY payments to CARD
-- 2. Removes MOBILE_MONEY from the payment_method enum
-- 3. Keeps only: CASH, CARD, STORE_BALANCE

BEGIN;

-- Step 1: Create backup of payments with MOBILE_MONEY (optional but recommended for audit)
CREATE TABLE IF NOT EXISTS payment_migration_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  original_payment_id UUID NOT NULL,
  original_method TEXT NOT NULL,
  new_method TEXT NOT NULL,
  migrated_at TIMESTAMPTZ DEFAULT NOW(),
  notes TEXT
);

-- Step 2: Log all unsupported payments (MOBILE_MONEY, PAYSTACK, etc.) before conversion
INSERT INTO payment_migration_log (original_payment_id, original_method, new_method, notes)
SELECT id, method::text, 'CARD', 'Converted from ' || method::text || ' during legacy payment removal'
FROM payments 
WHERE method::text NOT IN ('CASH', 'CARD', 'STORE_BALANCE');

-- Step 3: Create new enum type without MOBILE_MONEY
CREATE TYPE payment_method_new AS ENUM ('CASH', 'CARD', 'STORE_BALANCE');

-- Step 4: Change the type of the column AND update the data simultaneously
ALTER TABLE payments 
  ALTER COLUMN method TYPE payment_method_new 
  USING CASE 
    WHEN method::text IN ('CASH', 'CARD', 'STORE_BALANCE') THEN method::text::payment_method_new
    ELSE 'CARD'::payment_method_new
  END;

-- Step 5: Drop the old enum and rename the new one
DROP TYPE payment_method;
ALTER TYPE payment_method_new RENAME TO payment_method;

-- Step 6: Add a flag to track migrated payments
ALTER TABLE payments 
ADD COLUMN IF NOT EXISTS was_momo_payment BOOLEAN DEFAULT FALSE;

-- Step 7: Mark all migrated payments
UPDATE payments 
SET was_momo_payment = TRUE 
WHERE id IN (SELECT original_payment_id FROM payment_migration_log);

COMMIT; 

-- SELECT * FROM payment_migration_log;
-- SELECT COUNT(*) as total_momo_payments_converted FROM payments WHERE was_momo_payment = TRUE;
