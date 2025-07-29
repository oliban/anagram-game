const { Pool } = require('pg');

class ConfigService {
    constructor(dbPool) {
        this.dbPool = dbPool;
        this.cache = new Map();
        this.cacheTimeout = 30000; // 30 seconds cache
        this.lastCacheUpdate = new Map();
    }

    /**
     * Get configuration value from database with caching
     * @param {string} key - Configuration key
     * @param {any} defaultValue - Default value if key not found
     * @returns {Promise<any>} Configuration value
     */
    async getConfig(key, defaultValue = null) {
        try {
            // Check cache first
            if (this.cache.has(key)) {
                const lastUpdate = this.lastCacheUpdate.get(key) || 0;
                if (Date.now() - lastUpdate < this.cacheTimeout) {
                    return this.cache.get(key);
                }
            }

            // Fetch from database
            const result = await this.dbPool.query(
                'SELECT value FROM server_config WHERE key = $1',
                [key]
            );

            let value = defaultValue;
            if (result.rows.length > 0) {
                const rawValue = result.rows[0].value;
                
                // Parse boolean values
                if (rawValue === 'true') value = true;
                else if (rawValue === 'false') value = false;
                else if (!isNaN(rawValue)) value = Number(rawValue);
                else value = rawValue;
            }

            // Update cache
            this.cache.set(key, value);
            this.lastCacheUpdate.set(key, Date.now());

            return value;
        } catch (error) {
            console.error(`🚨 CONFIG ERROR: Failed to get config ${key}:`, error);
            return defaultValue;
        }
    }

    /**
     * Set configuration value in database
     * @param {string} key - Configuration key
     * @param {any} value - Configuration value
     * @param {string} description - Optional description
     * @returns {Promise<boolean>} Success status
     */
    async setConfig(key, value, description = null) {
        try {
            const stringValue = String(value);
            
            const result = await this.dbPool.query(`
                INSERT INTO server_config (key, value, description) 
                VALUES ($1, $2, $3)
                ON CONFLICT (key) 
                DO UPDATE SET 
                    value = $2, 
                    description = COALESCE($3, server_config.description),
                    updated_at = CURRENT_TIMESTAMP
            `, [key, stringValue, description]);

            // Clear cache for this key to force refresh
            this.cache.delete(key);
            this.lastCacheUpdate.delete(key);

            console.log(`⚙️ CONFIG: Updated ${key} = ${stringValue}`);
            return true;
        } catch (error) {
            console.error(`🚨 CONFIG ERROR: Failed to set config ${key}:`, error);
            return false;
        }
    }

    /**
     * Get all configuration values
     * @returns {Promise<Object>} All configuration as key-value pairs
     */
    async getAllConfig() {
        try {
            const result = await this.dbPool.query(
                'SELECT key, value, description, updated_at FROM server_config ORDER BY key'
            );

            const config = {};
            for (const row of result.rows) {
                let value = row.value;
                
                // Parse boolean and numeric values
                if (value === 'true') value = true;
                else if (value === 'false') value = false;
                else if (!isNaN(value)) value = Number(value);

                config[row.key] = {
                    value,
                    description: row.description,
                    updated_at: row.updated_at
                };
            }

            return config;
        } catch (error) {
            console.error('🚨 CONFIG ERROR: Failed to get all config:', error);
            return {};
        }
    }

    /**
     * Clear cache (useful for testing or manual refresh)
     */
    clearCache() {
        this.cache.clear();
        this.lastCacheUpdate.clear();
        console.log('⚙️ CONFIG: Cache cleared');
    }
}

module.exports = ConfigService;