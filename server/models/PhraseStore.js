const Phrase = require('./Phrase');

class PhraseStore {
  constructor() {
    this.phrases = new Map(); // id -> Phrase
    this.playerPhrases = new Map(); // playerId -> Set of phrase IDs
  }

  /**
   * Create a new phrase
   */
  createPhrase(content, senderId, targetId) {
    // Validate content
    const validation = Phrase.validateContent(content);
    if (!validation.valid) {
      throw new Error(validation.error);
    }

    // Generate unique ID
    const id = Phrase.generateId();

    // Create phrase
    const phrase = new Phrase(id, validation.content, senderId, targetId);
    
    // Store phrase
    this.phrases.set(id, phrase);

    // Add to target player's phrases
    if (!this.playerPhrases.has(targetId)) {
      this.playerPhrases.set(targetId, new Set());
    }
    this.playerPhrases.get(targetId).add(id);

    return phrase;
  }

  /**
   * Get phrase by ID
   */
  getPhrase(id) {
    return this.phrases.get(id);
  }

  /**
   * Get all phrases for a specific player
   */
  getPhrasesForPlayer(playerId, playerStore = null) {
    const phraseIds = this.playerPhrases.get(playerId) || new Set();
    const phrases = [];
    
    // Get player instance to check skip bucket
    const player = playerStore ? playerStore.getPlayer(playerId) : null;
    
    for (let id of phraseIds) {
      const phrase = this.phrases.get(id);
      if (phrase && !phrase.isConsumed) {
        // If player exists, filter out skipped phrases
        if (!player || !player.isSkipped(id)) {
          phrases.push(phrase);
        }
      }
    }

    return phrases;
  }

  /**
   * Get skipped phrases for a player (when all regular phrases are exhausted)
   */
  getSkippedPhrasesForPlayer(playerId, playerStore = null) {
    const phraseIds = this.playerPhrases.get(playerId) || new Set();
    const skippedPhrases = [];
    
    // Get player instance to check skip bucket
    const player = playerStore ? playerStore.getPlayer(playerId) : null;
    
    if (!player) {
      return skippedPhrases;
    }
    
    for (let id of phraseIds) {
      const phrase = this.phrases.get(id);
      if (phrase && !phrase.isConsumed && player.isSkipped(id)) {
        skippedPhrases.push(phrase);
      }
    }

    return skippedPhrases;
  }

  /**
   * Get next unconsumed phrase for a player
   */
  getNextPhraseForPlayer(playerId, playerStore = null) {
    // First try to get regular (non-skipped) phrases
    const phrases = this.getPhrasesForPlayer(playerId, playerStore);
    if (phrases.length > 0) {
      return phrases[0];
    }
    
    // If no regular phrases, get from skip bucket
    const skippedPhrases = this.getSkippedPhrasesForPlayer(playerId, playerStore);
    return skippedPhrases.length > 0 ? skippedPhrases[0] : null;
  }

  /**
   * Mark phrase as consumed
   */
  consumePhrase(phraseId) {
    const phrase = this.phrases.get(phraseId);
    if (phrase) {
      phrase.consume();
      return true;
    }
    return false;
  }

  /**
   * Get phrase count for a player
   */
  getPhraseCountForPlayer(playerId) {
    const phrases = this.getPhrasesForPlayer(playerId);
    return phrases.length;
  }

  /**
   * Get all phrases (for debugging)
   */
  getAllPhrases() {
    return Array.from(this.phrases.values());
  }

  /**
   * Clean up old consumed phrases (older than 24 hours)
   */
  cleanupOldPhrases() {
    const now = new Date();
    const oneDayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);
    let cleanedCount = 0;

    for (let [id, phrase] of this.phrases) {
      if (phrase.isConsumed && phrase.createdAt < oneDayAgo) {
        // Remove from main phrases map
        this.phrases.delete(id);
        
        // Remove from player phrases set
        const playerPhrases = this.playerPhrases.get(phrase.targetId);
        if (playerPhrases) {
          playerPhrases.delete(id);
          if (playerPhrases.size === 0) {
            this.playerPhrases.delete(phrase.targetId);
          }
        }
        
        cleanedCount++;
      }
    }

    return cleanedCount;
  }

  /**
   * Remove all phrases for a player (when player leaves)
   */
  removePhrasesForPlayer(playerId) {
    const phraseIds = this.playerPhrases.get(playerId) || new Set();
    let removedCount = 0;

    for (let id of phraseIds) {
      this.phrases.delete(id);
      removedCount++;
    }

    this.playerPhrases.delete(playerId);
    return removedCount;
  }

  /**
   * Get stats
   */
  getStats() {
    const totalPhrases = this.phrases.size;
    const consumedPhrases = Array.from(this.phrases.values()).filter(p => p.isConsumed).length;
    const activePhrases = totalPhrases - consumedPhrases;

    return {
      totalPhrases,
      consumedPhrases,
      activePhrases,
      playersWithPhrases: this.playerPhrases.size
    };
  }
}

module.exports = PhraseStore;