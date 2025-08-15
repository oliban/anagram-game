-- Missing Database Functions and Indexes for Staging
-- These are required for full functionality but missing from staging

-- Function: calculate_phrase_score - Core scoring with hint penalties
CREATE OR REPLACE FUNCTION calculate_phrase_score(difficulty_score integer, player_uuid uuid, phrase_uuid uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
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
$$;

-- Function: calculate_player_total_score - Aggregate player scores
CREATE OR REPLACE FUNCTION calculate_player_total_score(player_uuid uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    total_score INTEGER := 0;
BEGIN
    SELECT COALESCE(SUM(score), 0) INTO total_score
    FROM completed_phrases 
    WHERE player_id = player_uuid;
    
    RETURN total_score;
END;
$$;

-- Function: complete_phrase_for_player_with_hints - Hint-aware completion
CREATE OR REPLACE FUNCTION complete_phrase_for_player_with_hints(player_uuid uuid, phrase_uuid uuid, completion_time integer DEFAULT 0) 
RETURNS TABLE(success boolean, final_score integer, hints_used integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    phrase_exists BOOLEAN;
    player_exists BOOLEAN;
    difficulty_score INTEGER;
    hint_count INTEGER;
    calculated_score INTEGER;
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
    
    -- Count hints used
    SELECT COUNT(*) INTO hint_count FROM hint_usage 
    WHERE player_id = player_uuid AND phrase_id = phrase_uuid;
    
    -- Calculate final score with hint penalties
    calculated_score := calculate_phrase_score(difficulty_score, player_uuid, phrase_uuid);
    
    -- Insert completion record
    INSERT INTO completed_phrases (player_id, phrase_id, score, completed_at, completion_time)
    VALUES (player_uuid, phrase_uuid, calculated_score, CURRENT_TIMESTAMP, completion_time)
    ON CONFLICT (player_id, phrase_id) DO NOTHING;
    
    -- Mark as delivered if in player_phrases
    UPDATE player_phrases 
    SET is_delivered = true, delivered_at = CURRENT_TIMESTAMP
    WHERE phrase_id = phrase_uuid AND target_player_id = player_uuid;
    
    RETURN QUERY SELECT TRUE, calculated_score, hint_count;
END;
$$;

-- Function: get_player_score_summary - Dashboard data
CREATE OR REPLACE FUNCTION get_player_score_summary(player_uuid uuid) 
RETURNS TABLE(daily_score integer, daily_rank integer, weekly_score integer, weekly_rank integer, total_score integer, total_rank integer, total_phrases integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(ps_daily.total_score, 0) as daily_score,
        COALESCE(ps_daily.rank_position, 0) as daily_rank,
        COALESCE(ps_weekly.total_score, 0) as weekly_score,
        COALESCE(ps_weekly.rank_position, 0) as weekly_rank,
        COALESCE(ps_total.total_score, 0) as total_score,
        COALESCE(ps_total.rank_position, 0) as total_rank,
        COALESCE(ps_total.phrases_completed, 0) as total_phrases
    FROM players p
    LEFT JOIN player_scores ps_daily ON p.id = ps_daily.player_id AND ps_daily.score_period = 'daily' AND ps_daily.period_start = CURRENT_DATE
    LEFT JOIN player_scores ps_weekly ON p.id = ps_weekly.player_id AND ps_weekly.score_period = 'weekly' AND ps_weekly.period_start = date_trunc('week', CURRENT_DATE)::date
    LEFT JOIN player_scores ps_total ON p.id = ps_total.player_id AND ps_total.score_period = 'total' AND ps_total.period_start = '1970-01-01'
    WHERE p.id = player_uuid;
END;
$$;

-- Function: update_leaderboard_rankings - Leaderboard management
CREATE OR REPLACE FUNCTION update_leaderboard_rankings(score_period_param character varying, period_start_param date DEFAULT NULL)
RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    updated_count INTEGER := 0;
    target_period_start DATE;
BEGIN
    -- Determine period start if not provided
    IF period_start_param IS NULL THEN
        IF score_period_param = 'daily' THEN
            target_period_start := CURRENT_DATE;
        ELSIF score_period_param = 'weekly' THEN
            target_period_start := date_trunc('week', CURRENT_DATE)::date;
        ELSE
            target_period_start := '1970-01-01';
        END IF;
    ELSE
        target_period_start := period_start_param;
    END IF;
    
    -- Update rankings based on scores
    WITH ranked_scores AS (
        SELECT 
            player_id,
            total_score,
            phrases_completed,
            ROW_NUMBER() OVER (ORDER BY total_score DESC, phrases_completed DESC) as new_rank
        FROM player_scores
        WHERE score_period = score_period_param AND period_start = target_period_start
    )
    UPDATE player_scores ps
    SET rank_position = rs.new_rank,
        last_updated = CURRENT_TIMESTAMP
    FROM ranked_scores rs
    WHERE ps.player_id = rs.player_id 
      AND ps.score_period = score_period_param 
      AND ps.period_start = target_period_start;
    
    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RETURN updated_count;
END;
$$;

-- Function: update_player_score_aggregations - Score aggregation
CREATE OR REPLACE FUNCTION update_player_score_aggregations(player_uuid uuid)
RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Update daily scores
    INSERT INTO player_scores (player_id, score_period, period_start, total_score, phrases_completed)
    SELECT 
        player_uuid,
        'daily',
        CURRENT_DATE,
        COALESCE(SUM(score), 0),
        COUNT(*)
    FROM completed_phrases
    WHERE player_id = player_uuid AND DATE(completed_at) = CURRENT_DATE
    ON CONFLICT (player_id, score_period, period_start)
    DO UPDATE SET 
        total_score = EXCLUDED.total_score,
        phrases_completed = EXCLUDED.phrases_completed,
        avg_score = CASE WHEN EXCLUDED.phrases_completed > 0 THEN EXCLUDED.total_score::numeric / EXCLUDED.phrases_completed ELSE 0 END,
        last_updated = CURRENT_TIMESTAMP;
        
    -- Update weekly scores  
    INSERT INTO player_scores (player_id, score_period, period_start, total_score, phrases_completed)
    SELECT 
        player_uuid,
        'weekly', 
        date_trunc('week', CURRENT_DATE)::date,
        COALESCE(SUM(score), 0),
        COUNT(*)
    FROM completed_phrases
    WHERE player_id = player_uuid AND completed_at >= date_trunc('week', CURRENT_DATE)
    ON CONFLICT (player_id, score_period, period_start)
    DO UPDATE SET
        total_score = EXCLUDED.total_score,
        phrases_completed = EXCLUDED.phrases_completed,
        avg_score = CASE WHEN EXCLUDED.phrases_completed > 0 THEN EXCLUDED.total_score::numeric / EXCLUDED.phrases_completed ELSE 0 END,
        last_updated = CURRENT_TIMESTAMP;
        
    -- Update total scores
    INSERT INTO player_scores (player_id, score_period, period_start, total_score, phrases_completed)
    SELECT 
        player_uuid,
        'total',
        '1970-01-01',
        COALESCE(SUM(score), 0),
        COUNT(*)
    FROM completed_phrases
    WHERE player_id = player_uuid
    ON CONFLICT (player_id, score_period, period_start)
    DO UPDATE SET
        total_score = EXCLUDED.total_score,
        phrases_completed = EXCLUDED.phrases_completed,
        avg_score = CASE WHEN EXCLUDED.phrases_completed > 0 THEN EXCLUDED.total_score::numeric / EXCLUDED.phrases_completed ELSE 0 END,
        last_updated = CURRENT_TIMESTAMP;
END;
$$;

-- Function: update_player_scores_all_periods - Multi-period scoring
CREATE OR REPLACE FUNCTION update_player_scores_all_periods(player_uuid uuid)
RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Update aggregations
    PERFORM update_player_score_aggregations(player_uuid);
    
    -- Update rankings for all periods
    PERFORM update_leaderboard_rankings('daily');
    PERFORM update_leaderboard_rankings('weekly'); 
    PERFORM update_leaderboard_rankings('total');
    
    RETURN TRUE;
EXCEPTION 
    WHEN OTHERS THEN
        RETURN FALSE;
END;
$$;

-- Missing Performance Indexes
CREATE INDEX IF NOT EXISTS idx_completed_phrases_player ON completed_phrases(player_id, completed_at);
CREATE INDEX IF NOT EXISTS idx_contribution_links_expires_at ON contribution_links(expires_at);  
CREATE INDEX IF NOT EXISTS idx_contribution_links_requesting_player ON contribution_links(requesting_player_id);
CREATE INDEX IF NOT EXISTS idx_contribution_links_token ON contribution_links(token);