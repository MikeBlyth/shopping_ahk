-- Add subscribable column to items table
-- Run this script to add the missing subscribable field

-- Add the column as a SMALLINT (0 = false, 1 = true)
ALTER TABLE items ADD COLUMN IF NOT EXISTS subscribable SMALLINT DEFAULT 0;

-- Update schema for clarity
COMMENT ON COLUMN items.subscribable IS 'Whether item supports subscription ordering (0=no, 1=yes)';