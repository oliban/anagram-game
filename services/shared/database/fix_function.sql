DROP FUNCTION IF EXISTS get_next_phrase_for_player(UUID);

CREATE OR REPLACE FUNCTION get_next_phrase_for_player(player_uuid UUID)
RETURNS TABLE(
    phrase_id UUID,
    content VARCHAR(200),
    hint VARCHAR(300),
    difficulty_level INTEGER,
    phrase_type TEXT,
    priority INTEGER
) AS $$
BEGIN
    -- First, try to get targeted phrases (highest priority)
    RETURN QUERY
    SELECT 
        p.id as phrase_id,
        p.content,
        p.hint,
        p.difficulty_level,
        'targeted'::TEXT as phrase_type,
        pp.priority
    FROM phrases p
    INNER JOIN player_phrases pp ON p.id = pp.phrase_id
    WHERE pp.target_player_id = player_uuid
        AND pp.is_delivered = false
        AND p.id NOT IN (SELECT cp.phrase_id FROM completed_phrases cp WHERE cp.player_id = player_uuid)
        AND p.id NOT IN (SELECT sp.phrase_id FROM skipped_phrases sp WHERE sp.player_id = player_uuid)
    ORDER BY pp.priority ASC, pp.assigned_at ASC
    LIMIT 1;
    
    -- If found, return early
    IF FOUND THEN
        RETURN;
    END IF;
    
    -- If no targeted phrases, get random global phrase
    RETURN QUERY
    SELECT 
        p.id as phrase_id,
        p.content,
        p.hint,
        p.difficulty_level,
        'global'::TEXT as phrase_type,
        1 as priority
    FROM phrases p
    WHERE p.is_global = true
        AND p.is_approved = true
        AND (p.created_by_player_id <> player_uuid OR p.created_by_player_id IS NULL)
        AND p.id NOT IN (SELECT cp.phrase_id FROM completed_phrases cp WHERE cp.player_id = player_uuid)
        AND p.id NOT IN (SELECT sp.phrase_id FROM skipped_phrases sp WHERE sp.player_id = player_uuid)
    ORDER BY RANDOM()
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;