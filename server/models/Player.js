// Player model for in-memory storage
class Player {
  constructor(id, name, socketId) {
    this.id = id;
    this.name = name;
    this.socketId = socketId;
    this.connectedAt = new Date();
    this.lastActivity = new Date();
    this.skipBucket = new Set(); // Track skipped phrase IDs
  }

  // Update player's last activity timestamp
  updateActivity() {
    this.lastActivity = new Date();
  }

  // Check if player is considered active (connected recently)
  isActive() {
    const now = new Date();
    const fiveMinutesAgo = new Date(now.getTime() - 5 * 60 * 1000);
    return this.lastActivity > fiveMinutesAgo;
  }

  // Check if a phrase is skipped by this player
  isSkipped(phraseId) {
    return this.skipBucket.has(phraseId);
  }

  // Add a phrase to the skip bucket
  skipPhrase(phraseId) {
    this.skipBucket.add(phraseId);
  }

  // Get all skipped phrase IDs for this player
  getSkippedPhrases() {
    return Array.from(this.skipBucket);
  }

  // Clear the skip bucket (useful for testing or reset)
  clearSkipBucket() {
    this.skipBucket.clear();
  }

  // Get public player info (without sensitive data)
  getPublicInfo() {
    return {
      id: this.id,
      name: this.name,
      connectedAt: this.connectedAt,
      isActive: this.isActive()
    };
  }
}

module.exports = Player;