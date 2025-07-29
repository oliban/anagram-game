-- Migration: Remove priority field from phrases and related tables
-- Keep phrase_type for categorization but simplify by removing priority

-- Drop the priority column from phrases table
ALTER TABLE phrases DROP COLUMN IF EXISTS priority;

-- Drop the priority column from player_phrases table  
ALTER TABLE player_phrases DROP COLUMN IF EXISTS priority;

-- Update the get_next_phrase_for_player function to remove priority
DROP FUNCTION IF EXISTS get_next_phrase_for_player(uuid);

CREATE OR REPLACE FUNCTION get_next_phrase_for_player(player_uuid UUID)
RETURNS TABLE(
    phrase_id UUID,
    content VARCHAR(200),
    hint VARCHAR(300),
    difficulty_level INTEGER,
    phrase_type TEXT,
    language VARCHAR(5)
) AS $$
BEGIN
    -- First, try to get targeted phrases (no priority, just chronological)
    RETURN QUERY
    SELECT 
        p.id,
        p.content,
        p.hint,
        p.difficulty_level,
        'targeted'::TEXT,
        p.language
    FROM phrases p
    INNER JOIN player_phrases pp ON p.id = pp.phrase_id
    WHERE pp.target_player_id = player_uuid
        AND pp.is_delivered = false
        AND p.id NOT IN (SELECT phrase_id FROM completed_phrases WHERE player_id = player_uuid)
        AND p.id NOT IN (SELECT phrase_id FROM skipped_phrases WHERE player_id = player_uuid)
    ORDER BY pp.assigned_at ASC
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

-- Update the available_phrases_for_player view to remove priority
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