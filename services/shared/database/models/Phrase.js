class Phrase {
  constructor(id, content, senderId, targetId, createdAt = new Date(), theme = null) {
    this.id = id;
    this.content = content;
    this.senderId = senderId;
    this.targetId = targetId;
    this.createdAt = createdAt;
    this.isConsumed = false;
    this.theme = theme;
  }

  /**
   * Get public info (safe to send to clients)
   */
  getPublicInfo() {
    console.log(`🐛 DEBUG: getPublicInfo() for phrase "${this.content}" - targetId: ${this.targetId}, senderName: ${this.senderName || 'undefined'}, contributorName: ${this.contributorName || 'null'}, this.senderName: ${this.senderName || 'undefined'}, createdByPlayerId: ${this.createdByPlayerId || 'null'}`);
    return {
      id: this.id,
      content: this.content,
      senderId: this.senderId,
      targetId: this.targetId,
      createdAt: this.createdAt,
      isConsumed: this.isConsumed,
      theme: this.theme
    };
  }

  /**
   * Mark phrase as consumed (delivered/used)
   */
  consume() {
    this.isConsumed = true;
  }

  /**
   * Validate phrase content
   */
  static validateContent(content) {
    if (!content || typeof content !== 'string') {
      return { valid: false, error: 'Content must be a non-empty string' };
    }

    const trimmed = content.trim();
    if (trimmed.length === 0) {
      return { valid: false, error: 'Content cannot be empty' };
    }

    // Split into words and validate count (2-6 words)
    const words = trimmed.split(/\s+/);
    if (words.length < 2) {
      return { valid: false, error: 'Phrase must contain at least 2 words' };
    }
    if (words.length > 6) {
      return { valid: false, error: 'Phrase cannot contain more than 6 words' };
    }

    // Validate each word contains only letters, numbers, and basic punctuation
    const validWordPattern = /^[\p{L}\p{N}\-']+$/u;
    for (let word of words) {
      if (!validWordPattern.test(word)) {
        return { valid: false, error: 'Words can only contain letters, numbers, hyphens, and apostrophes' };
      }
    }

    return { valid: true, content: trimmed };
  }

  /**
   * Generate unique phrase ID
   */
  static generateId() {
    return 'phrase_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
  }
}

module.exports = Phrase;