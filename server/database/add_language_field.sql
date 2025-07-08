-- Migration: Add language field to phrases table
-- This migration adds language support for the LanguageTile feature

-- Add language field to phrases table
ALTER TABLE phrases 
ADD COLUMN language VARCHAR(5) DEFAULT 'en' NOT NULL;

-- Add constraint to ensure only supported languages
ALTER TABLE phrases 
ADD CONSTRAINT check_language CHECK (language IN ('en', 'sv'));

-- Create index for language-based queries
CREATE INDEX idx_phrases_language ON phrases(language, is_global, is_approved);

-- Update existing phrases to have English as default language
UPDATE phrases SET language = 'en' WHERE language IS NULL;

-- Update the get_next_phrase_for_player function to include language
CREATE OR REPLACE FUNCTION get_next_phrase_for_player(player_uuid UUID)
RETURNS TABLE(
    phrase_id UUID,
    content VARCHAR(200),
    hint VARCHAR(300),
    difficulty_level INTEGER,
    phrase_type TEXT,
    priority INTEGER,
    language VARCHAR(5)
) AS $$
BEGIN
    -- First, try to get targeted phrases (highest priority)
    RETURN QUERY
    SELECT 
        p.id,
        p.content,
        p.hint,
        p.difficulty_level,
        'targeted'::TEXT,
        pp.priority,
        p.language
    FROM phrases p
    INNER JOIN player_phrases pp ON p.id = pp.phrase_id
    WHERE pp.target_player_id = player_uuid
        AND pp.is_delivered = false
        AND p.id NOT IN (SELECT phrase_id FROM completed_phrases WHERE player_id = player_uuid)
        AND p.id NOT IN (SELECT phrase_id FROM skipped_phrases WHERE player_id = player_uuid)
    ORDER BY pp.priority ASC, pp.assigned_at ASC
    LIMIT 1;
    
    -- If found, return early
    IF FOUND THEN
        RETURN;
    END IF;
    
    -- If no targeted phrases, get random global phrase
    RETURN QUERY
    SELECT 
        p.id,
        p.content,
        p.hint,
        p.difficulty_level,
        'global'::TEXT,
        1 as priority,
        p.language
    FROM phrases p
    WHERE p.is_global = true
        AND p.is_approved = true
        AND p.created_by_player_id != player_uuid  -- Don't give players their own phrases
        AND p.id NOT IN (SELECT phrase_id FROM completed_phrases WHERE player_id = player_uuid)
        AND p.id NOT IN (SELECT phrase_id FROM skipped_phrases WHERE player_id = player_uuid)
    ORDER BY RANDOM()
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Update the available_phrases_for_player view to include language
DROP VIEW IF EXISTS available_phrases_for_player;
CREATE OR REPLACE VIEW available_phrases_for_player AS
SELECT 
    p.id,
    p.content,
    p.hint,
    p.difficulty_level,
    p.is_global,
    p.created_by_player_id,
    p.language,
    CASE 
        WHEN pp.target_player_id IS NOT NULL THEN 'targeted'
        WHEN p.is_global THEN 'global'
        ELSE 'other'
    END as phrase_type,
    pp.priority,
    pp.assigned_at
FROM phrases p
LEFT JOIN player_phrases pp ON p.id = pp.phrase_id
WHERE p.is_approved = true 
    AND p.id NOT IN (
        SELECT phrase_id FROM completed_phrases 
        WHERE player_id = COALESCE(pp.target_player_id, '00000000-0000-0000-0000-000000000000'::uuid)
    )
    AND p.id NOT IN (
        SELECT phrase_id FROM skipped_phrases 
        WHERE player_id = COALESCE(pp.target_player_id, '00000000-0000-0000-0000-000000000000'::uuid)
    );