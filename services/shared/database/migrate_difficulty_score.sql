-- Migration to update difficulty_level to support 1-100 score range instead of 1-5
-- This migration supports the new statistical difficulty scoring system

-- Step 1: Drop the existing constraint
ALTER TABLE phrases DROP CONSTRAINT IF EXISTS phrases_difficulty_level_check;

-- Step 2: Add new constraint for 1-100 range and rename semantically
ALTER TABLE phrases ADD CONSTRAINT phrases_difficulty_level_check 
    CHECK (difficulty_level BETWEEN 1 AND 100);

-- Step 3: Update existing phrases with difficulty_level 1-5 to use new scale
-- Convert old 1-5 scale to approximate 1-100 scale for backward compatibility
UPDATE phrases 
SET difficulty_level = CASE 
    WHEN difficulty_level = 1 THEN 20   -- Very Easy: 20/100
    WHEN difficulty_level = 2 THEN 40   -- Easy: 40/100
    WHEN difficulty_level = 3 THEN 60   -- Medium: 60/100
    WHEN difficulty_level = 4 THEN 80   -- Hard: 80/100
    WHEN difficulty_level = 5 THEN 95   -- Very Hard: 95/100
    ELSE 50  -- Default to medium if invalid
END
WHERE difficulty_level BETWEEN 1 AND 5;

-- Step 4: Update index to include the new range
DROP INDEX IF EXISTS idx_phrases_difficulty;
CREATE INDEX idx_phrases_difficulty ON phrases(difficulty_level, is_global, is_approved);

-- Step 5: Add comment to document the new scoring system
COMMENT ON COLUMN phrases.difficulty_level IS 'Statistical difficulty score (1-100) calculated using letter rarity and structural complexity analysis';

-- Verify the migration
SELECT 
    COUNT(*) as total_phrases,
    MIN(difficulty_level) as min_difficulty,
    MAX(difficulty_level) as max_difficulty,
    AVG(difficulty_level) as avg_difficulty
FROM phrases;