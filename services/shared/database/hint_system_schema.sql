-- Hint System Database Schema
-- Adds hint tracking and scoring capabilities to existing schema

-- Track hint usage per player per phrase
CREATE TABLE hint_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID REFERENCES players(id) ON DELETE CASCADE,
    phrase_id UUID REFERENCES phrases(id) ON DELETE CASCADE,
    hint_level INTEGER NOT NULL CHECK (hint_level BETWEEN 1 AND 3),
    used_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(player_id, phrase_id, hint_level)
);

-- Create index for efficient hint lookup
CREATE INDEX idx_hint_usage_player_phrase ON hint_usage(player_id, phrase_id, hint_level);
CREATE INDEX idx_hint_usage_phrase ON hint_usage(phrase_id, hint_level);

-- Function to record hint usage
CREATE OR REPLACE FUNCTION use_hint_for_player(
    player_uuid UUID,
    phrase_uuid UUID,
    hint_level_int INTEGER
)
RETURNS BOOLEAN AS $$
DECLARE
    phrase_exists BOOLEAN;
    player_exists BOOLEAN;
    previous_hint_exists BOOLEAN;
BEGIN
    -- Validate inputs
    IF hint_level_int < 1 OR hint_level_int > 3 THEN
        RETURN FALSE;
    END IF;
    
    -- Check if phrase and player exist
    SELECT EXISTS(SELECT 1 FROM phrases WHERE id = phrase_uuid) INTO phrase_exists;
    SELECT EXISTS(SELECT 1 FROM players WHERE id = player_uuid) INTO player_exists;
    
    IF NOT phrase_exists OR NOT player_exists THEN
        RETURN FALSE;
    END IF;
    
    -- Check if previous hint level was used (except for hint level 1)
    IF hint_level_int > 1 THEN
        SELECT EXISTS(
            SELECT 1 FROM hint_usage 
            WHERE player_id = player_uuid 
                AND phrase_id = phrase_uuid 
                AND hint_level = hint_level_int - 1
        ) INTO previous_hint_exists;
        
        IF NOT previous_hint_exists THEN
            RETURN FALSE; -- Must use hints in order
        END IF;
    END IF;
    
    -- Record hint usage (ignore if already exists)
    INSERT INTO hint_usage (player_id, phrase_id, hint_level)
    VALUES (player_uuid, phrase_uuid, hint_level_int)
    ON CONFLICT (player_id, phrase_id, hint_level) DO NOTHING;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Function to get hint status for a player's phrase
CREATE OR REPLACE FUNCTION get_hint_status_for_player(
    player_uuid UUID,
    phrase_uuid UUID
)
RETURNS TABLE(
    hint_level INTEGER,
    used_at TIMESTAMP,
    next_hint_level INTEGER,
    hints_remaining INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        hu.hint_level,
        hu.used_at,
        CASE 
            WHEN MAX(hu.hint_level) < 3 THEN MAX(hu.hint_level) + 1
            ELSE NULL
        END as next_hint_level,
        CASE 
            WHEN MAX(hu.hint_level) IS NULL THEN 3
            ELSE 3 - MAX(hu.hint_level)
        END as hints_remaining
    FROM hint_usage hu
    WHERE hu.player_id = player_uuid AND hu.phrase_id = phrase_uuid
    GROUP BY hu.hint_level, hu.used_at
    ORDER BY hu.hint_level;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate score based on difficulty and hints used
CREATE OR REPLACE FUNCTION calculate_phrase_score(
    difficulty_score INTEGER,
    player_uuid UUID,
    phrase_uuid UUID
)
RETURNS INTEGER AS $$
DECLARE
    hints_used INTEGER;
    final_score NUMERIC;
BEGIN
    -- Count hints used by this player for this phrase
    SELECT COUNT(*) INTO hints_used
    FROM hint_usage
    WHERE player_id = player_uuid AND phrase_id = phrase_uuid;
    
    -- Apply scoring formula: 100%, 90%, 70%, 50%
    final_score := difficulty_score;
    
    IF hints_used >= 1 THEN
        final_score := difficulty_score * 0.90;
    END IF;
    
    IF hints_used >= 2 THEN
        final_score := difficulty_score * 0.70;
    END IF;
    
    IF hints_used >= 3 THEN
        final_score := difficulty_score * 0.50;
    END IF;
    
    -- Return rounded whole number
    RETURN ROUND(final_score);
END;
$$ LANGUAGE plpgsql;

-- Update the complete_phrase_for_player function to use hint-based scoring
CREATE OR REPLACE FUNCTION complete_phrase_for_player_with_hints(
    player_uuid UUID,
    phrase_uuid UUID,
    completion_time INTEGER DEFAULT 0
)
RETURNS TABLE(
    success BOOLEAN,
    final_score INTEGER,
    hints_used INTEGER
) AS $$
DECLARE
    phrase_exists BOOLEAN;
    player_exists BOOLEAN;
    difficulty_score INTEGER;
    calculated_score INTEGER;
    hints_count INTEGER;
BEGIN
    -- Check if phrase and player exist
    SELECT EXISTS(SELECT 1 FROM phrases WHERE id = phrase_uuid) INTO phrase_exists;
    SELECT EXISTS(SELECT 1 FROM players WHERE id = player_uuid) INTO player_exists;
    
    IF NOT phrase_exists OR NOT player_exists THEN
        RETURN QUERY SELECT FALSE, 0, 0;
        RETURN;
    END IF;
    
    -- Get phrase difficulty
    SELECT difficulty_level INTO difficulty_score FROM phrases WHERE id = phrase_uuid;
    
    -- Calculate score based on hints used
    SELECT calculate_phrase_score(difficulty_score, player_uuid, phrase_uuid) INTO calculated_score;
    
    -- Count hints used
    SELECT COUNT(*) INTO hints_count FROM hint_usage WHERE player_id = player_uuid AND phrase_id = phrase_uuid;
    
    -- Mark phrase as completed
    INSERT INTO completed_phrases (player_id, phrase_id, score, completion_time_ms)
    VALUES (player_uuid, phrase_uuid, calculated_score, completion_time)
    ON CONFLICT (player_id, phrase_id) DO NOTHING;
    
    -- Update phrase usage count
    UPDATE phrases SET usage_count = usage_count + 1 WHERE id = phrase_uuid;
    
    -- Update player completion count
    UPDATE players SET phrases_completed = phrases_completed + 1 WHERE id = player_uuid;
    
    -- Mark targeted phrase as delivered if applicable
    UPDATE player_phrases 
    SET is_delivered = true, delivered_at = CURRENT_TIMESTAMP 
    WHERE phrase_id = phrase_uuid AND target_player_id = player_uuid;
    
    RETURN QUERY SELECT TRUE, calculated_score, hints_count;
END;
$$ LANGUAGE plpgsql;