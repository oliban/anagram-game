// Load environment variables
require('dotenv').config();

const express = require('express');
const cors = require('cors');
const { createServer } = require('http');
const { Server } = require('socket.io');

// Database modules
const { testConnection, getStats: getDbStats, shutdown: shutdownDb, pool } = require('./database/connection');
const DatabasePlayer = require('./models/DatabasePlayer');
const DatabasePhrase = require('./models/DatabasePhrase');

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


// Database initialization flag
let isDatabaseConnected = false;

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
app.get('/api/status', async (req, res) => {
  try {
    if (!isDatabaseConnected) {
      return res.status(503).json({
        status: 'database_unavailable',
        timestamp: new Date().toISOString(),
        error: 'Database connection required for operation'
      });
    }
    
    const dbStats = await getDbStats();
    const phraseStats = await DatabasePhrase.getStats();
    
    // Add pool statistics
    const poolStats = {
      poolSize: pool.totalCount,
      maxPoolSize: pool.options.max,
      idleCount: pool.idleCount,
      waitingCount: pool.waitingCount,
      connected: true
    };
    
    res.json({ 
      status: 'online',
      timestamp: new Date().toISOString(),
      server: 'Anagram Game Multiplayer Server',
      database: { ...dbStats, ...poolStats },
      phrases: phraseStats
    });
  } catch (error) {
    console.error('❌ STATUS: Error generating status:', error.message);
    res.status(500).json({
      status: 'error',
      timestamp: new Date().toISOString(),
      error: 'Failed to generate status'
    });
  }
});

// Player registration endpoint
app.post('/api/players/register', async (req, res) => {
  try {
    if (!isDatabaseConnected) {
      return res.status(503).json({
        error: 'Database connection required for player registration'
      });
    }
    
    const { name, socketId } = req.body;
    
    // Validate input
    if (!name || typeof name !== 'string') {
      return res.status(400).json({ 
        error: 'Player name is required and must be a string' 
      });
    }
    
    const player = await DatabasePlayer.createPlayer(name, socketId || null);
    console.log(`👤 Player registered: ${player.name} (${player.id})`);
    
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
    console.error('❌ Registration error:', error);
    
    // Handle specific validation errors as 400 (client errors)
    if (error.message.includes('Player name') || 
        error.message.includes('must be between') ||
        error.message.includes('can only contain') ||
        error.message.includes('is required')) {
      return res.status(400).json({ 
        error: error.message 
      });
    }
    
    // Handle database conflicts
    if (error.message.includes('already taken') || error.message.includes('duplicate')) {
      return res.status(409).json({ 
        error: 'Player name is already taken' 
      });
    }
    
    res.status(500).json({ 
      error: error.message || 'Registration failed' 
    });
  }
});

// Get online players
app.get('/api/players/online', async (req, res) => {
  try {
    if (!isDatabaseConnected) {
      return res.status(503).json({
        error: 'Database connection required for player data'
      });
    }
    
    const dbPlayers = await DatabasePlayer.getOnlinePlayers();
    const onlinePlayers = dbPlayers.map(player => player.getPublicInfo());
    
    res.json({
      players: onlinePlayers,
      count: onlinePlayers.length,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ Error getting online players:', error);
    res.status(500).json({ 
      error: 'Failed to get online players' 
    });
  }
});

// Phrase API endpoints
app.post('/api/phrases', async (req, res) => {
  try {
    const { content, senderId, targetId } = req.body;
    
    // Validate required fields
    if (!content || !senderId || !targetId) {
      return res.status(400).json({ 
        error: 'Content, senderId, and targetId are required' 
      });
    }
    
    // Validate that sender and target are different
    if (senderId === targetId) {
      return res.status(400).json({ 
        error: 'Cannot send phrase to yourself' 
      });
    }
    
    // Validate that both sender and target exist
    const sender = await DatabasePlayer.getPlayerById(senderId);
    const target = await DatabasePlayer.getPlayerById(targetId);
    
    if (!sender) {
      return res.status(404).json({ 
        error: 'Sender player not found' 
      });
    }
    
    if (!target) {
      return res.status(404).json({ 
        error: 'Target player not found' 
      });
    }
    
    // Create phrase in database
    const phrase = await DatabasePhrase.createPhrase({
      content,
      senderId,
      targetId,
      hint: req.body.hint || null // Optional hint support
    });
    
    console.log(`📝 Phrase created: "${content}" from ${sender.name} to ${target.name}`);
    
    // Send real-time notification to target player
    if (target.socketId) {
      io.to(target.socketId).emit('new-phrase', {
        phrase: phrase.getPublicInfo(),
        senderName: sender.name,
        timestamp: new Date().toISOString()
      });
      console.log(`📨 Sent new-phrase notification to ${target.name} (${target.socketId})`);
    } else {
      console.log(`📨 Target player ${target.name} not connected - phrase queued`);
    }
    
    res.status(201).json({
      success: true,
      phrase: phrase.getPublicInfo(),
      message: 'Phrase created successfully'
    });
    
  } catch (error) {
    console.error('Error creating phrase:', error);
    
    // Handle phrase validation errors as 400 (client errors)
    if (error.message.includes('cannot contain more than') ||
        error.message.includes('too short') ||
        error.message.includes('too long') ||
        error.message.includes('invalid characters')) {
      return res.status(400).json({ 
        error: error.message 
      });
    }
    
    res.status(500).json({ 
      error: error.message || 'Failed to create phrase' 
    });
  }
});

// Enhanced phrase creation endpoint (Phase 4.1)
app.post('/api/phrases/create', async (req, res) => {
  try {
    if (!isDatabaseConnected) {
      return res.status(503).json({
        error: 'Database connection required for phrase creation'
      });
    }

    const {
      content,
      hint,
      senderId,
      targetIds = [],
      isGlobal = false,
      difficultyLevel = 1,
      phraseType = 'custom',
      priority = 1
    } = req.body;

    // Validate required fields
    if (!content) {
      return res.status(400).json({
        error: 'Content is required'
      });
    }

    if (!senderId) {
      return res.status(400).json({
        error: 'Sender ID is required'
      });
    }

    // Validate sender exists
    const sender = await DatabasePlayer.getPlayerById(senderId);
    if (!sender) {
      return res.status(404).json({
        error: 'Sender player not found'
      });
    }

    // Validate target players if provided
    const validTargets = [];
    if (targetIds.length > 0) {
      for (const targetId of targetIds) {
        const target = await DatabasePlayer.getPlayerById(targetId);
        if (!target) {
          return res.status(404).json({
            error: `Target player ${targetId} not found`
          });
        }
        if (target.id === senderId) {
          return res.status(400).json({
            error: 'Cannot target yourself'
          });
        }
        validTargets.push(target);
      }
    }

    // Create enhanced phrase
    const result = await DatabasePhrase.createEnhancedPhrase({
      content,
      hint,
      senderId,
      targetIds,
      isGlobal,
      difficultyLevel,
      phraseType,
      priority
    });

    const { phrase, targetCount, isGlobal: phraseIsGlobal } = result;

    console.log(`📝 Enhanced phrase created: "${content}" from ${sender.name}${phraseIsGlobal ? ' (global)' : ` to ${targetCount} players`}`);

    // Send real-time notifications to target players
    const notifications = [];
    for (const target of validTargets) {
      if (target.socketId) {
        io.to(target.socketId).emit('new-phrase', {
          phrase: phrase.getPublicInfo(),
          senderName: sender.name,
          timestamp: new Date().toISOString()
        });
        notifications.push(target.name);
        console.log(`📨 Sent enhanced phrase notification to ${target.name} (${target.socketId})`);
      }
    }

    // Enhanced response format
    res.status(201).json({
      success: true,
      phrase: {
        ...phrase.getPublicInfo(),
        senderInfo: {
          id: sender.id,
          name: sender.name
        }
      },
      targeting: {
        isGlobal: phraseIsGlobal,
        targetCount,
        notificationsSent: notifications.length
      },
      message: 'Enhanced phrase created successfully'
    });

  } catch (error) {
    console.error('Error creating enhanced phrase:', error);

    // Handle validation errors as 400 (client errors)
    if (error.message.includes('Validation failed') ||
        error.message.includes('Difficulty level must be') ||
        error.message.includes('Invalid phrase type')) {
      return res.status(400).json({
        error: error.message
      });
    }

    res.status(500).json({
      error: error.message || 'Failed to create enhanced phrase'
    });
  }
});

// Global Phrase Bank endpoint (Phase 4.2)
app.get('/api/phrases/global', async (req, res) => {
  try {
    if (!isDatabaseConnected) {
      return res.status(503).json({
        error: 'Database connection required for phrase data'
      });
    }

    // Parse query parameters with defaults
    const rawLimit = parseInt(req.query.limit) || 50;
    const limit = Math.min(Math.max(rawLimit, 1), 100); // Ensure positive and max 100 phrases per request
    const offset = Math.max(parseInt(req.query.offset) || 0, 0); // Ensure non-negative
    const rawDifficulty = parseInt(req.query.difficulty);
    const difficulty = (rawDifficulty >= 1 && rawDifficulty <= 5) ? rawDifficulty : null; // Only valid difficulties
    const approved = req.query.approved !== 'false'; // Default to approved only

    console.log(`🌍 REQUEST: Global phrases - limit: ${limit}, offset: ${offset}, difficulty: ${difficulty || 'all'}, approved: ${approved}`);

    // Get global phrases with optional filtering
    const phrases = await DatabasePhrase.getGlobalPhrases(limit, offset, difficulty, approved);
    
    // Get total count for pagination
    const totalCount = await DatabasePhrase.getGlobalPhrasesCount(difficulty, approved);

    // Enhanced response with pagination metadata
    res.json({
      success: true,
      phrases: phrases.map(phrase => ({
        id: phrase.id,
        content: phrase.content,
        hint: phrase.hint,
        difficultyLevel: phrase.difficultyLevel,
        phraseType: phrase.phraseType,
        priority: phrase.priority,
        usageCount: phrase.usageCount,
        isApproved: phrase.isApproved,
        createdAt: phrase.createdAt,
        createdByName: phrase.createdByName || 'Anonymous'
      })),
      pagination: {
        limit,
        offset,
        total: totalCount,
        count: phrases.length,
        hasMore: offset + phrases.length < totalCount
      },
      filters: {
        difficulty: difficulty || 'all',
        approved
      },
      timestamp: new Date().toISOString()
    });

    console.log(`✅ DATABASE: Returned ${phrases.length} global phrases (${totalCount} total)`);

  } catch (error) {
    console.error('❌ Error getting global phrases:', error);
    res.status(500).json({
      error: 'Failed to retrieve global phrases'
    });
  }
});

app.get('/api/phrases/for/:playerId', async (req, res) => {
  try {
    if (!isDatabaseConnected) {
      return res.status(503).json({
        error: 'Database connection required for phrase data'
      });
    }
    
    const { playerId } = req.params;
    
    // Validate that player exists in database
    const player = await DatabasePlayer.getPlayerById(playerId);
    if (!player) {
      return res.status(404).json({ 
        error: 'Player not found' 
      });
    }
    
    // Get phrases for player from database
    const phrases = await DatabasePhrase.getPhrasesForPlayer(playerId);
    
    res.json({
      phrases: phrases.map(p => p.getPublicInfo()),
      count: phrases.length,
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    console.error('❌ Error getting phrases for player:', error);
    res.status(500).json({ 
      error: 'Failed to get phrases' 
    });
  }
});

app.post('/api/phrases/:phraseId/consume', async (req, res) => {
  try {
    const { phraseId } = req.params;
    
    const success = await DatabasePhrase.consumePhrase(phraseId);
    
    if (success) {
      console.log(`✅ Phrase consumed: ${phraseId}`);
      res.json({
        success: true,
        message: 'Phrase marked as consumed'
      });
    } else {
      res.status(404).json({ 
        error: 'Phrase not found or already consumed' 
      });
    }
    
  } catch (error) {
    console.error('Error consuming phrase:', error);
    res.status(500).json({ 
      error: 'Failed to consume phrase' 
    });
  }
});

// Skip phrase endpoint
app.post('/api/phrases/:phraseId/skip', async (req, res) => {
  try {
    if (!isDatabaseConnected) {
      return res.status(503).json({
        error: 'Database connection required for phrase operations'
      });
    }
    
    const { phraseId } = req.params;
    const { playerId } = req.body;
    
    // Validate player exists
    const player = await DatabasePlayer.getPlayerById(playerId);
    if (!player) {
      return res.status(404).json({ 
        error: 'Player not found' 
      });
    }
    
    // Skip the phrase in database
    const success = await DatabasePhrase.skipPhrase(playerId, phraseId);
    
    if (!success) {
      return res.status(404).json({ 
        error: 'Phrase not found or already processed' 
      });
    }
    
    console.log(`⏭️ Phrase skipped: ${phraseId} by player ${player.name} (${playerId})`);
    
    res.json({
      success: true,
      message: 'Phrase skipped successfully'
    });
    
  } catch (error) {
    console.error('Error skipping phrase:', error);
    res.status(500).json({ 
      error: 'Failed to skip phrase' 
    });
  }
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Server error:', err);
  
  // Handle JSON parsing errors as 400 (client errors)
  if (err.type === 'entity.parse.failed' || err.message.includes('JSON')) {
    return res.status(400).json({ 
      error: 'Invalid JSON format',
      message: 'Request body must be valid JSON'
    });
  }
  
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
  socket.on('player-connect', async (data) => {
    try {
      if (!isDatabaseConnected) {
        console.log(`❌ Database not connected for player-connect: ${socket.id}`);
        return;
      }
      
      const connectTimestamp = new Date().toISOString();
      console.log(`👤 Player-connect event received at ${connectTimestamp}`);
      console.log(`👤 Player-connect data:`, data);
      
      const { playerId } = data;
      
      try {
        const player = await DatabasePlayer.updateSocketId(playerId, socket.id);
        
        if (player) {
          console.log(`👤 Player connected via socket: ${player.name} (${socket.id})`);
          
          const onlinePlayers = (await DatabasePlayer.getOnlinePlayers()).map(p => p.getPublicInfo());
          io.emit('player-list-updated', {
            players: onlinePlayers,
            timestamp: new Date().toISOString()
          });
        } else {
          console.log(`❌ Player not found for ID: ${playerId}`);
        }
      } catch (dbError) {
        console.log(`❌ Invalid player ID format or player not found: ${playerId}`);
        // Client needs to re-register with proper player registration
      }
      
    } catch (error) {
      console.error('❌ Error handling player-connect:', error);
    }
  });
  
  socket.on('disconnect', async (reason) => {
    connectedClients--;
    const timestamp = new Date().toISOString();
    
    console.log(`🔌 Client disconnected: ${socket.id} (Total: ${connectedClients})`);
    console.log(`🔌 Disconnect reason: ${reason}`);
    
    if (!isDatabaseConnected) {
      console.log(`❌ Database not connected for disconnect: ${socket.id}`);
      return;
    }
    
    try {
      const player = await DatabasePlayer.setPlayerInactive(socket.id);
      if (player) {
        console.log(`👤 Player disconnected: ${player.name} (${socket.id})`);
        
        const onlinePlayers = (await DatabasePlayer.getOnlinePlayers()).map(p => p.getPublicInfo());
        
        // Broadcast player left event
        io.emit('player-left', {
          player: player.getPublicInfo(),
          timestamp: new Date().toISOString()
        });
        
        // Broadcast updated player list
        io.emit('player-list-updated', {
          players: onlinePlayers,
          timestamp: new Date().toISOString()
        });
      } else {
        console.log(`🔌 No player found for disconnected socket: ${socket.id}`);
      }
    } catch (error) {
      console.error('❌ Error handling disconnect:', error);
    }
  });

  // Send welcome message
  socket.emit('welcome', { 
    message: 'Connected to Anagram Game Server',
    clientId: socket.id,
    timestamp: new Date().toISOString()
  });
});

// Cleanup inactive players and old phrases every 5 minutes
setInterval(async () => {
  if (!isDatabaseConnected) {
    return; // Skip cleanup if database not available
  }
  
  try {
    const cleanedPlayersCount = await DatabasePlayer.cleanupInactivePlayers();
    // Note: Phrase cleanup not yet implemented for database - will be added in Phase 4
    
    if (cleanedPlayersCount > 0) {
      console.log(`🧹 Cleaned up ${cleanedPlayersCount} inactive players`);
      const onlinePlayers = (await DatabasePlayer.getOnlinePlayers()).map(p => p.getPublicInfo());
      io.emit('player-list-updated', {
        players: onlinePlayers,
        timestamp: new Date().toISOString()
      });
    }
  } catch (error) {
    console.error('❌ Cleanup error:', error);
  }
}, 5 * 60 * 1000); // 5 minutes

// Database initialization function
async function initializeDatabase() {
  console.log('🔄 Initializing database connection...');
  
  try {
    const connected = await testConnection();
    if (connected) {
      isDatabaseConnected = true;
      console.log('✅ Database connection established');
      console.log('📊 Database-powered phrase system ready');
    } else {
      console.log('❌ Database connection failed');
      isDatabaseConnected = false;
    }
  } catch (error) {
    console.error('❌ Database initialization error:', error.message);
    isDatabaseConnected = false;
  }
}

// Graceful shutdown handler
async function gracefulShutdown(signal) {
  console.log(`\n🛑 Received ${signal}. Starting graceful shutdown...`);
  
  try {
    // Close server
    server.close(() => {
      console.log('✅ HTTP server closed');
    });
    
    // Close database connections
    if (isDatabaseConnected) {
      await shutdownDb();
    }
    
    console.log('✅ Graceful shutdown complete');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error during shutdown:', error);
    process.exit(1);
  }
}

// Register shutdown handlers
process.on('SIGINT', () => gracefulShutdown('SIGINT'));
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));

// Start server with database initialization
async function startServer() {
  try {
    // Initialize database first
    await initializeDatabase();
    
    // Start server on all interfaces (0.0.0.0) so iPhone can connect
    server.listen(PORT, '0.0.0.0', () => {
      console.log(`🚀 Anagram Game Server running on port ${PORT}`);
      console.log(`📡 Status endpoint: http://localhost:${PORT}/api/status`);
      console.log(`🔌 WebSocket server ready for connections`);
      console.log(`💾 Database mode: ${isDatabaseConnected ? 'PostgreSQL' : 'In-Memory Fallback'}`);
    });
  } catch (error) {
    console.error('❌ Server startup failed:', error);
    process.exit(1);
  }
}

// Start the server
startServer();

module.exports = { app, server, io };