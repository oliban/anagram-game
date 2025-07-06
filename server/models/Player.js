// Player model for in-memory storage
class Player {
  constructor(id, name, socketId) {
    this.id = id;
    this.name = name;
    this.socketId = socketId;
    this.connectedAt = new Date();
    this.lastActivity = new Date();
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