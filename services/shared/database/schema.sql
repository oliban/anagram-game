-- Anagram Game Database Schema
-- This schema implements the redesigned phrase system with hints, targeting, and deduplication

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Enhanced players table
CREATE TABLE players (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50) NOT NULL,
    device_id VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT true,
    last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    phrases_completed INTEGER DEFAULT 0,
    socket_id VARCHAR(255) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_player_name UNIQUE (name),
    CONSTRAINT players_name_device_key UNIQUE (name, device_id)
);

-- Global phrase bank with hints
CREATE TABLE phrases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content VARCHAR(200) NOT NULL,
    hint VARCHAR(300) NOT NULL,
    difficulty_level INTEGER DEFAULT 1,
    is_global BOOLEAN DEFAULT false,
    created_by_player_id UUID REFERENCES players(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_approved BOOLEAN DEFAULT false,
    usage_count INTEGER DEFAULT 0,
    phrase_type VARCHAR(50) DEFAULT 'custom',
    language VARCHAR(10) DEFAULT 'en',
    theme VARCHAR(100),
    contributor_name VARCHAR(100),
    source VARCHAR(20) DEFAULT 'app',
    contribution_link_id UUID,
    sender_name VARCHAR(100)
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

-- Contribution links for tracking external phrase contributors
CREATE TABLE contribution_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contributor_name VARCHAR(100) NOT NULL,
    link_code VARCHAR(50) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT true,
    phrases_contributed INTEGER DEFAULT 0
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

-- Emoji Collection System Schema
-- Adds collectable emoji tracking with rarity system

-- Emoji master database with rarity system
CREATE TABLE emoji_catalog (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    emoji_character VARCHAR(10) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    rarity_tier VARCHAR(20) NOT NULL CHECK (rarity_tier IN ('legendary', 'mythic', 'epic', 'rare', 'uncommon', 'common')),
    drop_rate_percentage DECIMAL(5,3) NOT NULL CHECK (drop_rate_percentage > 0 AND drop_rate_percentage <= 100),
    points_reward INTEGER NOT NULL CHECK (points_reward > 0),
    unicode_version VARCHAR(10),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Player emoji collections
CREATE TABLE player_emoji_collections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID REFERENCES players(id) ON DELETE CASCADE,
    emoji_id UUID REFERENCES emoji_catalog(id) ON DELETE CASCADE,
    discovered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_first_global_discovery BOOLEAN DEFAULT false,
    UNIQUE(player_id, emoji_id)
);

-- Global emoji discovery tracking
CREATE TABLE emoji_global_discoveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    emoji_id UUID REFERENCES emoji_catalog(id) ON DELETE CASCADE,
    first_discoverer_id UUID REFERENCES players(id) ON DELETE SET NULL,
    discovered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(emoji_id)
);

-- Add points tracking to players table
ALTER TABLE players ADD COLUMN IF NOT EXISTS total_emoji_points INTEGER DEFAULT 0;

-- Indexes for performance
CREATE INDEX idx_emoji_catalog_rarity ON emoji_catalog(rarity_tier);
CREATE INDEX idx_emoji_catalog_drop_rate ON emoji_catalog(drop_rate_percentage);
CREATE INDEX idx_player_emoji_collections_player ON player_emoji_collections(player_id);
CREATE INDEX idx_player_emoji_collections_emoji ON player_emoji_collections(emoji_id);
CREATE INDEX idx_emoji_global_discoveries_emoji ON emoji_global_discoveries(emoji_id);

-- Insert the Power 9 legendary emojis
INSERT INTO emoji_catalog (emoji_character, name, rarity_tier, drop_rate_percentage, points_reward, unicode_version) VALUES
('🫩', 'Face with Bags Under Eyes', 'legendary', 0.1, 500, '16.0'),
('🎨', 'Paint Splatter', 'legendary', 0.15, 500, '16.0'),
('🫴', 'Fingerprint', 'legendary', 0.2, 500, '16.0'),
('🇨🇶', 'Flag for Sark', 'legendary', 0.25, 500, '16.0'),
('🦄', 'Unicorn', 'legendary', 0.3, 500, '14.0'),
('👑', 'Crown', 'legendary', 0.35, 500, '6.0'),
('💎', 'Diamond', 'legendary', 0.4, 500, '6.0'),
('⚡', 'Lightning Bolt', 'legendary', 0.45, 500, '6.0'),
('🌟', 'Glowing Star', 'legendary', 0.5, 500, '6.0');

-- Insert mythic tier emojis (0.6% - 2%)
INSERT INTO emoji_catalog (emoji_character, name, rarity_tier, drop_rate_percentage, points_reward, unicode_version) VALUES
('🪐', 'Ringed Planet', 'mythic', 0.6, 200, '12.0'),
('🧿', 'Nazar Amulet', 'mythic', 0.8, 200, '11.0'),
('🎭', 'Performing Arts', 'mythic', 1.0, 200, '6.0'),
('🏆', 'Trophy', 'mythic', 1.2, 200, '6.0'),
('🌌', 'Milky Way', 'mythic', 1.4, 200, '6.0'),
('🔥', 'Fire', 'mythic', 1.6, 200, '6.0'),
('✨', 'Sparkles', 'mythic', 1.8, 200, '6.0'),
('🎆', 'Fireworks', 'mythic', 2.0, 200, '6.0');

-- Insert epic tier emojis (2.1% - 5%) - triggers global drops
INSERT INTO emoji_catalog (emoji_character, name, rarity_tier, drop_rate_percentage, points_reward, unicode_version) VALUES
('🎯', 'Direct Hit', 'epic', 2.5, 100, '6.0'),
('🎪', 'Circus Tent', 'epic', 3.0, 100, '6.0'),
('🎰', 'Slot Machine', 'epic', 3.5, 100, '6.0'),
('🚀', 'Rocket', 'epic', 4.0, 100, '6.0'),
('🛸', 'Flying Saucer', 'epic', 4.5, 100, '7.0'),
('🏁', 'Chequered Flag', 'epic', 5.0, 100, '6.0');

-- Insert rare tier emojis (5.1% - 15%)
INSERT INTO emoji_catalog (emoji_character, name, rarity_tier, drop_rate_percentage, points_reward, unicode_version) VALUES
('🎁', 'Gift', 'rare', 6.0, 25, '6.0'),
('🎈', 'Balloon', 'rare', 7.0, 25, '6.0'),
('🎀', 'Ribbon', 'rare', 8.0, 25, '6.0'),
('🥇', 'Gold Medal', 'rare', 9.0, 25, '9.0'),
('🥈', 'Silver Medal', 'rare', 10.0, 25, '9.0'),
('🥉', 'Bronze Medal', 'rare', 11.0, 25, '9.0'),
('🎖️', 'Military Medal', 'rare', 12.0, 25, '7.0'),
('🏅', 'Sports Medal', 'rare', 13.0, 25, '7.0'),
('🎗️', 'Reminder Ribbon', 'rare', 14.0, 25, '7.0'),
('🌈', 'Rainbow', 'rare', 15.0, 25, '6.0');

-- Insert uncommon tier emojis (15.1% - 35%)
INSERT INTO emoji_catalog (emoji_character, name, rarity_tier, drop_rate_percentage, points_reward, unicode_version) VALUES
('🎵', 'Musical Note', 'uncommon', 16.0, 5, '6.0'),
('🎶', 'Musical Notes', 'uncommon', 17.0, 5, '6.0'),
('🎼', 'Musical Score', 'uncommon', 18.0, 5, '6.0'),
('🎤', 'Microphone', 'uncommon', 19.0, 5, '6.0'),
('🎧', 'Headphone', 'uncommon', 20.0, 5, '6.0'),
('🎺', 'Trumpet', 'uncommon', 21.0, 5, '6.0'),
('🎷', 'Saxophone', 'uncommon', 22.0, 5, '6.0'),
('🎸', 'Guitar', 'uncommon', 23.0, 5, '6.0'),
('🎻', 'Violin', 'uncommon', 24.0, 5, '6.0'),
('🎹', 'Musical Keyboard', 'uncommon', 25.0, 5, '6.0'),
('🥁', 'Drum', 'uncommon', 26.0, 5, '9.0'),
('💫', 'Dizzy', 'uncommon', 27.0, 5, '6.0'),
('⭐', 'Star', 'uncommon', 28.0, 5, '5.1'),
('🌠', 'Shooting Star', 'uncommon', 29.0, 5, '6.0'),
('☄️', 'Comet', 'uncommon', 30.0, 5, '7.0'),
('🌙', 'Crescent Moon', 'uncommon', 31.0, 5, '6.0'),
('☀️', 'Sun', 'uncommon', 32.0, 5, '6.0'),
('🌞', 'Sun with Face', 'uncommon', 33.0, 5, '6.0'),
('🌛', 'First Quarter Moon Face', 'uncommon', 34.0, 5, '6.0'),
('🌜', 'Last Quarter Moon Face', 'uncommon', 35.0, 5, '6.0');

-- Insert common tier emojis (35.1% - 100%) - the current celebration emojis
INSERT INTO emoji_catalog (emoji_character, name, rarity_tier, drop_rate_percentage, points_reward, unicode_version) VALUES
('🎉', 'Party Popper', 'common', 40.0, 1, '6.0'),
('🎊', 'Confetti Ball', 'common', 45.0, 1, '6.0'),
('🥳', 'Partying Face', 'common', 50.0, 1, '11.0'),
('🍾', 'Bottle with Popping Cork', 'common', 55.0, 1, '8.0'),
('💃', 'Woman Dancing', 'common', 60.0, 1, '6.0'),
('🕺', 'Man Dancing', 'common', 65.0, 1, '9.0'),
('🤩', 'Star-Struck', 'common', 70.0, 1, '11.0'),
('😍', 'Smiling Face with Heart-Eyes', 'common', 75.0, 1, '6.0'),
('🤗', 'Smiling Face with Open Hands', 'common', 80.0, 1, '8.0'),
('😎', 'Smiling Face with Sunglasses', 'common', 85.0, 1, '6.0'),
('🥰', 'Smiling Face with Hearts', 'common', 90.0, 1, '11.0'),
('😘', 'Face Blowing a Kiss', 'common', 95.0, 1, '6.0'),
('❤️', 'Red Heart', 'common', 100.0, 1, '6.0');