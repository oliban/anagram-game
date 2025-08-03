-- Rebalance emoji drop rates for better distribution
-- Goal: Make legendary actually rare, but not impossible to get

-- Update common emojis to have more reasonable rates (20-30% instead of 40-100%)
UPDATE emoji_catalog SET drop_rate_percentage = 30.0 WHERE emoji_character = '❤️';
UPDATE emoji_catalog SET drop_rate_percentage = 25.0 WHERE emoji_character = '😍';
UPDATE emoji_catalog SET drop_rate_percentage = 20.0 WHERE emoji_character = '🥳';
UPDATE emoji_catalog SET drop_rate_percentage = 18.0 WHERE emoji_character = '🎊';
UPDATE emoji_catalog SET drop_rate_percentage = 15.0 WHERE emoji_character = '🎉';

-- Update epic emojis to have rates between 3-8%
UPDATE emoji_catalog SET drop_rate_percentage = 8.0 WHERE emoji_character = '🏁';
UPDATE emoji_catalog SET drop_rate_percentage = 7.0 WHERE emoji_character = '🛸';
UPDATE emoji_catalog SET drop_rate_percentage = 6.0 WHERE emoji_character = '🚀';
UPDATE emoji_catalog SET drop_rate_percentage = 5.0 WHERE emoji_character = '🎰';
UPDATE emoji_catalog SET drop_rate_percentage = 4.0 WHERE emoji_character = '🎪';
UPDATE emoji_catalog SET drop_rate_percentage = 3.0 WHERE emoji_character = '🎯';

-- Update mythic emojis to have rates between 1-2.5%
UPDATE emoji_catalog SET drop_rate_percentage = 2.5 WHERE emoji_character = '🎆';
UPDATE emoji_catalog SET drop_rate_percentage = 2.2 WHERE emoji_character = '✨';
UPDATE emoji_catalog SET drop_rate_percentage = 2.0 WHERE emoji_character = '🔥';
UPDATE emoji_catalog SET drop_rate_percentage = 1.8 WHERE emoji_character = '🌌';
UPDATE emoji_catalog SET drop_rate_percentage = 1.5 WHERE emoji_character = '🏆';
UPDATE emoji_catalog SET drop_rate_percentage = 1.2 WHERE emoji_character = '🎭';
UPDATE emoji_catalog SET drop_rate_percentage = 1.0 WHERE emoji_character = '🪐';

-- Legendary rates remain very low but slightly increased (0.1-0.8%)
UPDATE emoji_catalog SET drop_rate_percentage = 0.8 WHERE emoji_character = '💎';
UPDATE emoji_catalog SET drop_rate_percentage = 0.7 WHERE emoji_character = '🗿';
UPDATE emoji_catalog SET drop_rate_percentage = 0.6 WHERE emoji_character = '🦄';
UPDATE emoji_catalog SET drop_rate_percentage = 0.5 WHERE emoji_character = '🧿';
UPDATE emoji_catalog SET drop_rate_percentage = 0.4 WHERE emoji_character = '🍶';
UPDATE emoji_catalog SET drop_rate_percentage = 0.3 WHERE emoji_character = '🦞';
UPDATE emoji_catalog SET drop_rate_percentage = 0.2 WHERE emoji_character = '🫴';
UPDATE emoji_catalog SET drop_rate_percentage = 0.15 WHERE emoji_character = '🎨';
UPDATE emoji_catalog SET drop_rate_percentage = 0.1 WHERE emoji_character = '🧬';

-- Check the new distribution
SELECT rarity_tier, 
       COUNT(*) as count, 
       SUM(drop_rate_percentage) as total_weight,
       ROUND(SUM(drop_rate_percentage)::numeric, 2) || '%' as percent_of_drops
FROM emoji_catalog 
WHERE is_active = true 
GROUP BY rarity_tier 
ORDER BY total_weight DESC;

-- Check total weight
SELECT SUM(drop_rate_percentage) as new_total_weight FROM emoji_catalog WHERE is_active = true;