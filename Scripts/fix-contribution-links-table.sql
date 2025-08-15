-- Fix contribution_links table to match localhost schema
-- Add missing columns to staging database

-- Add missing columns
ALTER TABLE contribution_links 
ADD COLUMN IF NOT EXISTS token VARCHAR(255),
ADD COLUMN IF NOT EXISTS requesting_player_id UUID,
ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP,
ADD COLUMN IF NOT EXISTS used_at TIMESTAMP,
ADD COLUMN IF NOT EXISTS contributor_ip VARCHAR(45),
ADD COLUMN IF NOT EXISTS max_uses INTEGER DEFAULT 1,
ADD COLUMN IF NOT EXISTS current_uses INTEGER DEFAULT 0;

-- Add foreign key constraint
ALTER TABLE contribution_links 
ADD CONSTRAINT contribution_links_requesting_player_id_fkey 
FOREIGN KEY (requesting_player_id) REFERENCES players(id) ON DELETE CASCADE;

-- Add unique constraint on token
ALTER TABLE contribution_links 
ADD CONSTRAINT contribution_links_token_key UNIQUE (token);

-- Create the missing indexes
CREATE INDEX IF NOT EXISTS idx_contribution_links_token ON contribution_links(token);
CREATE INDEX IF NOT EXISTS idx_contribution_links_requesting_player ON contribution_links(requesting_player_id);
CREATE INDEX IF NOT EXISTS idx_contribution_links_expires_at ON contribution_links(expires_at);

-- Add missing functions
CREATE OR REPLACE FUNCTION generate_contribution_token()
RETURNS VARCHAR(255) AS $$
BEGIN
    RETURN encode(gen_random_bytes(32), 'base64url');
END;
$$ LANGUAGE plpgsql;