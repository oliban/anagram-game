-- Patch 001: Add Contribution Links System
-- Safe to run multiple times - uses IF NOT EXISTS and conditional logic

-- Check if the contribution_links table already exists
DO $$
BEGIN
    -- Only create the table if it doesn't exist
    IF NOT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'contribution_links') THEN
        
        -- Create the contribution_links table
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

        RAISE NOTICE 'Created contribution_links table and indexes';
    ELSE
        RAISE NOTICE 'contribution_links table already exists, skipping creation';
    END IF;
END
$$;

-- Add language field to phrases table if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'phrases' AND column_name = 'language') THEN
        ALTER TABLE phrases ADD COLUMN language VARCHAR(5) DEFAULT 'en' CHECK (language IN ('en', 'sv'));
        RAISE NOTICE 'Added language column to phrases table';
    ELSE
        RAISE NOTICE 'language column already exists in phrases table';
    END IF;
END
$$;

-- Add source tracking to phrases table if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'phrases' AND column_name = 'source') THEN
        ALTER TABLE phrases ADD COLUMN source VARCHAR(20) DEFAULT 'app' CHECK (source IN ('app', 'external', 'admin'));
        RAISE NOTICE 'Added source column to phrases table';
    ELSE
        RAISE NOTICE 'source column already exists in phrases table';
    END IF;
END
$$;

-- Add contribution link reference to phrases table if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'phrases' AND column_name = 'contribution_link_id') THEN
        ALTER TABLE phrases ADD COLUMN contribution_link_id UUID REFERENCES contribution_links(id) ON DELETE SET NULL;
        RAISE NOTICE 'Added contribution_link_id column to phrases table';
    ELSE
        RAISE NOTICE 'contribution_link_id column already exists in phrases table';
    END IF;
END
$$;

-- Create helper functions if they don't exist
DO $$
BEGIN
    -- Check if cleanup function exists
    IF NOT EXISTS (SELECT FROM pg_proc WHERE proname = 'cleanup_expired_contribution_links') THEN
        CREATE OR REPLACE FUNCTION cleanup_expired_contribution_links()
        RETURNS INTEGER AS $func$
        DECLARE
            deleted_count INTEGER;
        BEGIN
            DELETE FROM contribution_links 
            WHERE expires_at < CURRENT_TIMESTAMP 
            AND is_active = false;
            
            GET DIAGNOSTICS deleted_count = ROW_COUNT;
            RETURN deleted_count;
        END;
        $func$ LANGUAGE plpgsql;
        
        RAISE NOTICE 'Created cleanup_expired_contribution_links function';
    ELSE
        RAISE NOTICE 'cleanup_expired_contribution_links function already exists';
    END IF;

    -- Check if token generation function exists
    IF NOT EXISTS (SELECT FROM pg_proc WHERE proname = 'generate_contribution_token') THEN
        CREATE OR REPLACE FUNCTION generate_contribution_token()
        RETURNS VARCHAR(255) AS $func$
        BEGIN
            RETURN encode(gen_random_bytes(32), 'base64url');
        END;
        $func$ LANGUAGE plpgsql;
        
        RAISE NOTICE 'Created generate_contribution_token function';
    ELSE
        RAISE NOTICE 'generate_contribution_token function already exists';
    END IF;
END
$$;

-- Verify the patch was applied successfully
DO $$
BEGIN
    -- Check that all required components exist
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'contribution_links') AND
       EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'phrases' AND column_name = 'language') AND
       EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'phrases' AND column_name = 'source') AND
       EXISTS (SELECT FROM pg_proc WHERE proname = 'cleanup_expired_contribution_links') THEN
        
        RAISE NOTICE '✅ Patch 001 (Contribution Links System) applied successfully!';
        RAISE NOTICE 'You can now use the web dashboard contribution system.';
    ELSE
        RAISE EXCEPTION '❌ Patch 001 failed to apply correctly. Please check the logs above.';
    END IF;
END
$$;