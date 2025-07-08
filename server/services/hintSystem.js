const { query } = require('../database/connection');

/**
 * Custom error class for hint validation errors
 */
class HintValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = 'HintValidationError';
  }
}

/**
 * Hint System Service
 * Manages the 3-tier progressive hint system with scoring
 */
class HintSystem {
  
  /**
   * Generate hint content based on hint level and phrase
   */
  static generateHintContent(phrase, hintLevel, originalHint) {
    const words = phrase.split(/\s+/);
    
    switch (hintLevel) {
      case 1:
        // Level 1: Word count indication
        return `This phrase has ${words.length} word${words.length > 1 ? 's' : ''}`;
        
      case 2:
        // Level 2: Show the original hint that came with the phrase
        return originalHint;
        
      case 3:
        // Level 3: First letters of each word
        const firstLetters = words.map(word => word.charAt(0).toUpperCase()).join(' ');
        return `First letters: ${firstLetters}`;
        
      default:
        throw new Error('Invalid hint level. Must be 1, 2, or 3.');
    }
  }
  
  /**
   * Calculate score for each hint level based on difficulty
   */
  static calculateScoreForHintLevel(difficultyScore, hintsUsed) {
    let score = difficultyScore;
    
    if (hintsUsed >= 1) score = Math.round(difficultyScore * 0.90);
    if (hintsUsed >= 2) score = Math.round(difficultyScore * 0.70);
    if (hintsUsed >= 3) score = Math.round(difficultyScore * 0.50);
    
    return score;
  }
  
  /**
   * Get score preview for each hint level
   */
  static getScorePreview(difficultyScore) {
    return {
      noHints: difficultyScore,
      level1: Math.round(difficultyScore * 0.90),
      level2: Math.round(difficultyScore * 0.70),
      level3: Math.round(difficultyScore * 0.50)
    };
  }
  
  /**
   * Use a hint for a player on a specific phrase
   */
  static async useHint(playerId, phraseId, hintLevel) {
    try {
      // Validate hint level
      if (hintLevel < 1 || hintLevel > 3) {
        throw new Error('Invalid hint level. Must be 1, 2, or 3.');
      }
      
      // Use database function to record hint usage
      const result = await query(`
        SELECT use_hint_for_player($1, $2, $3) as success
      `, [playerId, phraseId, hintLevel]);
      
      if (!result.rows[0].success) {
        throw new HintValidationError('Must use hints in order (1, 2, 3). Use previous hint level first.');
      }
      
      // Get phrase details for hint generation
      const phraseResult = await query(`
        SELECT content, hint, difficulty_level 
        FROM phrases 
        WHERE id = $1
      `, [phraseId]);
      
      if (phraseResult.rows.length === 0) {
        throw new Error('Phrase not found');
      }
      
      const phrase = phraseResult.rows[0];
      
      // Generate hint content
      const hintContent = this.generateHintContent(
        phrase.content, 
        hintLevel, 
        phrase.hint
      );
      
      // Get current hint status
      const hintStatus = await this.getHintStatus(playerId, phraseId);
      
      // Calculate score preview for button
      const scorePreview = this.getScorePreview(phrase.difficulty_level);
      
      console.log(`🔍 HINT: Player ${playerId} used level ${hintLevel} hint for phrase "${phrase.content}"`);
      
      return {
        success: true,
        hintLevel,
        hintContent,
        currentScore: this.calculateScoreForHintLevel(phrase.difficulty_level, hintLevel),
        nextHintScore: hintLevel < 3 ? this.calculateScoreForHintLevel(phrase.difficulty_level, hintLevel + 1) : null,
        hintsRemaining: Math.max(0, 3 - hintLevel),
        scorePreview,
        canUseNextHint: hintLevel < 3
      };
      
    } catch (error) {
      console.error('❌ HINT: Error using hint:', error.message);
      throw error;
    }
  }
  
  /**
   * Get hint status for a player's phrase
   */
  static async getHintStatus(playerId, phraseId) {
    try {
      const result = await query(`
        SELECT hint_level, used_at
        FROM hint_usage
        WHERE player_id = $1 AND phrase_id = $2
        ORDER BY hint_level
      `, [playerId, phraseId]);
      
      const hintsUsed = result.rows;
      const maxHintLevel = hintsUsed.length > 0 ? Math.max(...hintsUsed.map(h => h.hint_level)) : 0;
      
      // Get phrase difficulty for score calculation
      const phraseResult = await query(`
        SELECT difficulty_level FROM phrases WHERE id = $1
      `, [phraseId]);
      
      if (phraseResult.rows.length === 0) {
        throw new Error('Phrase not found');
      }
      
      const difficultyLevel = phraseResult.rows[0].difficulty_level;
      const scorePreview = this.getScorePreview(difficultyLevel);
      
      return {
        hintsUsed: hintsUsed.map(h => ({
          level: h.hint_level,
          usedAt: h.used_at
        })),
        nextHintLevel: maxHintLevel < 3 ? maxHintLevel + 1 : null,
        hintsRemaining: Math.max(0, 3 - maxHintLevel),
        currentScore: this.calculateScoreForHintLevel(difficultyLevel, maxHintLevel),
        nextHintScore: maxHintLevel < 3 ? this.calculateScoreForHintLevel(difficultyLevel, maxHintLevel + 1) : null,
        scorePreview,
        canUseNextHint: maxHintLevel < 3
      };
      
    } catch (error) {
      console.error('❌ HINT: Error getting hint status:', error.message);
      throw error;
    }
  }
  
  /**
   * Complete phrase with hint-based scoring
   */
  static async completePhrase(playerId, phraseId, completionTime = 0) {
    try {
      const result = await query(`
        SELECT success, final_score, hints_used
        FROM complete_phrase_for_player_with_hints($1, $2, $3)
      `, [playerId, phraseId, completionTime]);
      
      if (result.rows.length === 0 || !result.rows[0].success) {
        throw new Error('Failed to complete phrase');
      }
      
      const completion = result.rows[0];
      
      console.log(`✅ COMPLETION: Player ${playerId} completed phrase with ${completion.hints_used} hints, score: ${completion.final_score}`);
      
      return {
        success: true,
        finalScore: completion.final_score,
        hintsUsed: completion.hints_used,
        completionTime
      };
      
    } catch (error) {
      console.error('❌ COMPLETION: Error completing phrase:', error.message);
      throw error;
    }
  }
  
  /**
   * Get phrase with hint preview for UI
   */
  static async getPhraseWithHintPreview(phraseId, playerId) {
    try {
      // Get phrase details
      const phraseResult = await query(`
        SELECT id, content, hint, difficulty_level, is_global, created_by_player_id
        FROM phrases 
        WHERE id = $1
      `, [phraseId]);
      
      if (phraseResult.rows.length === 0) {
        throw new Error('Phrase not found');
      }
      
      const phrase = phraseResult.rows[0];
      
      // Get hint status for this player
      const hintStatus = await this.getHintStatus(playerId, phraseId);
      
      return {
        ...phrase,
        hintStatus,
        scorePreview: hintStatus.scorePreview
      };
      
    } catch (error) {
      console.error('❌ HINT: Error getting phrase with hint preview:', error.message);
      throw error;
    }
  }
}

module.exports = { HintSystem, HintValidationError };