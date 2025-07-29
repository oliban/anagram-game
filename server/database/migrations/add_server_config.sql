-- Server Configuration Table
-- This table stores dynamic server configuration that can be changed without redeployment

CREATE TABLE IF NOT EXISTS server_config (
    key VARCHAR(255) PRIMARY KEY,
    value TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert default configuration values
INSERT INTO server_config (key, value, description) VALUES 
    ('performance_monitoring_enabled', 'true', 'Enable/disable performance monitoring UI and logging')
ON CONFLICT (key) DO NOTHING;

-- Add trigger to update timestamp on changes
CREATE OR REPLACE FUNCTION update_server_config_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_server_config_timestamp
    BEFORE UPDATE ON server_config
    FOR EACH ROW
    EXECUTE FUNCTION update_server_config_timestamp();