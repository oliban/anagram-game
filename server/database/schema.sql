-- Anagram Game Database Schema
-- This schema implements the redesigned phrase system with hints, targeting, and deduplication

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Enhanced players table
CREATE TABLE players (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50) NOT NULL UNIQUE,
    is_active BOOLEAN DEFAULT true,
    last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    phrases_completed INTEGER DEFAULT 0,
    socket_id VARCHAR(255) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Global phrase bank with hints
CREATE TABLE phrases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content VARCHAR(200) NOT NULL,
    hint VARCHAR(300) NOT NULL,
    difficulty_level INTEGER DEFAULT 1 CHECK (difficulty_level BETWEEN 1 AND 5),
    is_global BOOLEAN DEFAULT false,
    created_by_player_id UUID REFERENCES players(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_approved BOOLEAN DEFAULT false,
    usage_count INTEGER DEFAULT 0
);

-- Player-specific phrase queue for targeting
CREATE TABLE player_phrases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phrase_id UUID REFERENCES phrases(id) ON DELETE CASCADE,
    target_player_id UUID REFERENCES players(id) ON DELETE CASCADE,
    assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    priority INTEGER DEFAULT 1,
    is_delivered BOOLEAN DEFAULT false,
    delivered_at TIMESTAMP NULL
);

-- Track completed phrases per player (prevents duplicates)
CREATE TABLE completed_phrases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID REFERENCES players(id) ON DELETE CASCADE,
    phrase_id UUID REFERENCES phrases(id) ON DELETE CASCADE,
    completed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    score INTEGER DEFAULT 0,
    completion_time_ms INTEGER DEFAULT 0,
    UNIQUE(player_id, phrase_id)
);

-- Track skipped phrases per player
CREATE TABLE skipped_phrases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID REFERENCES players(id) ON DELETE CASCADE,
    phrase_id UUID REFERENCES phrases(id) ON DELETE CASCADE,
    skipped_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(player_id, phrase_id)
);

-- Offline phrase downloads for mobile clients
CREATE TABLE offline_phrases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID REFERENCES players(id) ON DELETE CASCADE,
    phrase_id UUID REFERENCES phrases(id) ON DELETE CASCADE,
    downloaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_used BOOLEAN DEFAULT false,
    used_at TIMESTAMP NULL
);

-- Performance indexes
CREATE INDEX idx_phrases_global ON phrases(is_global, is_approved) WHERE is_global = true AND is_approved = true;
CREATE INDEX idx_phrases_difficulty ON phrases(difficulty_level, is_global, is_approved);
CREATE INDEX idx_player_phrases_target ON player_phrases(target_player_id, priority, is_delivered) WHERE is_delivered = false;
CREATE INDEX idx_player_phrases_delivered ON player_phrases(target_player_id, delivered_at) WHERE is_delivered = true;
CREATE INDEX idx_completed_phrases_player ON completed_phrases(player_id, completed_at);
CREATE INDEX idx_players_active ON players(is_active, last_seen) WHERE is_active = true;
CREATE INDEX idx_skipped_phrases_player ON skipped_phrases(player_id, skipped_at);
CREATE INDEX idx_offline_phrases_player ON offline_phrases(player_id, is_used);

-- Insert default global phrases with hints from existing anagrams.txt
INSERT INTO phrases (content, hint, difficulty_level, is_global, is_approved) VALUES
('be kind', 'A simple act of compassion', 1, true, true),
('hello world', 'The classic first program greeting', 1, true, true),
('time flies', 'What happens when you''re having fun', 2, true, true),
('open door', 'Access point that''s not closed', 1, true, true),
('quick brown fox jumps', 'Famous typing test animal in motion', 3, true, true),
('make it count', 'Ensure your effort has value', 2, true, true),
('lost keys', 'Common household frustration', 2, true, true),
('coffee break', 'Mid-day caffeine pause', 2, true, true),
('bright sunny day', 'Perfect weather for outdoor activities', 2, true, true),
('code works', 'Developer''s dream outcome', 2, true, true);

-- Update usage count for initial phrases
UPDATE phrases SET usage_count = 0 WHERE is_global = true;

-- Create a view for available phrases for a player
CREATE OR REPLACE VIEW available_phrases_for_player AS
SELECT 
    p.id,
    p.content,
    p.hint,
    p.difficulty_level,
    p.is_global,
    p.created_by_player_id,
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

-- Function to get next phrase for a player
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
        p.id,
        p.content,
        p.hint,
        p.difficulty_level,
        'targeted'::TEXT,
        pp.priority
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
        1 as priority
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

-- Function to mark phrase as completed
CREATE OR REPLACE FUNCTION complete_phrase_for_player(
    player_uuid UUID,
    phrase_uuid UUID,
    completion_score INTEGER DEFAULT 0,
    completion_time INTEGER DEFAULT 0
)
RETURNS BOOLEAN AS $$
DECLARE
    phrase_exists BOOLEAN;
    player_exists BOOLEAN;
BEGIN
    -- Check if phrase and player exist
    SELECT EXISTS(SELECT 1 FROM phrases WHERE id = phrase_uuid) INTO phrase_exists;
    SELECT EXISTS(SELECT 1 FROM players WHERE id = player_uuid) INTO player_exists;
    
    IF NOT phrase_exists OR NOT player_exists THEN
        RETURN FALSE;
    END IF;
    
    -- Mark phrase as completed (ignore conflicts)
    INSERT INTO completed_phrases (player_id, phrase_id, score, completion_time_ms)
    VALUES (player_uuid, phrase_uuid, completion_score, completion_time)
    ON CONFLICT (player_id, phrase_id) DO NOTHING;
    
    -- Update phrase usage count
    UPDATE phrases SET usage_count = usage_count + 1 WHERE id = phrase_uuid;
    
    -- Update player completion count
    UPDATE players SET phrases_completed = phrases_completed + 1 WHERE id = player_uuid;
    
    -- Mark targeted phrase as delivered if applicable
    UPDATE player_phrases 
    SET is_delivered = true, delivered_at = CURRENT_TIMESTAMP 
    WHERE phrase_id = phrase_uuid AND target_player_id = player_uuid;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Function to skip phrase for player
CREATE OR REPLACE FUNCTION skip_phrase_for_player(
    player_uuid UUID,
    phrase_uuid UUID
)
RETURNS BOOLEAN AS $$
BEGIN
    -- Add to skipped phrases (ignore conflicts)
    INSERT INTO skipped_phrases (player_id, phrase_id)
    VALUES (player_uuid, phrase_uuid)
    ON CONFLICT (player_id, phrase_id) DO NOTHING;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;