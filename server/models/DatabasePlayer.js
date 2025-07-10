const { query, transaction } = require('../database/connection');

/**
 * DatabasePlayer model implementing persistent player storage
 * This replaces the old in-memory PlayerStore with database persistence
 */
class DatabasePlayer {
  constructor(data) {
    this.id = data.id;
    this.name = data.name;
    this.isActive = data.is_active;
    this.lastSeen = data.last_seen;
    this.phrasesCompleted = data.phrases_completed;
    this.socketId = data.socket_id;
    this.createdAt = data.created_at;
  }

  /**
   * Get public info (safe to send to clients)
   */
  getPublicInfo() {
    return {
      id: this.id,
      name: this.name,
      isActive: this.isActive,
      lastSeen: this.lastSeen,
      phrasesCompleted: this.phrasesCompleted
    };
  }

  /**
   * Validate player name
   */
  static validateName(name) {
    if (!name || typeof name !== 'string') {
      return { valid: false, error: 'Player name is required and must be a string' };
    }

    const trimmedName = name.trim();
    if (trimmedName.length < 2 || trimmedName.length > 50) {
      return { valid: false, error: 'Player name must be between 2 and 50 characters' };
    }

    // Check alphanumeric (allow spaces and basic punctuation)
    const validNamePattern = /^[a-zA-Z0-9\s\-_]+$/;
    if (!validNamePattern.test(trimmedName)) {
      return { valid: false, error: 'Player name can only contain letters, numbers, spaces, hyphens, and underscores' };
    }

    return { valid: true, name: trimmedName };
  }

  /**
   * Create or get existing player
   */
  static async createPlayer(name, socketId = null) {
    const validation = this.validateName(name);
    if (!validation.valid) {
      throw new Error(validation.error);
    }

    try {
      // First try to get existing player
      const existingResult = await query(`
        SELECT * FROM players WHERE name = $1
      `, [validation.name]);

      if (existingResult.rows.length > 0) {
        // Player exists, update socket and activity
        const updateResult = await query(`
          UPDATE players 
          SET socket_id = $2, is_active = true, last_seen = CURRENT_TIMESTAMP
          WHERE name = $1
          RETURNING *
        `, [validation.name, socketId]);

        const playerData = updateResult.rows[0];
        console.log(`👤 DATABASE: Existing player logged in: ${playerData.name} (${playerData.id})`);
        return new DatabasePlayer(playerData);
      } else {
        // Create new player
        const createResult = await query(`
          INSERT INTO players (name, socket_id, is_active, last_seen)
          VALUES ($1, $2, true, CURRENT_TIMESTAMP)
          RETURNING *
        `, [validation.name, socketId]);

        const playerData = createResult.rows[0];
        console.log(`👤 DATABASE: New player created: ${playerData.name} (${playerData.id})`);
        return new DatabasePlayer(playerData);
      }
    } catch (error) {
      console.error('❌ DATABASE: Error creating/getting player:', error.message);
      throw new Error('Failed to create or retrieve player');
    }
  }

  /**
   * Get player by ID
   */
  static async getPlayerById(playerId) {
    try {
      const result = await query(`
        SELECT * FROM players WHERE id = $1
      `, [playerId]);

      if (result.rows.length === 0) {
        return null;
      }

      return new DatabasePlayer(result.rows[0]);
    } catch (error) {
      console.error('❌ DATABASE: Error getting player by ID:', error.message);
      return null;
    }
  }

  /**
   * Get player by socket ID
   */
  static async getPlayerBySocketId(socketId) {
    try {
      const result = await query(`
        SELECT * FROM players WHERE socket_id = $1 AND is_active = true
      `, [socketId]);

      if (result.rows.length === 0) {
        return null;
      }

      return new DatabasePlayer(result.rows[0]);
    } catch (error) {
      console.error('❌ DATABASE: Error getting player by socket ID:', error.message);
      return null;
    }
  }

  /**
   * Update player socket ID
   */
  static async updateSocketId(playerId, socketId) {
    try {
      const result = await query(`
        UPDATE players 
        SET socket_id = $2, is_active = true, last_seen = CURRENT_TIMESTAMP
        WHERE id = $1
        RETURNING *
      `, [playerId, socketId]);

      if (result.rows.length > 0) {
        console.log(`🔌 DATABASE: Socket updated for player ${playerId}: ${socketId}`);
        return new DatabasePlayer(result.rows[0]);
      }

      return null;
    } catch (error) {
      console.error('❌ DATABASE: Error updating socket ID:', error.message);
      return null;
    }
  }

  /**
   * Set player as inactive (when disconnecting)
   */
  static async setPlayerInactive(socketId) {
    try {
      const result = await query(`
        UPDATE players 
        SET socket_id = NULL, is_active = false, last_seen = CURRENT_TIMESTAMP
        WHERE socket_id = $1
        RETURNING *
      `, [socketId]);

      if (result.rows.length > 0) {
        const player = new DatabasePlayer(result.rows[0]);
        console.log(`📴 DATABASE: Player ${player.name} set as inactive`);
        return player;
      }

      return null;
    } catch (error) {
      console.error('❌ DATABASE: Error setting player inactive:', error.message);
      return null;
    }
  }

  /**
   * Get all online players
   */
  static async getOnlinePlayers() {
    try {
      const result = await query(`
        SELECT * FROM players 
        WHERE is_active = true AND last_seen > NOW() - INTERVAL '5 minutes'
        ORDER BY last_seen DESC
      `);

      const players = result.rows.map(row => new DatabasePlayer(row));
      console.log(`👥 DATABASE: Found ${players.length} online players`);
      return players;
    } catch (error) {
      console.error('❌ DATABASE: Error getting online players:', error.message);
      return [];
    }
  }

  /**
   * Get all active players (including offline)
   */
  static async getActivePlayers() {
    try {
      const result = await query(`
        SELECT * FROM players 
        WHERE is_active = true
        ORDER BY last_seen DESC
      `);

      return result.rows.map(row => new DatabasePlayer(row));
    } catch (error) {
      console.error('❌ DATABASE: Error getting active players:', error.message);
      return [];
    }
  }

  /**
   * Check if player name is taken by another active player
   */
  static async isNameTaken(name, excludePlayerId = null) {
    try {
      let queryText = `
        SELECT COUNT(*) as count FROM players 
        WHERE name = $1 AND is_active = true
      `;
      let params = [name];

      if (excludePlayerId) {
        queryText += ` AND id != $2`;
        params.push(excludePlayerId);
      }

      const result = await query(queryText, params);
      return parseInt(result.rows[0].count) > 0;
    } catch (error) {
      console.error('❌ DATABASE: Error checking if name is taken:', error.message);
      return false;
    }
  }

  /**
   * Update player's completion count
   */
  async incrementCompletionCount() {
    try {
      const result = await query(`
        UPDATE players 
        SET phrases_completed = phrases_completed + 1, last_seen = CURRENT_TIMESTAMP
        WHERE id = $1
        RETURNING phrases_completed
      `, [this.id]);

      if (result.rows.length > 0) {
        this.phrasesCompleted = result.rows[0].phrases_completed;
        console.log(`📈 DATABASE: Player ${this.name} completion count: ${this.phrasesCompleted}`);
      }
    } catch (error) {
      console.error('❌ DATABASE: Error incrementing completion count:', error.message);
    }
  }

  /**
   * Get player statistics
   */
  static async getPlayerStats(playerId) {
    try {
      const result = await query(`
        SELECT 
          p.name,
          p.phrases_completed,
          p.created_at,
          (SELECT COUNT(*) FROM completed_phrases WHERE player_id = p.id) as phrases_completed_detailed,
          (SELECT COUNT(*) FROM skipped_phrases WHERE player_id = p.id) as phrases_skipped,
          (SELECT COUNT(*) FROM phrases WHERE created_by_player_id = p.id) as phrases_created,
          (SELECT AVG(completion_time_ms) FROM completed_phrases WHERE player_id = p.id) as avg_completion_time
        FROM players p
        WHERE p.id = $1
      `, [playerId]);

      if (result.rows.length === 0) {
        return null;
      }

      return result.rows[0];
    } catch (error) {
      console.error('❌ DATABASE: Error getting player stats:', error.message);
      return null;
    }
  }

  /**
   * Clean up old inactive players (older than 30 days)
   */
  static async cleanupInactivePlayers() {
    try {
      const result = await query(`
        DELETE FROM players 
        WHERE is_active = false 
          AND last_seen < CURRENT_TIMESTAMP - INTERVAL '30 days'
      `);

      const deletedCount = result.rowCount || 0;
      if (deletedCount > 0) {
        console.log(`🧹 DATABASE: Cleaned up ${deletedCount} inactive players`);
      }

      return deletedCount;
    } catch (error) {
      console.error('❌ DATABASE: Error cleaning up inactive players:', error.message);
      return 0;
    }
  }

  /**
   * Clean up stale socket connections (players who haven't been seen in 10+ minutes)
   */
  static async cleanupStaleConnections() {
    try {
      const result = await query(`
        UPDATE players 
        SET socket_id = NULL, is_active = false
        WHERE socket_id IS NOT NULL 
          AND last_seen < CURRENT_TIMESTAMP - INTERVAL '10 minutes'
      `);

      const updatedCount = result.rowCount || 0;
      if (updatedCount > 0) {
        console.log(`🧹 DATABASE: Cleaned up ${updatedCount} stale socket connections`);
      }

      return updatedCount;
    } catch (error) {
      console.error('❌ DATABASE: Error cleaning up stale connections:', error.message);
      return 0;
    }
  }

  /**
   * Get player count
   */
  static async getPlayerCount() {
    try {
      const result = await query(`
        SELECT 
          COUNT(*) as total_players,
          COUNT(*) FILTER (WHERE is_active = true) as active_players,
          COUNT(*) FILTER (WHERE is_active = true AND socket_id IS NOT NULL) as online_players
        FROM players
      `);

      return result.rows[0];
    } catch (error) {
      console.error('❌ DATABASE: Error getting player count:', error.message);
      return {
        total_players: 0,
        active_players: 0,
        online_players: 0
      };
    }
  }
}

module.exports = DatabasePlayer;