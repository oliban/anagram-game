const { query, transaction } = require('../connection');
const { calculateScore, LANGUAGES } = require('../../services/difficultyScorer');

/**
 * DatabasePhrase model implementing the new phrase system with hints and targeting
 * This replaces the old in-memory PhraseStore with persistent database storage
 */
class DatabasePhrase {
  constructor(data) {
    this.id = data.id;
    this.content = data.content;
    this.hint = data.hint;
    this.difficultyLevel = data.difficulty_level || 1;
    this.isGlobal = data.is_global || false;
    this.createdByPlayerId = data.created_by_player_id;
    this.createdAt = data.created_at;
    this.isApproved = data.is_approved || false;
    this.usageCount = data.usage_count || 0;
    this.phraseType = data.phrase_type || 'custom';
    this.language = data.language || LANGUAGES.ENGLISH;
  }

  /**
   * Get public info (safe to send to clients)
   * Includes backward compatibility fields
   */
  getPublicInfo() {
    const publicInfo = {
      id: this.id,
      content: this.content,
      hint: this.hint,
      difficultyLevel: this.difficultyLevel,
      isGlobal: this.isGlobal,
      language: this.language,
      phraseType: this.phraseType,
      usageCount: this.usageCount,
      createdAt: this.createdAt ? this.createdAt.toISOString() : new Date().toISOString(),
      // Legacy fields for backward compatibility
      senderId: this.senderId || this.createdByPlayerId || 'system',
      senderName: this.senderName || 'Unknown Player',
      targetId: this.targetId,
      isConsumed: this.isConsumed || false
    };
    
    // Debug logging to see what targetId is being sent
    console.log(`🐛 DEBUG: getPublicInfo() for phrase "${this.content}" - targetId: ${this.targetId || 'null'}, senderName: ${this.senderName || 'Unknown Player'}`);
    
    return publicInfo;
  }

  /**
   * Validate phrase content and hint
   */
  static validatePhrase(content, hint) {
    const errors = [];

    // Validate content
    if (!content || typeof content !== 'string') {
      errors.push('Content must be a non-empty string');
    } else {
      const trimmed = content.trim();
      if (trimmed.length === 0) {
        errors.push('Content cannot be empty');
      } else {
        // Split into words and validate count (2-6 words)
        const words = trimmed.split(/\s+/);
        if (words.length < 2) {
          errors.push('Phrase must contain at least 2 words');
        }
        if (words.length > 6) {
          errors.push('Phrase cannot contain more than 6 words');
        }

        // Validate each word contains only letters, numbers, and basic punctuation
        const validWordPattern = /^[\p{L}\p{N}\-']+$/u;
        for (let word of words) {
          if (!validWordPattern.test(word)) {
            errors.push('Words can only contain letters, numbers, hyphens, and apostrophes');
            break;
          }
        }
      }
    }

    // Validate hint (allow empty hints for iOS compatibility)
    if (hint !== undefined && hint !== null && typeof hint !== 'string') {
      errors.push('Hint must be a string');
    } else {
      const trimmedHint = (hint || '').trim();  // Default to empty string if hint is null/undefined
      if (trimmedHint.length > 300) {
        errors.push('Hint cannot be longer than 300 characters');
      }
      
      // Check that hint doesn't contain the exact answer words (only words longer than 5 chars)
      // This prevents giving away the answer while allowing common words like "test", "word", etc.
      if (trimmedHint.length > 0) {  // Only validate if hint is provided
        const contentLower = content.toLowerCase();
        const hintLower = trimmedHint.toLowerCase();
      const words = contentLower.split(/\s+/);
      
      // Skip common words that are reasonable to use in hints
      const allowedCommonWords = ['test', 'word', 'words', 'phrase', 'message', 'challenge', 'custom', 'global', 'community'];
      
      for (let word of words) {
        if (word.length > 5 && !allowedCommonWords.includes(word) && 
            (hintLower.includes(` ${word} `) || hintLower.includes(` ${word}`) || hintLower.includes(`${word} `))) {
          errors.push('Hint should not contain exact words from the phrase');
          break;
        }
      }
    }
    }

    return {
      valid: errors.length === 0,
      errors,
      content: content ? content.trim() : '',
      hint: hint ? hint.trim() : ''
    };
  }

  /**
   * Calculate automatic difficulty score (1-100) from phrase content
   * Uses statistical analysis via difficultyScorer with full score range
   */
  static calculateDifficultyScore(content, language = LANGUAGES.ENGLISH) {
    try {
      // Get statistical score (1-100) - use directly
      const score = calculateScore({ phrase: content, language });
      
      console.log(`📊 DIFFICULTY: "${content}" -> Score: ${score}/100`);
      return score;
    } catch (error) {
      console.error('📊 DIFFICULTY: Error calculating difficulty, defaulting to score 1:', error.message);
      return 1;
    }
  }

  /**
   * Create a new phrase in the database (simplified for existing API)
   */
  static async createPhrase(options) {
    const {
      content,
      senderId,
      targetId,
      hint,
      language = LANGUAGES.ENGLISH,
      contributionLinkId = null
    } = options;

    // Basic validation
    if (!content || typeof content !== 'string' || content.trim().length === 0) {
      throw new Error('Content must be a non-empty string');
    }
    
    const cleanContent = content.trim();
    
    // Generate automatic hint if none provided
    const cleanHint = hint || (() => {
      const words = cleanContent.split(/\s+/);
      return words.length > 1 ? `Unscramble these ${words.length} words` : 'Unscramble this word';
    })();

    // Calculate automatic difficulty score (1-100)
    const difficultyScore = this.calculateDifficultyScore(cleanContent);

    try {
      // Use transaction to ensure both phrase creation and assignment are atomic
      return await transaction(async (client) => {
        // Create the phrase
        const result = await client.query(`
          INSERT INTO phrases (content, hint, difficulty_level, is_global, created_by_player_id, is_approved, language, contribution_link_id)
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
          RETURNING *
        `, [cleanContent, cleanHint, difficultyScore, false, senderId, true, language, contributionLinkId]);

        const phraseData = result.rows[0];
        console.log(`📝 DATABASE: Phrase created - "${phraseData.content}" with hint: "${phraseData.hint}"`);
        
        const phrase = new DatabasePhrase(phraseData);
        
        // If this is a targeted phrase, assign it to the target player within the same transaction
        if (targetId) {
          await client.query(`
            INSERT INTO player_phrases (phrase_id, target_player_id)
            VALUES ($1, $2)
            ON CONFLICT DO NOTHING
          `, [phrase.id, targetId]);
          console.log(`🎯 DATABASE: Phrase ${phrase.id} assigned to player ${targetId} within transaction`);
        }
        
        return phrase;
      });
    } catch (error) {
      console.error('❌ DATABASE: Error creating phrase:', error.message);
      throw new Error('Failed to create phrase');
    }
  }

  /**
   * Get phrase by ID
   */
  static async getPhraseById(phraseId) {
    try {
      const result = await query(`
        SELECT * FROM phrases WHERE id = $1
      `, [phraseId]);

      if (result.rows.length === 0) {
        console.log(`❌ DATABASE: Phrase ${phraseId} not found`);
        return null;
      }

      const phrase = new DatabasePhrase(result.rows[0]);
      console.log(`✅ DATABASE: Found phrase ${phraseId} - "${phrase.content}"`);
      return phrase;
    } catch (error) {
      console.error('❌ DATABASE: Error getting phrase by ID:', error.message);
      return null;
    }
  }

  /**
   * Get phrases for a player (backward compatible with old PhraseStore API)
   * Returns targeted phrases first, then global phrases if no targeted phrases available
   */
  static async getPhrasesForPlayer(playerId, maxDifficulty = null) {
    try {
      // First, get targeted phrases (NO difficulty filtering - targeted phrases should always be delivered)
      const targetedResult = await query(`
        SELECT 
          p.id,
          p.content,
          p.hint,
          p.difficulty_level,
          p.is_global,
          p.language,
          p.created_by_player_id as "senderId",
          COALESCE(pl.name, 'Unknown Player') as "senderName",
          pp.target_player_id as "targetId",
          false as "isConsumed",
          'targeted' as phrase_type
        FROM phrases p
        JOIN player_phrases pp ON p.id = pp.phrase_id
        LEFT JOIN players pl ON p.created_by_player_id = pl.id
        LEFT JOIN players pl2 ON FALSE
        WHERE pp.target_player_id = $1 
          AND pp.is_delivered = false
          AND p.id NOT IN (SELECT phrase_id FROM skipped_phrases WHERE player_id = $1)
        ORDER BY p.created_at ASC
        LIMIT 10
      `, [playerId]);

      let phrases = targetedResult.rows.map(row => {
        const phrase = new DatabasePhrase({
          id: row.id,
          content: row.content,
          hint: row.hint,
          difficulty_level: row.difficulty_level,
          is_global: row.is_global,
          created_by_player_id: row.senderId,
          phrase_type: row.phrase_type,
          language: row.language
        });
        
        // Add legacy properties for backward compatibility
        phrase.senderId = row.senderId;
        phrase.senderName = row.senderName;
        phrase.targetId = row.targetId;
        phrase.isConsumed = row.isConsumed;
        
        return phrase;
      });

      // If no targeted phrases, get global phrases
      if (phrases.length === 0) {
        // For global phrases, $1 appears 3 times, so difficulty parameter is $2
        // Include NULL check to exclude phrases without difficulty scores
        const globalDifficultyFilter = maxDifficulty ? `AND p.difficulty_level IS NOT NULL AND p.difficulty_level <= $2` : '';
        const globalParams = maxDifficulty ? [playerId, maxDifficulty] : [playerId];
        const globalResult = await query(`
          SELECT 
            p.id,
            p.content,
            p.hint,
            p.difficulty_level,
            p.is_global,
            p.language,
            p.created_by_player_id as "senderId",
            COALESCE(pl.name, 'Unknown Player') as "senderName",
            null as "targetId",
            false as "isConsumed",
            'global' as phrase_type
          FROM phrases p
          LEFT JOIN players pl ON p.created_by_player_id = pl.id
          LEFT JOIN players pl2 ON FALSE
          WHERE p.is_global = true 
            AND p.is_approved = true
            AND (p.created_by_player_id IS NULL OR p.created_by_player_id != $1)
            AND p.id NOT IN (SELECT phrase_id FROM completed_phrases WHERE player_id = $1)
            AND p.id NOT IN (SELECT phrase_id FROM skipped_phrases WHERE player_id = $1)
            ${globalDifficultyFilter}
          ORDER BY RANDOM()
          LIMIT 10
        `, globalParams);

        phrases = globalResult.rows.map(row => {
          const phrase = new DatabasePhrase({
            id: row.id,
            content: row.content,
            hint: row.hint,
            difficulty_level: row.difficulty_level,
            is_global: row.is_global,
            created_by_player_id: row.senderId,
            phrase_type: row.phrase_type,
            language: row.language
          });
          
          // Add legacy properties for backward compatibility
          phrase.senderId = row.senderId;
          phrase.senderName = row.senderName;
          phrase.targetId = row.targetId;
          phrase.isConsumed = row.isConsumed;
          
          return phrase;
        });

        console.log(`📋 DATABASE: Found ${phrases.length} global phrases for player ${playerId} (no targeted phrases available)`);
        
        // Debug: Log difficulty levels of returned phrases if level filtering was applied
        if (maxDifficulty && phrases.length > 0) {
          const difficulties = phrases.map(p => p.difficultyLevel || 'NULL').join(', ');
          console.log(`🔍 DATABASE_DEBUG: Returned phrase difficulties: [${difficulties}] (max allowed: ${maxDifficulty})`);
        }
      } else {
        console.log(`📋 DATABASE: Found ${phrases.length} targeted phrases for player ${playerId}`);
        
        // Debug: Log difficulty levels of targeted phrases (no filtering applied)
        if (phrases.length > 0) {
          const difficulties = phrases.map(p => p.difficultyLevel || 'NULL').join(', ');
          console.log(`🎯 TARGETED_DEBUG: Targeted phrase difficulties: [${difficulties}] (no level filtering - all delivered)`);
        }
      }

      return phrases;
    } catch (error) {
      console.error('❌ DATABASE: Error getting phrases for player:', error.message);
      return [];
    }
  }

  /**
   * Get next phrase for a player using the database function
   */
  static async getNextPhraseForPlayer(playerId) {
    try {
      const result = await query(`
        SELECT * FROM get_next_phrase_for_player($1)
      `, [playerId]);

      if (result.rows.length === 0) {
        console.log(`📭 DATABASE: No phrases available for player ${playerId}`);
        return null;
      }

      const phraseData = result.rows[0];
      const phrase = new DatabasePhrase({
        id: phraseData.phrase_id,
        content: phraseData.content,
        hint: phraseData.hint,
        difficulty_level: phraseData.difficulty_level,
        phrase_type: phraseData.phrase_type
      });

      console.log(`✅ DATABASE: Found ${phraseData.phrase_type} phrase for player: "${phrase.content}"`);
      return phrase;
    } catch (error) {
      console.error('❌ DATABASE: Error getting next phrase:', error.message);
      return null;
    }
  }

  /**
   * Consume/complete a phrase (backward compatible with old PhraseStore API)
   */
  static async consumePhrase(phraseId) {
    try {
      // Mark the phrase as delivered/consumed in player_phrases
      const result = await query(`
        UPDATE player_phrases 
        SET is_delivered = true, delivered_at = CURRENT_TIMESTAMP
        WHERE phrase_id = $1 AND is_delivered = false
        RETURNING *
      `, [phraseId]);

      if (result.rows.length > 0) {
        console.log(`✅ DATABASE: Phrase ${phraseId} marked as consumed`);
        return true;
      } else {
        console.log(`❌ DATABASE: Phrase ${phraseId} not found or already consumed`);
        return false;
      }
    } catch (error) {
      console.error('❌ DATABASE: Error consuming phrase:', error.message);
      return false;
    }
  }

  /**
   * Mark phrase as completed for a player
   */
  static async completePhrase(playerId, phraseId, score = 0, completionTime = 0) {
    try {
      const result = await query(`
        SELECT complete_phrase_for_player($1, $2, $3, $4) as success
      `, [playerId, phraseId, score, completionTime]);

      const success = result.rows[0].success;
      if (success) {
        console.log(`✅ DATABASE: Phrase ${phraseId} completed by player ${playerId}`);
      } else {
        console.log(`❌ DATABASE: Failed to mark phrase ${phraseId} as completed for player ${playerId}`);
      }

      return success;
    } catch (error) {
      console.error('❌ DATABASE: Error completing phrase:', error.message);
      return false;
    }
  }

  /**
   * Skip phrase for a player
   */
  static async skipPhrase(playerId, phraseId) {
    try {
      const result = await query(`
        SELECT skip_phrase_for_player($1, $2) as success
      `, [playerId, phraseId]);

      const success = result.rows[0].success;
      if (success) {
        console.log(`⏭️ DATABASE: Phrase ${phraseId} skipped by player ${playerId}`);
      }

      return success;
    } catch (error) {
      console.error('❌ DATABASE: Error skipping phrase:', error.message);
      return false;
    }
  }

  /**
   * Assign phrase to specific players (targeting)
   */
  static async assignPhraseToPlayers(phraseId, targetPlayerIds) {
    try {
      await transaction(async (client) => {
        for (const playerId of targetPlayerIds) {
          await client.query(`
            INSERT INTO player_phrases (phrase_id, target_player_id)
            VALUES ($1, $2)
            ON CONFLICT DO NOTHING
          `, [phraseId, playerId]);
        }
      });

      console.log(`🎯 DATABASE: Phrase ${phraseId} assigned to ${targetPlayerIds.length} players`);
      return true;
    } catch (error) {
      console.error('❌ DATABASE: Error assigning phrase:', error.message);
      return false;
    }
  }

  /**
   * Get phrase statistics
   */
  static async getStats() {
    try {
      const result = await query(`
        SELECT 
          COUNT(*) as total_phrases,
          COUNT(*) FILTER (WHERE is_global = true AND is_approved = true) as global_phrases,
          COUNT(*) FILTER (WHERE is_global = false) as targeted_phrases,
          AVG(usage_count) as avg_usage,
          MAX(usage_count) as max_usage
        FROM phrases
      `);

      return result.rows[0];
    } catch (error) {
      console.error('❌ DATABASE: Error getting phrase stats:', error.message);
      return {
        total_phrases: 0,
        global_phrases: 0,
        targeted_phrases: 0,
        avg_usage: 0,
        max_usage: 0
      };
    }
  }

  /**
   * Get all global phrases with optional filtering (Phase 4.2 + 4.7.3)
   */
  static async getGlobalPhrases(limit = 50, offset = 0, difficulty = null, approved = true, minDifficulty = null, maxDifficulty = null) {
    try {
      let whereClause = 'WHERE p.is_global = true';
      const params = [];
      let paramIndex = 1;

      // Legacy difficulty filter (exact match, 1-5 range)
      if (difficulty !== null && difficulty >= 1 && difficulty <= 5) {
        whereClause += ` AND p.difficulty_level = $${paramIndex}`;
        params.push(difficulty);
        paramIndex++;
      }

      // New difficulty range filters (1+ range, no upper limit)
      if (minDifficulty !== null && minDifficulty >= 1) {
        whereClause += ` AND p.difficulty_level >= $${paramIndex}`;
        params.push(minDifficulty);
        paramIndex++;
      }

      if (maxDifficulty !== null && maxDifficulty >= 1) {
        whereClause += ` AND p.difficulty_level <= $${paramIndex}`;
        params.push(maxDifficulty);
        paramIndex++;
      }

      // Add approval filter
      if (approved !== null) {
        whereClause += ` AND p.is_approved = $${paramIndex}`;
        params.push(approved);
        paramIndex++;
      }

      // Add limit and offset
      params.push(limit);
      params.push(offset);

      const result = await query(`
        SELECT p.*, pl.name as created_by_name
        FROM phrases p
        LEFT JOIN players pl ON p.created_by_player_id = pl.id
        ${whereClause}
        ORDER BY p.created_at DESC
        LIMIT $${paramIndex} OFFSET $${paramIndex + 1}
      `, params);

      return result.rows.map(row => {
        const phrase = new DatabasePhrase(row);
        phrase.createdByName = row.created_by_name;
        return phrase;
      });
    } catch (error) {
      console.error('❌ DATABASE: Error getting global phrases:', error.message);
      return [];
    }
  }

  /**
   * Get count of global phrases with optional filtering (Phase 4.2 + 4.7.3)
   */
  static async getGlobalPhrasesCount(difficulty = null, approved = true, minDifficulty = null, maxDifficulty = null) {
    try {
      let whereClause = 'WHERE is_global = true';
      const params = [];
      let paramIndex = 1;

      // Legacy difficulty filter (exact match, 1-5 range)
      if (difficulty !== null && difficulty >= 1 && difficulty <= 5) {
        whereClause += ` AND difficulty_level = $${paramIndex}`;
        params.push(difficulty);
        paramIndex++;
      }

      // New difficulty range filters (1+ range, no upper limit)
      if (minDifficulty !== null && minDifficulty >= 1) {
        whereClause += ` AND difficulty_level >= $${paramIndex}`;
        params.push(minDifficulty);
        paramIndex++;
      }

      if (maxDifficulty !== null && maxDifficulty >= 1) {
        whereClause += ` AND difficulty_level <= $${paramIndex}`;
        params.push(maxDifficulty);
        paramIndex++;
      }

      // Add approval filter
      if (approved !== null) {
        whereClause += ` AND is_approved = $${paramIndex}`;
        params.push(approved);
        paramIndex++;
      }

      const result = await query(`
        SELECT COUNT(*) as total
        FROM phrases
        ${whereClause}
      `, params);

      return parseInt(result.rows[0].total) || 0;
    } catch (error) {
      console.error('❌ DATABASE: Error counting global phrases:', error.message);
      return 0;
    }
  }

  /**
   * Approve a global phrase
   */
  static async approvePhrase(phraseId) {
    try {
      const result = await query(`
        UPDATE phrases 
        SET is_approved = true 
        WHERE id = $1 AND is_global = true
        RETURNING *
      `, [phraseId]);

      if (result.rows.length > 0) {
        console.log(`✅ DATABASE: Phrase ${phraseId} approved for global use`);
        return true;
      } else {
        console.log(`❌ DATABASE: Phrase ${phraseId} not found or not global`);
        return false;
      }
    } catch (error) {
      console.error('❌ DATABASE: Error approving phrase:', error.message);
      return false;
    }
  }

  /**
   * Get offline phrases for a player (for mobile offline mode)
   */
  static async getOfflinePhrases(playerId, count = 10) {
    try {
      const result = await query(`
        SELECT p.*
        FROM phrases p
        WHERE p.is_global = true 
          AND p.is_approved = true
          AND p.created_by_player_id != $1
          AND p.id NOT IN (SELECT phrase_id FROM completed_phrases WHERE player_id = $1)
          AND p.id NOT IN (SELECT phrase_id FROM skipped_phrases WHERE player_id = $1)
          AND p.id NOT IN (SELECT phrase_id FROM offline_phrases WHERE player_id = $1)
        ORDER BY RANDOM()
        LIMIT $2
      `, [playerId, count]);

      const phrases = result.rows.map(row => new DatabasePhrase(row));

      // Record the download
      if (phrases.length > 0) {
        await transaction(async (client) => {
          for (const phrase of phrases) {
            await client.query(`
              INSERT INTO offline_phrases (player_id, phrase_id)
              VALUES ($1, $2)
              ON CONFLICT DO NOTHING
            `, [playerId, phrase.id]);
          }
        });

        console.log(`📱 DATABASE: ${phrases.length} offline phrases downloaded for player ${playerId}`);
      }

      return phrases;
    } catch (error) {
      console.error('❌ DATABASE: Error getting offline phrases:', error.message);
      return [];
    }
  }

  /**
   * Enhanced phrase creation with comprehensive options (Phase 4.1)
   * Supports global phrases, multi-player targeting, and advanced hint validation
   */
  static async createEnhancedPhrase(options) {
    const {
      content,
      hint,
      senderId,
      targetIds = [], // Array for multi-player targeting
      isGlobal = false,
      phraseType = 'custom',
      language = LANGUAGES.ENGLISH // Language parameter for LanguageTile feature
    } = options;

    // Comprehensive validation
    const validation = this.validatePhrase(content, hint);
    if (!validation.valid) {
      throw new Error(`Validation failed: ${validation.errors.join(', ')}`);
    }

    const cleanContent = validation.content;
    const cleanHint = validation.hint;

    // Calculate automatic difficulty score (1-100)
    const difficultyScore = this.calculateDifficultyScore(cleanContent, language);

    // Validate phrase type
    const validTypes = ['custom', 'global', 'community', 'challenge'];
    if (!validTypes.includes(phraseType)) {
      throw new Error(`Invalid phrase type. Must be one of: ${validTypes.join(', ')}`);
    }

    try {
      return await transaction(async (client) => {
        // Create the phrase
        const phraseResult = await client.query(`
          INSERT INTO phrases (content, hint, difficulty_level, is_global, created_by_player_id, phrase_type, language)
          VALUES ($1, $2, $3, $4, $5, $6, $7)
          RETURNING *
        `, [cleanContent, cleanHint, difficultyScore, isGlobal, senderId, phraseType, language]);

        const phrase = new DatabasePhrase(phraseResult.rows[0]);

        // Handle targeting
        let targetCount = 0;
        if (isGlobal) {
          // Global phrases are available to all players
          console.log(`🌍 DATABASE: Global phrase created - "${cleanContent}"`);
        } else if (targetIds.length > 0) {
          // Multi-player targeting
          for (const targetId of targetIds) {
            await client.query(`
              INSERT INTO player_phrases (target_player_id, phrase_id)
              VALUES ($1, $2)
              ON CONFLICT DO NOTHING
            `, [targetId, phrase.id]);
            targetCount++;
          }
          console.log(`🎯 DATABASE: Phrase ${phrase.id} assigned to ${targetCount} players`);
        }

        console.log(`📝 DATABASE: Enhanced phrase created - "${cleanContent}" with hint: "${cleanHint}"`);
        return {
          phrase,
          targetCount,
          isGlobal
        };
      });
    } catch (error) {
      console.error('❌ DATABASE: Error creating enhanced phrase:', error.message);
      throw error;
    }
  }
}

module.exports = DatabasePhrase;