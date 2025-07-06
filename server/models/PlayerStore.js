const Player = require('./Player');

class PlayerStore {
  constructor() {
    this.players = new Map(); // Map<playerId, Player>
    this.nameToId = new Map(); // Map<playerName, playerId> for quick lookups
    this.socketToId = new Map(); // Map<socketId, playerId> for socket management
  }

  // Generate unique player ID
  generatePlayerId() {
    return 'player_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
  }

  // Check if player name is already taken
  isNameTaken(name) {
    return this.nameToId.has(name.toLowerCase());
  }

  // Add a new player
  addPlayer(name, socketId) {
    if (this.isNameTaken(name)) {
      throw new Error('Player name already taken');
    }

    const playerId = this.generatePlayerId();
    const player = new Player(playerId, name, socketId);
    
    this.players.set(playerId, player);
    this.nameToId.set(name.toLowerCase(), playerId);
    this.socketToId.set(socketId, playerId);
    
    console.log(`👤 Player registered: ${name} (${playerId})`);
    return player;
  }

  // Get player by ID
  getPlayer(playerId) {
    return this.players.get(playerId);
  }

  // Get player by name
  getPlayerByName(name) {
    const playerId = this.nameToId.get(name.toLowerCase());
    return playerId ? this.players.get(playerId) : null;
  }

  // Get player by socket ID
  getPlayerBySocket(socketId) {
    const playerId = this.socketToId.get(socketId);
    return playerId ? this.players.get(playerId) : null;
  }

  // Remove player (on disconnect)
  removePlayer(playerId) {
    const player = this.players.get(playerId);
    if (player) {
      this.players.delete(playerId);
      this.nameToId.delete(player.name.toLowerCase());
      this.socketToId.delete(player.socketId);
      console.log(`👤 Player disconnected: ${player.name} (${playerId})`);
      return player;
    }
    return null;
  }

  // Remove player by socket ID
  removePlayerBySocket(socketId) {
    const playerId = this.socketToId.get(socketId);
    if (playerId) {
      return this.removePlayer(playerId);
    }
    return null;
  }

  // Get all online players
  getOnlinePlayers() {
    return Array.from(this.players.values())
      .filter(player => player.isActive())
      .map(player => player.getPublicInfo());
  }

  // Get player count
  getPlayerCount() {
    return this.players.size;
  }

  // Update player activity
  updatePlayerActivity(playerId) {
    const player = this.players.get(playerId);
    if (player) {
      player.updateActivity();
    }
  }

  // Cleanup inactive players (called periodically)
  cleanupInactivePlayers() {
    const inactivePlayers = [];
    for (const [playerId, player] of this.players) {
      if (!player.isActive()) {
        inactivePlayers.push(playerId);
      }
    }
    
    inactivePlayers.forEach(playerId => this.removePlayer(playerId));
    
    if (inactivePlayers.length > 0) {
      console.log(`🧹 Cleaned up ${inactivePlayers.length} inactive players`);
    }
    
    return inactivePlayers.length;
  }
}

module.exports = PlayerStore;