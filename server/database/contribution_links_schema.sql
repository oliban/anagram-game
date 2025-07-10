-- Contribution Links System Schema
-- This schema enables external phrase contributions via shareable links

-- Contribution links table
CREATE TABLE contribution_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token VARCHAR(255) UNIQUE NOT NULL,
    requesting_player_id UUID REFERENCES players(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    used_at TIMESTAMP NULL,
    contributor_name VARCHAR(100) NULL,
    contributor_ip VARCHAR(45) NULL,
    is_active BOOLEAN DEFAULT true,
    max_uses INTEGER DEFAULT 1,
    current_uses INTEGER DEFAULT 0
);

-- Add indexes for performance
CREATE INDEX idx_contribution_links_token ON contribution_links(token);
CREATE INDEX idx_contribution_links_requesting_player ON contribution_links(requesting_player_id);
CREATE INDEX idx_contribution_links_expires_at ON contribution_links(expires_at);
CREATE INDEX idx_contribution_links_is_active ON contribution_links(is_active);

-- Add language field to phrases table if it doesn't exist
ALTER TABLE phrases 
ADD COLUMN IF NOT EXISTS language VARCHAR(5) DEFAULT 'en' CHECK (language IN ('en', 'sv'));

-- Add source tracking to phrases
ALTER TABLE phrases 
ADD COLUMN IF NOT EXISTS source VARCHAR(20) DEFAULT 'app' CHECK (source IN ('app', 'external', 'admin'));

-- Add contribution link reference to phrases
ALTER TABLE phrases 
ADD COLUMN IF NOT EXISTS contribution_link_id UUID REFERENCES contribution_links(id) ON DELETE SET NULL;

-- Function to clean up expired contribution links
CREATE OR REPLACE FUNCTION cleanup_expired_contribution_links()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM contribution_links 
    WHERE expires_at < CURRENT_TIMESTAMP 
    AND is_active = false;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Function to generate secure token
CREATE OR REPLACE FUNCTION generate_contribution_token()
RETURNS VARCHAR(255) AS $$
BEGIN
    RETURN encode(gen_random_bytes(32), 'base64url');
END;
$$ LANGUAGE plpgsql;