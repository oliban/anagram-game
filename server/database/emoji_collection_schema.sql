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