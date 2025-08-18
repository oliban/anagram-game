const { pool } = require('./database/connection');
const crypto = require('crypto');

class ContributionLinkGenerator {
    constructor() {
        this.defaultExpirationHours = 48;
        this.maxUsesPerLink = 3;
    }

    generateSecureToken() {
        return crypto.randomBytes(32).toString('base64url');
    }

    // Get dynamic base URL for shareable links - now uses game-server URL
    getShareableBaseUrl() {
        try {
            // Check for dynamic tunnel URL from environment (set at container start)
            if (process.env.DYNAMIC_TUNNEL_URL) {
                console.log(`🔗 Using dynamic tunnel URL from env: ${process.env.DYNAMIC_TUNNEL_URL}`);
                return process.env.DYNAMIC_TUNNEL_URL;
            }

            // For staging environment, try to read the dynamic Cloudflare tunnel URL from file
            if (process.env.NODE_ENV === 'staging' || process.env.NODE_ENV === 'production') {
                try {
                    const fs = require('fs');
                    // Try to read tunnel URL from the mounted file (updated by cloudflare-tunnel service)
                    const tunnelUrl = fs.readFileSync('/app/cloudflare-tunnel-url.txt', 'utf8').trim();
                    if (tunnelUrl && tunnelUrl.startsWith('https://')) {
                        console.log(`🔗 Using dynamic tunnel URL from file: ${tunnelUrl}`);
                        return tunnelUrl;
                    }
                } catch (error) {
                    console.log(`⚠️ Could not read tunnel URL file: ${error.message}`);
                }
            }

            // Fallback to environment variable or default - now uses game-server URL
            const fallbackUrl = process.env.SERVER_URL || 'http://192.168.1.133:3000';
            console.log(`🔗 Using fallback URL: ${fallbackUrl}`);
            return fallbackUrl;
            
        } catch (error) {
            console.error('Error getting shareable base URL:', error);
            return 'http://192.168.1.133:3000'; // Hard fallback to game-server
        }
    }

    async createContributionLink(requestingPlayerId, options = {}) {
        const {
            expirationHours = this.defaultExpirationHours,
            maxUses = this.maxUsesPerLink,
            customMessage = null
        } = options;

        const token = this.generateSecureToken();
        const expiresAt = new Date(Date.now() + (expirationHours * 60 * 60 * 1000));

        const query = `
            INSERT INTO contribution_links 
            (token, requesting_player_id, expires_at, max_uses)
            VALUES ($1, $2, $3, $4)
            RETURNING id, token, expires_at, max_uses
        `;

        try {
            const result = await pool.query(query, [
                token,
                requestingPlayerId,
                expiresAt,
                maxUses
            ]);

            const link = result.rows[0];
            
            // Get dynamic base URL for shareable links
            const shareableBaseUrl = this.getShareableBaseUrl();
            
            return {
                id: link.id,
                token: link.token,
                url: `/contribute/${link.token}`,
                expiresAt: link.expires_at,
                maxUses: link.max_uses,
                shareableUrl: `${shareableBaseUrl}/contribute/${link.token}`
            };
        } catch (error) {
            console.error('Error creating contribution link:', error);
            throw new Error('Failed to create contribution link');
        }
    }

    async validateToken(token) {
        console.log(`🔍 VALIDATE: Checking token: ${token}`);
        
        const query = `
            SELECT 
                cl.id,
                cl.token,
                cl.requesting_player_id,
                cl.expires_at,
                cl.max_uses,
                cl.current_uses,
                cl.is_active,
                cl.created_at,
                p.name as requesting_player_name
            FROM contribution_links cl
            LEFT JOIN players p ON cl.requesting_player_id = p.id
            WHERE cl.token = $1 
            AND cl.is_active = true
            AND cl.expires_at > NOW()
            AND cl.current_uses < cl.max_uses
        `;

        try {
            const result = await pool.query(query, [token]);
            
            if (result.rows.length === 0) {
                console.log(`❌ VALIDATE: Token not found, expired, or exhausted: ${token}`);
                return null;
            }

            const link = result.rows[0];
            console.log(`✅ VALIDATE: Valid token found for player: ${link.requesting_player_name} (${link.requesting_player_id})`);
            console.log(`📊 VALIDATE: Usage: ${link.current_uses}/${link.max_uses}, Expires: ${link.expires_at}`);
            
            return {
                id: link.id,
                token: link.token,
                requestingPlayerId: link.requesting_player_id,
                requestingPlayerName: link.requesting_player_name,
                expiresAt: link.expires_at,
                maxUses: link.max_uses,
                currentUses: link.current_uses,
                remainingUses: link.max_uses - link.current_uses,
                createdAt: link.created_at
            };
        } catch (error) {
            console.error('Error validating token:', error);
            throw new Error('Failed to validate contribution link');
        }
    }

    async incrementUsage(token) {
        const query = `
            UPDATE contribution_links 
            SET current_uses = current_uses + 1,
                used_at = NOW()
            WHERE token = $1
            AND is_active = true
            AND expires_at > NOW()
            AND current_uses < max_uses
            RETURNING id, current_uses, max_uses
        `;

        try {
            const result = await pool.query(query, [token]);
            
            if (result.rows.length === 0) {
                throw new Error('Cannot increment usage: link not found, expired, or exhausted');
            }

            const link = result.rows[0];
            console.log(`📊 USAGE: Incremented usage for link ${link.id}: ${link.current_uses}/${link.max_uses}`);
            
            return {
                id: link.id,
                currentUses: link.current_uses,
                maxUses: link.max_uses,
                remainingUses: link.max_uses - link.current_uses
            };
        } catch (error) {
            console.error('Error incrementing link usage:', error);
            throw error;
        }
    }

    // Cleanup expired links (maintenance task)
    async cleanupExpiredLinks() {
        const query = `
            UPDATE contribution_links 
            SET is_active = false
            WHERE expires_at <= NOW() AND is_active = true
            RETURNING COUNT(*) as cleaned_count
        `;

        try {
            const result = await pool.query(query);
            const cleanedCount = result.rowCount || 0;
            
            if (cleanedCount > 0) {
                console.log(`🧹 Cleaned up ${cleanedCount} expired contribution links`);
            }
            
            return cleanedCount;
        } catch (error) {
            console.error('Error cleaning up expired links:', error);
            throw error;
        }
    }
}

module.exports = ContributionLinkGenerator;