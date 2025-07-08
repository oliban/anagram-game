-- Phase 4.9: Scoring System Database Schema
-- Adds leaderboard and score aggregation tables

-- Player aggregated scores table
CREATE TABLE IF NOT EXISTS player_scores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID REFERENCES players(id) ON DELETE CASCADE,
    score_period VARCHAR(10) NOT NULL CHECK (score_period IN ('daily', 'weekly', 'total')),
    period_start DATE NOT NULL,
    total_score INTEGER DEFAULT 0,
    phrases_completed INTEGER DEFAULT 0,
    avg_score DECIMAL(5,2) DEFAULT 0.00,
    rank_position INTEGER DEFAULT 0,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(player_id, score_period, period_start)
);

-- Index for efficient leaderboard queries
CREATE INDEX IF NOT EXISTS idx_player_scores_period_rank ON player_scores(score_period, rank_position);
CREATE INDEX IF NOT EXISTS idx_player_scores_player_period ON player_scores(player_id, score_period);
CREATE INDEX IF NOT EXISTS idx_player_scores_period_score ON player_scores(score_period, total_score DESC);

-- Leaderboard snapshot table for fast queries
CREATE TABLE IF NOT EXISTS leaderboards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    score_period VARCHAR(10) NOT NULL CHECK (score_period IN ('daily', 'weekly', 'total')),
    period_start DATE NOT NULL,
    player_id UUID REFERENCES players(id) ON DELETE CASCADE,
    player_name VARCHAR(50) NOT NULL,
    total_score INTEGER NOT NULL,
    phrases_completed INTEGER NOT NULL,
    rank_position INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(score_period, period_start, player_id)
);

-- Index for efficient leaderboard retrieval
CREATE INDEX IF NOT EXISTS idx_leaderboards_period_rank ON leaderboards(score_period, period_start, rank_position);
CREATE INDEX IF NOT EXISTS idx_leaderboards_period_score ON leaderboards(score_period, period_start, total_score DESC);

-- Function to calculate total score for a player
CREATE OR REPLACE FUNCTION calculate_player_total_score(player_uuid UUID)
RETURNS INTEGER AS $$
DECLARE
    total_score INTEGER := 0;
BEGIN
    SELECT COALESCE(SUM(score), 0) INTO total_score
    FROM completed_phrases 
    WHERE player_id = player_uuid;
    
    RETURN total_score;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate daily score for a player
CREATE OR REPLACE FUNCTION calculate_player_daily_score(player_uuid UUID, target_date DATE DEFAULT CURRENT_DATE)
RETURNS INTEGER AS $$
DECLARE
    daily_score INTEGER := 0;
BEGIN
    SELECT COALESCE(SUM(score), 0) INTO daily_score
    FROM completed_phrases 
    WHERE player_id = player_uuid 
    AND DATE(completed_at) = target_date;
    
    RETURN daily_score;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate weekly score for a player
CREATE OR REPLACE FUNCTION calculate_player_weekly_score(player_uuid UUID, week_start DATE DEFAULT DATE_TRUNC('week', CURRENT_DATE))
RETURNS INTEGER AS $$
DECLARE
    weekly_score INTEGER := 0;
BEGIN
    SELECT COALESCE(SUM(score), 0) INTO weekly_score
    FROM completed_phrases 
    WHERE player_id = player_uuid 
    AND DATE(completed_at) >= week_start 
    AND DATE(completed_at) < week_start + INTERVAL '7 days';
    
    RETURN weekly_score;
END;
$$ LANGUAGE plpgsql;

-- Function to update player score aggregations
CREATE OR REPLACE FUNCTION update_player_score_aggregations(player_uuid UUID)
RETURNS VOID AS $$
DECLARE
    current_date DATE := CURRENT_DATE;
    week_start DATE := DATE_TRUNC('week', CURRENT_DATE);
    daily_score INTEGER;
    weekly_score INTEGER;
    total_score INTEGER;
    daily_count INTEGER;
    weekly_count INTEGER;
    total_count INTEGER;
BEGIN
    -- Calculate scores
    daily_score := calculate_player_daily_score(player_uuid, current_date);
    weekly_score := calculate_player_weekly_score(player_uuid, week_start);
    total_score := calculate_player_total_score(player_uuid);
    
    -- Calculate phrase counts
    SELECT COUNT(*) INTO daily_count
    FROM completed_phrases 
    WHERE player_id = player_uuid AND DATE(completed_at) = current_date;
    
    SELECT COUNT(*) INTO weekly_count
    FROM completed_phrases 
    WHERE player_id = player_uuid 
    AND DATE(completed_at) >= week_start 
    AND DATE(completed_at) < week_start + INTERVAL '7 days';
    
    SELECT COUNT(*) INTO total_count
    FROM completed_phrases 
    WHERE player_id = player_uuid;
    
    -- Update or insert daily score
    INSERT INTO player_scores (player_id, score_period, period_start, total_score, phrases_completed, avg_score, last_updated)
    VALUES (player_uuid, 'daily', current_date, daily_score, daily_count, 
            CASE WHEN daily_count > 0 THEN daily_score::DECIMAL / daily_count ELSE 0 END, 
            CURRENT_TIMESTAMP)
    ON CONFLICT (player_id, score_period, period_start)
    DO UPDATE SET 
        total_score = EXCLUDED.total_score,
        phrases_completed = EXCLUDED.phrases_completed,
        avg_score = EXCLUDED.avg_score,
        last_updated = CURRENT_TIMESTAMP;
    
    -- Update or insert weekly score
    INSERT INTO player_scores (player_id, score_period, period_start, total_score, phrases_completed, avg_score, last_updated)
    VALUES (player_uuid, 'weekly', week_start, weekly_score, weekly_count,
            CASE WHEN weekly_count > 0 THEN weekly_score::DECIMAL / weekly_count ELSE 0 END,
            CURRENT_TIMESTAMP)
    ON CONFLICT (player_id, score_period, period_start)
    DO UPDATE SET 
        total_score = EXCLUDED.total_score,
        phrases_completed = EXCLUDED.phrases_completed,
        avg_score = EXCLUDED.avg_score,
        last_updated = CURRENT_TIMESTAMP;
    
    -- Update or insert total score
    INSERT INTO player_scores (player_id, score_period, period_start, total_score, phrases_completed, avg_score, last_updated)
    VALUES (player_uuid, 'total', '1970-01-01', total_score, total_count,
            CASE WHEN total_count > 0 THEN total_score::DECIMAL / total_count ELSE 0 END,
            CURRENT_TIMESTAMP)
    ON CONFLICT (player_id, score_period, period_start)
    DO UPDATE SET 
        total_score = EXCLUDED.total_score,
        phrases_completed = EXCLUDED.phrases_completed,
        avg_score = EXCLUDED.avg_score,
        last_updated = CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- Function to update leaderboard rankings
CREATE OR REPLACE FUNCTION update_leaderboard_rankings(score_period_param VARCHAR(10), period_start_param DATE DEFAULT NULL)
RETURNS INTEGER AS $$
DECLARE
    target_period_start DATE;
    records_updated INTEGER := 0;
BEGIN
    -- Set default period start based on period type
    IF period_start_param IS NULL THEN
        CASE score_period_param
            WHEN 'daily' THEN target_period_start := CURRENT_DATE;
            WHEN 'weekly' THEN target_period_start := DATE_TRUNC('week', CURRENT_DATE);
            WHEN 'total' THEN target_period_start := '1970-01-01';
            ELSE RAISE EXCEPTION 'Invalid score period: %', score_period_param;
        END CASE;
    ELSE
        target_period_start := period_start_param;
    END IF;
    
    -- Update rankings in player_scores table
    WITH ranked_players AS (
        SELECT 
            player_id,
            ROW_NUMBER() OVER (ORDER BY total_score DESC, phrases_completed DESC, last_updated ASC) as new_rank
        FROM player_scores 
        WHERE score_period = score_period_param 
        AND period_start = target_period_start
        AND total_score > 0
    )
    UPDATE player_scores 
    SET rank_position = ranked_players.new_rank
    FROM ranked_players 
    WHERE player_scores.player_id = ranked_players.player_id
    AND player_scores.score_period = score_period_param
    AND player_scores.period_start = target_period_start;
    
    GET DIAGNOSTICS records_updated = ROW_COUNT;
    
    -- Delete and recreate leaderboard snapshot
    DELETE FROM leaderboards 
    WHERE score_period = score_period_param 
    AND period_start = target_period_start;
    
    -- Insert new leaderboard snapshot
    INSERT INTO leaderboards (score_period, period_start, player_id, player_name, total_score, phrases_completed, rank_position)
    SELECT 
        ps.score_period,
        ps.period_start,
        ps.player_id,
        p.name,
        ps.total_score,
        ps.phrases_completed,
        ps.rank_position
    FROM player_scores ps
    JOIN players p ON ps.player_id = p.id
    WHERE ps.score_period = score_period_param 
    AND ps.period_start = target_period_start
    AND ps.total_score > 0
    ORDER BY ps.rank_position;
    
    RETURN records_updated;
END;
$$ LANGUAGE plpgsql;

-- Function to get player score summary
CREATE OR REPLACE FUNCTION get_player_score_summary(player_uuid UUID)
RETURNS TABLE (
    daily_score INTEGER,
    daily_rank INTEGER,
    weekly_score INTEGER,
    weekly_rank INTEGER,
    total_score INTEGER,
    total_rank INTEGER,
    total_phrases INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(daily.total_score, 0) as daily_score,
        COALESCE(daily.rank_position, 0) as daily_rank,
        COALESCE(weekly.total_score, 0) as weekly_score,
        COALESCE(weekly.rank_position, 0) as weekly_rank,
        COALESCE(total.total_score, 0) as total_score,
        COALESCE(total.rank_position, 0) as total_rank,
        COALESCE(total.phrases_completed, 0) as total_phrases
    FROM (SELECT 1) as dummy
    LEFT JOIN player_scores daily ON daily.player_id = player_uuid 
        AND daily.score_period = 'daily' 
        AND daily.period_start = CURRENT_DATE
    LEFT JOIN player_scores weekly ON weekly.player_id = player_uuid 
        AND weekly.score_period = 'weekly' 
        AND weekly.period_start = DATE_TRUNC('week', CURRENT_DATE)
    LEFT JOIN player_scores total ON total.player_id = player_uuid 
        AND total.score_period = 'total' 
        AND total.period_start = '1970-01-01';
END;
$$ LANGUAGE plpgsql;