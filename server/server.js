// Load environment variables only if .env file exists (local development)
const fs = require('fs');
const path = require('path');
if (fs.existsSync(path.join(__dirname, '.env'))) {
  require('dotenv').config();
}

const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const { createServer } = require('http');
const { Server } = require('socket.io');

// Database modules
const { testConnection, getStats: getDbStats, shutdown: shutdownDb, pool, query } = require('./database/connection');
const DatabasePlayer = require('./models/DatabasePlayer');
const DatabasePhrase = require('./models/DatabasePhrase');
const ScoringSystem = require('./services/scoringSystem');
const ConfigService = require('./services/config-service');
const RouteAnalytics = require('../services/shared/services/routeAnalytics');

// Swagger documentation setup
const swaggerUi = require('swagger-ui-express');
const swaggerFile = require('./swagger-output.json');

// Web dashboard modules

const app = express();
const server = createServer(app);

// Initialize configuration service
const configService = new ConfigService(pool);
const routeAnalytics = new RouteAnalytics('game-server');

// CORS configuration - secure but development-friendly
const isDevelopment = process.env.NODE_ENV === 'development';
const isSecurityRelaxed = process.env.SECURITY_RELAXED === 'true';

// In development with SECURITY_RELAXED, or when SECURITY_RELAXED is true in staging, allow all origins
const corsOptions = (isDevelopment && isSecurityRelaxed) || isSecurityRelaxed ? {
  origin: true, // Allow all origins in relaxed mode
  methods: ["GET", "POST"],
  credentials: true
} : {
  origin: function (origin, callback) {
    const allowedOrigins = isDevelopment 
      ? ['http://localhost:3000', 'http://localhost:3001', 'http://localhost:3002', 
         'http://192.168.1.133:3000', 'http://192.168.1.133:3001', 'http://192.168.1.133:3002',
         'http://192.168.1.188:3000', 'http://192.168.1.188:3001', 'http://192.168.1.188:3002']
      : ['https://your-production-domain.com', 'https://anagram-staging-alb-1354034851.eu-west-1.elb.amazonaws.com'];
    
    // Allow requests with no origin (mobile apps, curl, iOS simulator)
    if (!origin) {
      callback(null, true);
      return;
    }
    
    // Allow explicitly listed origins
    if (allowedOrigins.indexOf(origin) !== -1) {
      callback(null, true);
      return;
    }
    
    // In staging/production, also allow any Cloudflare tunnel URL
    if (!isDevelopment && origin.includes('.trycloudflare.com')) {
      console.log(`✅ CORS: Allowing Cloudflare tunnel origin: ${origin}`);
      callback(null, true);
      return;
    }
    
    // Check if origin matches the dynamic tunnel URL from environment
    if (process.env.DYNAMIC_TUNNEL_URL && origin === process.env.DYNAMIC_TUNNEL_URL) {
      console.log(`✅ CORS: Allowing dynamic tunnel origin: ${origin}`);
      callback(null, true);
      return;
    }
    
    if (process.env.LOG_SECURITY_EVENTS === 'true') {
      console.log(`🚫 CORS: Blocked origin: ${origin}`);
    }
    callback(new Error('Not allowed by CORS'));
  },
  methods: ["GET", "POST"],
  credentials: true
};

// Log CORS configuration for debugging
console.log('🔧 CORS Configuration:', {
  isDevelopment,
  isSecurityRelaxed,
  corsMode: (isDevelopment && isSecurityRelaxed) || isSecurityRelaxed ? 'RELAXED (origin: true)' : 'RESTRICTED'
});

// Rate limiting configuration
const skipRateLimits = process.env.SKIP_RATE_LIMITS === 'true';

// General API rate limiter - realistic for word game usage
const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: isDevelopment ? 300 : 30, // ~20-2 requests per minute (generous for development)
  message: { error: 'Too many requests, please try again later.' },
  standardHeaders: true,
  legacyHeaders: false,
  skip: () => skipRateLimits
});

// Strict rate limiter for sensitive endpoints (phrase creation, etc.)
const strictLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: isDevelopment ? 100 : 10, // ~7-0.7 requests per minute (more generous for development)
  message: { error: 'Rate limit exceeded for sensitive endpoint.' },
  standardHeaders: true,
  legacyHeaders: false,
  skip: () => skipRateLimits
});

console.log('🛡️ Rate Limiting Configuration:', {
  skipRateLimits,
  apiLimit: isDevelopment ? 300 : 30,
  strictLimit: isDevelopment ? 100 : 10
});

// WebSocket security configuration
const hasApiKey = !!process.env.ADMIN_API_KEY;
console.log('🔌 WebSocket Security Configuration:', {
  monitoringAuthRequired: !isSecurityRelaxed || !isDevelopment,
  gameNamespaceOpen: true, // Always open for iOS apps
  apiKeyConfigured: hasApiKey
});

const io = new Server(server, {
  cors: corsOptions,
  pingTimeout: 120000,   // 2 minutes (increased for mobile apps)
  pingInterval: 30000,   // 30 seconds (longer intervals for battery)
  upgradeTimeout: 30000, // 30 seconds for WebSocket upgrade
  allowUpgrades: true,   // Allow transport upgrades
  transports: ['websocket', 'polling'], // Support both transports
  allowEIO3: true,       // Allow Engine.IO v3 clients
  maxHttpBufferSize: 1e6, // 1MB buffer for large messages
  httpCompression: true,  // Enable compression
  perMessageDeflate: true // Enable per-message compression
});
const PORT = process.env.PORT || 3000;

// Create monitoring namespace for dashboard with authentication
const monitoringNamespace = io.of('/monitoring');

// Add authentication middleware to monitoring namespace  
monitoringNamespace.use((socket, next) => {
  const isDevelopment = process.env.NODE_ENV === 'development';
  const isSecurityRelaxed = process.env.SECURITY_RELAXED === 'true';
  
  // Skip auth in relaxed development mode
  if (isDevelopment && isSecurityRelaxed) {
    if (process.env.LOG_SECURITY_EVENTS === 'true') {
      console.log('🔓 WEBSOCKET: Bypassing monitoring auth in relaxed development mode');
    }
    return next();
  }

  // Check for API key in handshake auth
  const apiKey = socket.handshake.auth?.apiKey || socket.handshake.query?.apiKey;
  const expectedKey = process.env.ADMIN_API_KEY;

  if (process.env.LOG_SECURITY_EVENTS === 'true') {
    console.log('🔑 WEBSOCKET: Monitoring namespace auth attempt', {
      hasApiKey: !!apiKey,
      socketId: socket.id,
      ip: socket.handshake.address
    });
  }

  if (!expectedKey) {
    console.error('❌ WEBSOCKET: ADMIN_API_KEY not configured for monitoring');
    return next(new Error('Server configuration error'));
  }

  if (!apiKey || apiKey !== expectedKey) {
    if (process.env.LOG_SECURITY_EVENTS === 'true') {
      console.log('🚫 WEBSOCKET: Invalid or missing API key for monitoring namespace');
    }
    return next(new Error('Authentication required for monitoring dashboard'));
  }

  if (process.env.LOG_SECURITY_EVENTS === 'true') {
    console.log('✅ WEBSOCKET: Monitoring authentication successful');
  }
  next();
});

monitoringNamespace.on('connection', (socket) => {
  console.log(`📊 MONITORING: Authenticated dashboard connected: ${socket.id}`);
  
  // Send initial connection confirmation
  socket.emit('connected', {
    message: 'Connected to monitoring dashboard',
    timestamp: new Date().toISOString()
  });
  
  // Handle monitoring stats request
  socket.on('request-stats', async () => {
    try {
      if (isDatabaseConnected) {
        const stats = await getMonitoringStats();
        socket.emit('stats', stats);
        
        // Also send initial players and phrases data
        const players = await DatabasePlayer.getOnlinePlayers();
        const phrases = await getRecentPhrases();
        
        socket.emit('players', players.map(p => p.getPublicInfo()));
        socket.emit('phrases', phrases);
        
        // Send a test activity event to verify the connection works
        socket.emit('activity', {
          type: 'system',
          message: 'Test activity event on connection',
          details: { socketId: socket.id },
          timestamp: new Date().toISOString()
        });
        console.log(`🧪 TEST: Sent test activity to socket ${socket.id}`);
      }
    } catch (error) {
      console.error('❌ MONITORING: Error getting stats:', error);
    }
  });
  
  // Emit activity events to monitoring dashboard
  socket.on('request-activity', () => {
    socket.emit('activity', {
      type: 'system',
      message: 'Monitoring dashboard connected',
      timestamp: new Date().toISOString()
    });
  });
  
  socket.on('disconnect', () => {
    console.log(`📊 MONITORING: Dashboard disconnected: ${socket.id}`);
  });
});

// Helper function to get monitoring stats
async function getMonitoringStats() {
  try {
    const [playersResult, phrasesResult, todayPhrasesResult] = await Promise.all([
      query('SELECT COUNT(*) as count FROM players WHERE is_active = true'),
      query('SELECT COUNT(*) as count FROM phrases WHERE is_global = true AND is_approved = true'),
      query(`SELECT COUNT(*) as count FROM phrases WHERE created_at >= CURRENT_DATE`)
    ]);

    return {
      players: {
        online: parseInt(playersResult.rows[0]?.count) || 0,
        total: parseInt(playersResult.rows[0]?.count) || 0
      },
      phrases: {
        global: parseInt(phrasesResult.rows[0]?.count) || 0,
        today: parseInt(todayPhrasesResult.rows[0]?.count) || 0
      },
      timestamp: new Date().toISOString()
    };
  } catch (error) {
    console.error('Error getting monitoring stats:', error);
    return {
      players: { online: 0, total: 0 },
      phrases: { global: 0, today: 0 },
      timestamp: new Date().toISOString()
    };
  }
}

// Helper function to get recent phrases
async function getRecentPhrases() {
  try {
    const result = await query(`
      SELECT 
        p.id, 
        p.content as text,
        p.difficulty_level as difficulty,
        p.language,
        p.created_at,
        p.hint,
        pl.name as author_name,
        CASE WHEN p.is_approved THEN 'approved' ELSE 'pending' END as status
      FROM phrases p
      LEFT JOIN players pl ON p.created_by_player_id = pl.id
      WHERE p.created_at > NOW() - INTERVAL '24 hours'
      ORDER BY p.created_at DESC
      LIMIT 10
    `);
    
    return result.rows.map(row => ({
      id: row.id,
      text: row.text,
      difficulty: row.difficulty,
      language: row.language,
      createdAt: row.created_at,
      hint: row.hint,
      authorName: row.author_name || 'System',
      status: row.status
    }));
  } catch (error) {
    console.error('Error getting recent phrases:', error);
    return [];
  }
}

// Database initialization flag
let isDatabaseConnected = false;

// Function to broadcast activity to monitoring dashboard
function broadcastActivity(type, message, details = null) {
  const activity = {
    type,
    message,
    details,
    timestamp: new Date().toISOString()
  };
  
  // Send to all connected monitoring clients
  const connectedClients = monitoringNamespace.sockets.size;
  console.log(`📊 ACTIVITY: ${type} - ${message} (broadcasting to ${connectedClients} clients)`);
  
  // Emit to the namespace
  monitoringNamespace.emit('activity', activity);
  console.log(`📡 NAMESPACE: Activity emitted to monitoring namespace`);
  
  // Also emit directly to each connected socket for debugging
  let socketCount = 0;
  monitoringNamespace.sockets.forEach((socket) => {
    socket.emit('activity', activity);
    socketCount++;
    console.log(`📤 DIRECT: Activity sent to socket ${socket.id}`);
  });
  
  console.log(`📡 MONITORING: Sent to ${socketCount} connected monitoring sockets`);
}

// Middleware
app.set('trust proxy', true); // Trust nginx reverse proxy headers
app.use(cors(corsOptions));
app.use(express.json());
app.use(express.static('public'));

// Apply rate limiting to API routes - TEMPORARILY DISABLED FOR TESTING
// app.use('/api', apiLimiter);

// Route analytics middleware (only for API routes)
app.use('/api', routeAnalytics.createMiddleware());

// Swagger API documentation
app.use('/api-docs', swaggerUi.serve, swaggerUi.setup(swaggerFile));

// Function to get current route dependencies (called at runtime)
const getRouteDependencies = () => ({
  getDatabaseStatus: () => isDatabaseConnected,
  getDbStats,
  configService,
  DatabasePlayer,
  DatabasePhrase,
  ScoringSystem,
  broadcastActivity,
  io,
  query,
  pool,
  getMonitoringStats
});

// Import route modules (but don't initialize them yet)
const systemRoutesFactory = require('./routes/system');
const playerRoutesFactory = require('./routes/players');
// const phraseRoutesFactory = require('./routes/phrases'); // REMOVED: Duplicate phrases routes - using game-server version
const contributionRoutesFactory = require('./routes/contributions');
const leaderboardRoutesFactory = require('./routes/leaderboards');
const debugRoutesFactory = require('./routes/debug');
const adminRoutesFactory = require('./routes/admin');

// Serve static assets for contribution pages
app.use('/contribute', express.static(path.join(__dirname, 'public/contribute')));





// Initialize and use route modules after dependencies are ready
const initializeRoutes = () => {
  const deps = getRouteDependencies();
  app.use(systemRoutesFactory(deps));
  app.use(playerRoutesFactory(deps));
  // app.use(phraseRoutesFactory(deps)); // REMOVED: Using game-server phrases routes instead
  app.use(contributionRoutesFactory(deps));
  app.use(leaderboardRoutesFactory(deps));
  app.use(debugRoutesFactory(deps));
  // MOVED: app.use(adminRoutesFactory(deps)); - Admin routes moved to Web Dashboard Service (port 3001)
};

// Call this after database initialization
initializeRoutes();

// Handle 404s
app.use('*', (req, res) => {
  res.status(404).json({ 
    error: 'Not found',
    path: req.originalUrl 
  });
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

// WebSocket connection handling
let connectedClients = 0;

io.on('connection', (socket) => {
  connectedClients++;
  const timestamp = new Date().toISOString();
  const handshake = socket.handshake;
  
  console.log(`🔌 SERVER: Client connected: ${socket.id} (Total: ${connectedClients}) at ${timestamp}`);
  console.log(`🔌 SERVER: Client remote address: ${socket.request.connection.remoteAddress}`);
  console.log(`🔌 SERVER: Client user agent: ${socket.request.headers['user-agent'] || 'Unknown'}`);
  console.log(`🔌 SERVER: Connection query params:`, handshake.query);
  console.log(`🔌 SERVER: Connection auth payload:`, handshake.auth);
  
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
  
  // Handle iOS app lifecycle events
  socket.on('app-backgrounded', async () => {
    console.log(`📱 SERVER: App backgrounded for ${socket.id}`);
    // Update last_seen but keep connection active for longer
    if (isDatabaseConnected) {
      try {
        await DatabasePlayer.updateLastSeen(socket.id);
        console.log(`📱 SERVER: Updated last_seen for backgrounded app ${socket.id}`);
      } catch (error) {
        console.log(`❌ Error updating last_seen for backgrounded app: ${error.message}`);
      }
    }
  });
  
  socket.on('app-foregrounded', async () => {
    console.log(`📱 SERVER: App foregrounded for ${socket.id}`);
    // Refresh player status and reconnect
    if (isDatabaseConnected) {
      try {
        await DatabasePlayer.setPlayerActive(socket.id);
        const onlinePlayers = (await DatabasePlayer.getOnlinePlayers()).map(p => p.getPublicInfo());
        socket.emit('player-list-updated', {
          players: onlinePlayers,
          timestamp: new Date().toISOString()
        });
      } catch (error) {
        console.log(`❌ Error handling app foreground: ${error.message}`);
      }
    }
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
        socket.emit('connection-error', { error: 'Database not available' });
        return;
      }
      
      const connectTimestamp = new Date().toISOString();
      console.log(`👤 Player-connect event received at ${connectTimestamp}`);
      console.log(`👤 Player-connect data:`, data);
      
      const { playerId } = data;
      
      if (!playerId) {
        console.log(`❌ Missing playerId in player-connect event`);
        socket.emit('connection-error', { error: 'Missing player ID' });
        return;
      }
      
      try {
        // First check if player exists in database
        const existingPlayer = await DatabasePlayer.getPlayerById(playerId);
        if (!existingPlayer) {
          console.log(`❌ Player not found in database: ${playerId}`);
          console.log(`🔍 DEBUG: This suggests registration didn't complete properly`);
          socket.emit('connection-error', { error: 'Player not found - please re-register' });
          return;
        }
        
        console.log(`✅ Found player in database: ${existingPlayer.name} (${playerId})`);
        
        // Update socket ID for existing player
        console.log(`🔧 SOCKET UPDATE DEBUG: Updating socket for playerId: ${playerId}, socketId: ${socket.id}`);
        const player = await DatabasePlayer.updateSocketId(playerId, socket.id);
        console.log(`🔧 SOCKET UPDATE DEBUG: Update result - player found: ${!!player}, player name: ${player?.name || 'N/A'}`);
        
        if (player) {
          console.log(`👤 Player connected via socket: ${player.name} (${socket.id})`);
          
          // Send success confirmation to this specific client
          socket.emit('player-connected', {
            success: true,
            player: player.getPublicInfo(),
            timestamp: new Date().toISOString()
          });
          
          const onlinePlayers = (await DatabasePlayer.getOnlinePlayers()).map(p => p.getPublicInfo());
          const updateData = {
            players: onlinePlayers,
            timestamp: new Date().toISOString()
          };
          
          console.log(`🔄 SERVER: Emitting player-list-updated to ${io.engine.clientsCount} clients`);
          console.log(`🔄 SERVER: Player list data:`, JSON.stringify(updateData, null, 2));
          
          io.emit('player-list-updated', updateData);
        } else {
          console.log(`❌ Failed to update socket ID for player: ${playerId}`);
          socket.emit('connection-error', { error: 'Failed to update connection' });
        }
      } catch (dbError) {
        console.log(`❌ Database error during player-connect: ${dbError.message}`);
        console.log(`🔍 DEBUG: Player ID: ${playerId}, Socket ID: ${socket.id}`);
        socket.emit('connection-error', { error: 'Database error during connection' });
      }
      
    } catch (error) {
      console.error('❌ Error handling player-connect:', error);
      socket.emit('connection-error', { error: 'Server error during connection' });
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
    const cleanedStaleCount = await DatabasePlayer.cleanupStaleConnections();
    // Note: Phrase cleanup not yet implemented for database - will be added in Phase 4
    
    if (cleanedPlayersCount > 0 || cleanedStaleCount > 0) {
      console.log(`🧹 Cleaned up ${cleanedPlayersCount} inactive players and ${cleanedStaleCount} stale connections`);
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
      console.log(`📁 Routes loaded: system, players, phrases, contributions, leaderboards, debug`);
    });
  } catch (error) {
    console.error('❌ Server startup failed:', error);
    process.exit(1);
  }
}

// Start the server
startServer();

module.exports = { app, server, io };