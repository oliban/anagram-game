const { pool } = require('./shared/database/connection');
const crypto = require('crypto');

class ContributionLinkGenerator {
    constructor() {
        this.defaultExpirationHours = 48;
        this.maxUsesPerLink = 3;
    }

    generateSecureToken() {
        return crypto.randomBytes(32).toString('base64url');
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
            
            // Use link generator URL for contribution links since that's where the form is hosted
            // Default to the same IP used by iOS app for consistency  
            const linkGeneratorUrl = process.env.LINK_GENERATOR_URL || 'http://192.168.1.133:3002';
            
            return {
                id: link.id,
                token: link.token,
                url: `/contribute/${link.token}`,
                expiresAt: link.expires_at,
                maxUses: link.max_uses,
                shareableUrl: `${linkGeneratorUrl}/contribute/${link.token}`
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
                p.name as requesting_player_name
            FROM contribution_links cl
            JOIN players p ON cl.requesting_player_id = p.id
            WHERE cl.token = $1
        `;

        try {
            console.log(`🔍 VALIDATE: Executing query with token parameter`);
            const result = await pool.query(query, [token]);
            console.log(`🔍 VALIDATE: Query returned ${result.rows.length} rows`);
            
            if (result.rows.length === 0) {
                console.log(`❌ VALIDATE: No rows found for token ${token}`);
                return { valid: false, reason: 'Token not found' };
            }

            const link = result.rows[0];
            
            if (!link.is_active) {
                return { 
                    valid: false, 
                    reason: 'Link has been deactivated',
                    link: {
                        id: link.id,
                        token: link.token,
                        requestingPlayerId: link.requesting_player_id,
                        requestingPlayerName: link.requesting_player_name,
                        expiresAt: link.expires_at,
                        maxUses: link.max_uses,
                        currentUses: link.current_uses,
                        remainingUses: link.max_uses - link.current_uses
                    }
                };
            }

            if (new Date() > new Date(link.expires_at)) {
                return { 
                    valid: false, 
                    reason: 'Link has expired',
                    link: {
                        id: link.id,
                        token: link.token,
                        requestingPlayerId: link.requesting_player_id,
                        requestingPlayerName: link.requesting_player_name,
                        expiresAt: link.expires_at,
                        maxUses: link.max_uses,
                        currentUses: link.current_uses,
                        remainingUses: link.max_uses - link.current_uses
                    }
                };
            }

            if (link.current_uses >= link.max_uses) {
                return { valid: false, reason: 'Link usage limit reached' };
            }

            return {
                valid: true,
                link: {
                    id: link.id,
                    token: link.token,
                    requestingPlayerId: link.requesting_player_id,
                    requestingPlayerName: link.requesting_player_name,
                    expiresAt: link.expires_at,
                    maxUses: link.max_uses,
                    currentUses: link.current_uses,
                    remainingUses: link.max_uses - link.current_uses
                }
            };
        } catch (error) {
            console.error('Error validating token:', error);
            throw new Error('Failed to validate token');
        }
    }

    async recordContribution(token, contributorInfo = {}) {
        const { name, ip } = contributorInfo;
        
        const query = `
            UPDATE contribution_links 
            SET 
                current_uses = current_uses + 1,
                contributor_name = COALESCE(contributor_name, $2),
                contributor_ip = COALESCE(contributor_ip, $3),
                used_at = CASE 
                    WHEN current_uses = 0 THEN CURRENT_TIMESTAMP 
                    ELSE used_at 
                END
            WHERE token = $1
            RETURNING current_uses, max_uses
        `;

        try {
            const result = await pool.query(query, [token, name, ip]);
            
            if (result.rows.length === 0) {
                throw new Error('Token not found');
            }

            const link = result.rows[0];
            
            // Deactivate link if max uses reached
            if (link.current_uses >= link.max_uses) {
                await pool.query(
                    'UPDATE contribution_links SET is_active = false WHERE token = $1',
                    [token]
                );
            }

            return {
                success: true,
                currentUses: link.current_uses,
                maxUses: link.max_uses,
                remainingUses: link.max_uses - link.current_uses
            };
        } catch (error) {
            console.error('Error recording contribution:', error);
            throw new Error('Failed to record contribution');
        }
    }

    async getPlayerContributionLinks(playerId, activeOnly = true) {
        let query = `
            SELECT 
                id,
                token,
                created_at,
                expires_at,
                max_uses,
                current_uses,
                is_active,
                contributor_name
            FROM contribution_links 
            WHERE requesting_player_id = $1
        `;

        if (activeOnly) {
            query += ' AND is_active = true AND expires_at > CURRENT_TIMESTAMP';
        }

        query += ' ORDER BY created_at DESC';

        try {
            const result = await pool.query(query, [playerId]);
            
            // Use link generator service URL for contribution links
            const baseUrl = process.env.LINK_GENERATOR_URL || process.env.BASE_URL || 'http://localhost:3002';
            
            return result.rows.map(link => ({
                id: link.id,
                token: link.token,
                url: `/contribute/${link.token}`,
                shareableUrl: `${baseUrl}/contribute/${link.token}`,
                createdAt: link.created_at,
                expiresAt: link.expires_at,
                maxUses: link.max_uses,
                currentUses: link.current_uses,
                remainingUses: link.max_uses - link.current_uses,
                isActive: link.is_active,
                contributorName: link.contributor_name,
                status: this.getLinkStatus(link)
            }));
        } catch (error) {
            console.error('Error fetching player contribution links:', error);
            throw new Error('Failed to fetch contribution links');
        }
    }

    getLinkStatus(link) {
        if (!link.is_active) return 'deactivated';
        if (new Date() > new Date(link.expires_at)) return 'expired';
        if (link.current_uses >= link.max_uses) return 'used_up';
        return 'active';
    }

    async deactivateLink(linkId, playerId) {
        const query = `
            UPDATE contribution_links 
            SET is_active = false 
            WHERE id = $1 AND requesting_player_id = $2
            RETURNING id
        `;

        try {
            const result = await pool.query(query, [linkId, playerId]);
            
            if (result.rows.length === 0) {
                throw new Error('Link not found or not owned by player');
            }

            return { success: true, linkId: result.rows[0].id };
        } catch (error) {
            console.error('Error deactivating link:', error);
            throw new Error('Failed to deactivate link');
        }
    }

    async cleanupExpiredLinks() {
        const query = `
            UPDATE contribution_links 
            SET is_active = false 
            WHERE expires_at < CURRENT_TIMESTAMP AND is_active = true
            RETURNING COUNT(*) as cleaned_count
        `;

        try {
            const result = await pool.query(query);
            return result.rows[0]?.cleaned_count || 0;
        } catch (error) {
            console.error('Error cleaning up expired links:', error);
            return 0;
        }
    }

    async getContributionStats() {
        const query = `
            SELECT 
                COUNT(*) as total_links,
                COUNT(CASE WHEN is_active = true AND expires_at > CURRENT_TIMESTAMP THEN 1 END) as active_links,
                COUNT(CASE WHEN current_uses > 0 THEN 1 END) as used_links,
                SUM(current_uses) as total_contributions,
                AVG(current_uses) as avg_uses_per_link
            FROM contribution_links
        `;

        try {
            const result = await pool.query(query);
            return result.rows[0];
        } catch (error) {
            console.error('Error fetching contribution stats:', error);
            throw new Error('Failed to fetch contribution stats');
        }
    }
}

module.exports = ContributionLinkGenerator;