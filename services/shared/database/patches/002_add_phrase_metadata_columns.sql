-- Add metadata columns to phrases table for enhanced phrase management
-- These columns support external contributions, theming, and proper sender attribution

ALTER TABLE phrases ADD COLUMN IF NOT EXISTS theme VARCHAR(100);
ALTER TABLE phrases ADD COLUMN IF NOT EXISTS contributor_name VARCHAR(100);  
ALTER TABLE phrases ADD COLUMN IF NOT EXISTS source VARCHAR(20) DEFAULT 'app';
ALTER TABLE phrases ADD COLUMN IF NOT EXISTS contribution_link_id UUID;
ALTER TABLE phrases ADD COLUMN IF NOT EXISTS sender_name VARCHAR(100);

-- Add index on sender_name for faster lookups
CREATE INDEX IF NOT EXISTS idx_phrases_sender_name ON phrases(sender_name);

-- Add index on theme for categorization queries
CREATE INDEX IF NOT EXISTS idx_phrases_theme ON phrases(theme);