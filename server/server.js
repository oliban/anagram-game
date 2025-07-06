const express = require('express');
const cors = require('cors');
const { createServer } = require('http');
const { Server } = require('socket.io');
const PlayerStore = require('./models/PlayerStore');

const app = express();
const server = createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  },
  pingTimeout: 60000,    // 60 seconds (default is 20 seconds)
  pingInterval: 25000,   // 25 seconds (default is 10 seconds)
  upgradeTimeout: 30000, // 30 seconds for WebSocket upgrade
  allowUpgrades: true,   // Allow transport upgrades
  transports: ['websocket', 'polling'], // Support both transports
  allowEIO3: true        // Allow Engine.IO v3 clients
});
const PORT = process.env.PORT || 3000;

// Initialize player store
const playerStore = new PlayerStore();

// Middleware
app.use(cors({
  origin: "*", // Allow all origins for development
  methods: ["GET", "POST", "PUT", "DELETE"],
  credentials: true
}));
app.use(express.json());

// Basic logging middleware
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} - ${req.method} ${req.path}`);
  next();
});

// API Routes
app.get('/api/status', (req, res) => {
  res.json({ 
    status: 'online',
    timestamp: new Date().toISOString(),
    server: 'Anagram Game Multiplayer Server',
    players: playerStore.getPlayerCount()
  });
});

// Player registration endpoint
app.post('/api/players/register', (req, res) => {
  try {
    const { name, socketId } = req.body;
    
    // Validate input
    if (!name || typeof name !== 'string') {
      return res.status(400).json({ 
        error: 'Player name is required and must be a string' 
      });
    }
    
    // Validate name format
    const trimmedName = name.trim();
    if (trimmedName.length < 2 || trimmedName.length > 20) {
      return res.status(400).json({ 
        error: 'Player name must be between 2 and 20 characters' 
      });
    }
    
    // Check alphanumeric (allow spaces and basic punctuation)
    const validNamePattern = /^[a-zA-Z0-9\s\-_]+$/;
    if (!validNamePattern.test(trimmedName)) {
      return res.status(400).json({ 
        error: 'Player name can only contain letters, numbers, spaces, hyphens, and underscores' 
      });
    }
    
    // Check if name is already taken
    if (playerStore.isNameTaken(trimmedName)) {
      return res.status(409).json({ 
        error: 'Player name is already taken' 
      });
    }
    
    // Create player (socketId is optional at registration)
    const player = playerStore.addPlayer(trimmedName, socketId || null);
    
    // Broadcast new player joined event
    io.emit('player-joined', {
      player: player.getPublicInfo(),
      timestamp: new Date().toISOString()
    });
    
    res.status(201).json({
      success: true,
      player: player.getPublicInfo(),
      message: 'Player registered successfully'
    });
    
  } catch (error) {
    console.error('Registration error:', error);
    res.status(500).json({ 
      error: error.message || 'Registration failed' 
    });
  }
});

// Get online players
app.get('/api/players/online', (req, res) => {
  try {
    const onlinePlayers = playerStore.getOnlinePlayers();
    res.json({
      players: onlinePlayers,
      count: onlinePlayers.length,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('Error getting online players:', error);
    res.status(500).json({ 
      error: 'Failed to get online players' 
    });
  }
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Server error:', err);
  res.status(500).json({ 
    error: 'Internal server error',
    message: err.message 
  });
});

// Handle 404s
app.use('*', (req, res) => {
  res.status(404).json({ 
    error: 'Not found',
    path: req.originalUrl 
  });
});

// WebSocket connection handling
let connectedClients = 0;

io.on('connection', (socket) => {
  connectedClients++;
  const timestamp = new Date().toISOString();
  console.log(`🔌 SERVER: Client connected: ${socket.id} (Total: ${connectedClients}) at ${timestamp}`);
  console.log(`🔌 SERVER: Client remote address: ${socket.request.connection.remoteAddress}`);
  console.log(`🔌 SERVER: Client user agent: ${socket.request.headers['user-agent'] || 'Unknown'}`);
  
  // Monitor client readiness
  socket.on('connect', () => {
    console.log(`🔌 SERVER: Client ${socket.id} fully connected`);
  });
  
  // Monitor ping/pong for transport health
  socket.on('ping', () => {
    console.log(`🏓 SERVER: Ping received from ${socket.id}`);
  });
  
  socket.on('pong', () => {
    console.log(`🏓 SERVER: Pong received from ${socket.id}`);
  });
  
  // Monitor raw Socket.IO messages
  socket.onAny((event, ...args) => {
    console.log(`📨 SERVER: Received event '${event}' from ${socket.id}:`, args);
  });
  
  // Monitor connection errors
  socket.on('error', (error) => {
    console.log(`❌ SERVER: Socket error from ${socket.id}:`, error);
  });
  
  // Handle player joining with socket
  socket.on('player-connect', (data) => {
    try {
      const connectTimestamp = new Date().toISOString();
      console.log(`👤 SERVER: Player-connect event received at ${connectTimestamp}`);
      console.log(`👤 SERVER: Player-connect data:`, data);
      
      const { playerId } = data;
      const player = playerStore.getPlayer(playerId);
      
      if (player) {
        // Update player's socket ID
        player.socketId = socket.id;
        playerStore.socketToId.set(socket.id, playerId);
        player.updateActivity();
        
        console.log(`👤 SERVER: Player connected via socket: ${player.name} (${socket.id}) at ${connectTimestamp}`);
        
        // Broadcast updated player list
        io.emit('player-list-updated', {
          players: playerStore.getOnlinePlayers(),
          timestamp: new Date().toISOString()
        });
      } else {
        console.log(`❌ SERVER: Player not found for ID: ${playerId}`);
      }
    } catch (error) {
      console.error('❌ SERVER: Error handling player-connect:', error);
    }
  });
  
  socket.on('disconnect', (reason) => {
    connectedClients--;
    const timestamp = new Date().toISOString();
    
    console.log(`🔌 SERVER: Client disconnected: ${socket.id} (Total: ${connectedClients}) at ${timestamp}`);
    console.log(`🔌 SERVER: Disconnect reason: ${reason}`);
    
    // Handle player disconnect
    const player = playerStore.getPlayerBySocket(socket.id);
    if (player) {
      console.log(`👤 SERVER: Player socket disconnected: ${player.name} (${socket.id}) at ${timestamp}`);
      console.log(`👤 SERVER: Player disconnect reason: ${reason}`);
      
      // Remove player from store
      playerStore.removePlayerBySocket(socket.id);
      
      // Broadcast player left event
      io.emit('player-left', {
        player: player.getPublicInfo(),
        timestamp: new Date().toISOString()
      });
      
      // Broadcast updated player list
      io.emit('player-list-updated', {
        players: playerStore.getOnlinePlayers(),
        timestamp: new Date().toISOString()
      });
    } else {
      console.log(`🔌 SERVER: No player found for disconnected socket: ${socket.id}`);
    }
  });

  // Send welcome message
  socket.emit('welcome', { 
    message: 'Connected to Anagram Game Server',
    clientId: socket.id,
    timestamp: new Date().toISOString()
  });
});

// Cleanup inactive players every 5 minutes
setInterval(() => {
  const cleanedCount = playerStore.cleanupInactivePlayers();
  if (cleanedCount > 0) {
    // Broadcast updated player list after cleanup
    io.emit('player-list-updated', {
      players: playerStore.getOnlinePlayers(),
      timestamp: new Date().toISOString()
    });
  }
}, 5 * 60 * 1000); // 5 minutes

// Start server on all interfaces (0.0.0.0) so iPhone can connect
server.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Anagram Game Server running on port ${PORT}`);
  console.log(`📡 Status endpoint: http://localhost:${PORT}/api/status`);
  console.log(`🔌 WebSocket server ready for connections`);
});

module.exports = { app, server, io };