// Load environment variables
require('dotenv').config();

const express = require('express');
const cors = require('cors');
const { createServer } = require('http');
const { Server } = require('socket.io');

// Database modules
const { testConnection, getStats: getDbStats, shutdown: shutdownDb, pool, query } = require('./database/connection');
const DatabasePlayer = require('./models/DatabasePlayer');
const DatabasePhrase = require('./models/DatabasePhrase');
const { HintSystem, HintValidationError } = require('./services/hintSystem');
const ScoringSystem = require('./services/scoringSystem');
const ConfigService = require('./services/config-service');
// Language detection removed - use explicit language parameter

// Swagger documentation setup
const swaggerUi = require('swagger-ui-express');
const swaggerFile = require('./swagger-output.json');

// Web dashboard modules (temporarily disabled for Docker)
const path = require('path');
// const ContributionLinkGenerator = require('./web-dashboard/server/link-generator');

const app = express();
const server = createServer(app);

// Initialize configuration service
const configService = new ConfigService(pool);
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

// Create monitoring namespace for dashboard
const monitoringNamespace = io.of('/monitoring');

monitoringNamespace.on('connection', (socket) => {
  console.log(`📊 MONITORING: Dashboard connected: ${socket.id}`);
  
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
      pool.query('SELECT COUNT(*) as count FROM players WHERE is_active = true AND last_seen > NOW() - INTERVAL \'5 minutes\''),
      pool.query('SELECT COUNT(*) as count FROM phrases WHERE created_at > NOW() - INTERVAL \'24 hours\''),
      pool.query('SELECT COUNT(*) as count FROM phrases WHERE created_at > CURRENT_DATE')
    ]);

    const completedResult = await pool.query(`
      SELECT 
        COUNT(*) as completed,
        COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM phrases WHERE created_at > NOW() - INTERVAL '24 hours'), 0) as completion_rate
      FROM completed_phrases cp
      JOIN phrases p ON cp.phrase_id = p.id
      WHERE cp.completed_at > NOW() - INTERVAL '24 hours'
    `);

    // Get phrase inventory by difficulty
    const inventoryResult = await getPhraseInventoryByDifficulty();
    
    // Get players nearing phrase depletion
    const playersNearingDepletion = await getPlayersNearingPhraseDepletion();

    return {
      onlinePlayers: parseInt(playersResult.rows[0].count),
      activePhrases: parseInt(phrasesResult.rows[0].count),
      phrasesToday: parseInt(todayPhrasesResult.rows[0].count),
      completionRate: Math.round(parseFloat(completedResult.rows[0].completion_rate || 0)),
      phraseInventory: inventoryResult,
      playersNearingDepletion: playersNearingDepletion
    };
  } catch (error) {
    console.error('Error calculating monitoring stats:', error);
    return {
      onlinePlayers: 0,
      activePhrases: 0,
      phrasesToday: 0,
      completionRate: 0,
      phraseInventory: {
        veryEasy: 0,
        easy: 0,
        medium: 0,
        hard: 0,
        veryHard: 0
      },
      playersNearingDepletion: []
    };
  }
}

// Helper function to get phrase inventory by difficulty ranges
async function getPhraseInventoryByDifficulty() {
  try {
    const inventoryQuery = `
      SELECT 
        CASE 
          WHEN difficulty_level <= 20 THEN 'veryEasy'
          WHEN difficulty_level <= 40 THEN 'easy'
          WHEN difficulty_level <= 60 THEN 'medium'
          WHEN difficulty_level <= 80 THEN 'hard'
          ELSE 'veryHard'
        END as difficulty_range,
        COUNT(*) as phrase_count
      FROM phrases 
      WHERE is_global = true 
        AND is_approved = true
        AND NOT EXISTS (
          SELECT 1 FROM completed_phrases cp 
          WHERE cp.phrase_id = phrases.id
        )
      GROUP BY difficulty_range
      ORDER BY 
        CASE difficulty_range
          WHEN 'veryEasy' THEN 1
          WHEN 'easy' THEN 2
          WHEN 'medium' THEN 3
          WHEN 'hard' THEN 4
          WHEN 'veryHard' THEN 5
        END
    `;

    const result = await pool.query(inventoryQuery);
    
    // Initialize with zeros
    const inventory = {
      veryEasy: 0,
      easy: 0,
      medium: 0,
      hard: 0,
      veryHard: 0
    };

    // Fill in actual counts
    result.rows.forEach(row => {
      inventory[row.difficulty_range] = parseInt(row.phrase_count);
    });

    console.log('📊 INVENTORY: Phrase counts by difficulty:', inventory);
    return inventory;

  } catch (error) {
    console.error('❌ INVENTORY: Error getting phrase inventory:', error);
    return {
      veryEasy: 0,
      easy: 0,
      medium: 0,
      hard: 0,
      veryHard: 0
    };
  }
}

// Helper function to get players nearing phrase depletion
async function getPlayersNearingPhraseDepletion() {
  try {
    const depletionQuery = `
      WITH player_stats as (
        SELECT 
          p.id,
          p.name,
          p.is_active,
          p.last_seen,
          COUNT(cp.phrase_id) as phrases_completed,
          -- Calculate available phrases for player's level range
          (
            SELECT COUNT(*) 
            FROM phrases ph
            WHERE ph.is_global = true 
              AND ph.is_approved = true
              AND ph.difficulty_level <= COALESCE(p.level, 1) * 50  -- Assuming level * 50 = max difficulty
              AND NOT EXISTS (
                SELECT 1 FROM completed_phrases cp2 
                WHERE cp2.phrase_id = ph.id AND cp2.player_id = p.id
              )
          ) as available_phrases,
          -- Player's current level (default to 1 if null)
          COALESCE(p.level, 1) as player_level
        FROM players p
        LEFT JOIN completed_phrases cp ON p.id = cp.player_id
        WHERE p.is_active = true 
          AND p.last_seen > NOW() - INTERVAL '7 days'  -- Active in last 7 days
        GROUP BY p.id, p.name, p.is_active, p.last_seen, p.level
      )
      SELECT 
        id,
        name,
        phrases_completed,
        available_phrases,
        player_level,
        last_seen,
        CASE 
          WHEN available_phrases = 0 THEN 'critical'
          WHEN available_phrases < 5 THEN 'low'
          WHEN available_phrases < 15 THEN 'medium'
          ELSE 'good'
        END as depletion_status
      FROM player_stats
      WHERE available_phrases < 20  -- Only show players with less than 20 available phrases
      ORDER BY available_phrases ASC, phrases_completed DESC
      LIMIT 20
    `;

    const result = await pool.query(depletionQuery);
    
    const playersNearingDepletion = result.rows.map(row => ({
      id: row.id,
      name: row.name,
      phrasesCompleted: parseInt(row.phrases_completed),
      availablePhrases: parseInt(row.available_phrases),
      playerLevel: parseInt(row.player_level),
      lastSeen: row.last_seen,
      depletionStatus: row.depletion_status
    }));

    console.log(`📊 DEPLETION: Found ${playersNearingDepletion.length} players nearing phrase depletion`);
    return playersNearingDepletion;

  } catch (error) {
    console.error('❌ DEPLETION: Error getting players nearing depletion:', error);
    return [];
  }
}

// Helper function to get recent phrases for monitoring
async function getRecentPhrases() {
  try {
    const result = await pool.query(`
      SELECT 
        p.id,
        p.content as text,
        p.difficulty_level as difficulty,
        p.language,
        p.created_at,
        p.hint,
        p.created_by_player_id,
        pl.name as author_name,
        CASE 
          WHEN EXISTS (SELECT 1 FROM completed_phrases cp WHERE cp.phrase_id = p.id) THEN 'completed'
          ELSE 'active'
        END as status
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
  console.log(`📊 DIRECT EMIT: Sent to ${socketCount} individual sockets`);
}

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

// Swagger UI setup
app.use('/api/docs', swaggerUi.serve, swaggerUi.setup(swaggerFile, {
  customCss: '.swagger-ui .topbar { display: none }',
  customSiteTitle: 'Anagram Game API Documentation'
}));

// Web Dashboard Static Files
app.use('/web', express.static(path.join(__dirname, '../web-dashboard/public')));

// Web Dashboard Routes
// const linkGenerator = new ContributionLinkGenerator();

// Serve monitoring dashboard
app.get('/monitoring', (req, res) => {
  res.sendFile(path.join(__dirname, '../web-dashboard/public/monitoring/index.html'));
});

// Serve contribution form
app.get('/contribute/:token', (req, res) => {
  res.sendFile(path.join(__dirname, '../web-dashboard/public/contribute/index.html'));
});

// Generate contribution link
app.post('/api/contribution/request', async (req, res) => {
  try {
    const { playerId, expirationHours = 48, maxUses = 3, customMessage } = req.body;
    
    if (!playerId) {
      return res.status(400).json({ error: 'Player ID is required' });
    }

    if (!isDatabaseConnected) {
      return res.status(503).json({ error: 'Database connection required' });
    }

    const player = await DatabasePlayer.getPlayerById(playerId);
    if (!player) {
      return res.status(404).json({ error: 'Player not found' });
    }

    const link = await linkGenerator.createContributionLink(playerId, {
      expirationHours,
      maxUses,
      customMessage
    });

    res.status(201).json({
      success: true,
      link: link
    });
  } catch (error) {
    console.error('Error creating contribution link:', error);
    res.status(500).json({ error: 'Failed to create contribution link' });
  }
});

// Get contribution link details
app.get('/api/contribution/:token', async (req, res) => {
  try {
    const { token } = req.params;
    
    if (!isDatabaseConnected) {
      return res.status(503).json({ error: 'Database connection required' });
    }
    
    const validation = await linkGenerator.validateToken(token);
    
    if (!validation.valid) {
      return res.status(400).json({ error: validation.reason });
    }

    res.json({
      success: true,
      link: validation.link
    });
  } catch (error) {
    console.error('Error validating contribution token:', error);
    res.status(500).json({ error: 'Failed to validate contribution link' });
  }
});

// Submit phrase via contribution link
app.post('/api/contribution/:token/submit', async (req, res) => {
  try {
    const { token } = req.params;
    const { phrase, clue, language = 'en', contributorName } = req.body;
    
    if (!isDatabaseConnected) {
      return res.status(503).json({ error: 'Database connection required' });
    }
    
    // Validate token
    const validation = await linkGenerator.validateToken(token);
    if (!validation.valid) {
      return res.status(400).json({ error: validation.reason });
    }

    // Validate phrase using same logic as app
    if (!phrase || typeof phrase !== 'string') {
      return res.status(400).json({ error: 'Phrase is required' });
    }

    const trimmedPhrase = phrase.trim();
    if (trimmedPhrase.length < 3) {
      return res.status(400).json({ error: 'Phrase must be at least 3 characters long' });
    }

    if (trimmedPhrase.length > 200) {
      return res.status(400).json({ error: 'Phrase must be less than 200 characters' });
    }

    // Count words (same logic as PhraseCreationView.swift)
    const wordCount = trimmedPhrase.split(/\s+/).filter(word => word.length > 0).length;
    if (wordCount < 2) {
      return res.status(400).json({ error: 'Phrase must contain at least 2 words' });
    }

    if (wordCount > 6) {
      return res.status(400).json({ error: 'Phrase must contain no more than 6 words' });
    }

    // Validate clue
    const finalClue = clue && clue.trim() ? clue.trim() : 'No clue provided';
    if (finalClue.length > 500) {
      return res.status(400).json({ error: 'Clue must be less than 500 characters' });
    }

    // Validate language
    if (!['en', 'sv'].includes(language)) {
      return res.status(400).json({ error: 'Invalid language' });
    }

    // Create phrase using existing DatabasePhrase.createPhrase logic with contribution link
    const createdPhrase = await DatabasePhrase.createPhrase({
      content: trimmedPhrase,
      hint: finalClue,
      language: language,
      senderId: null, // External contribution
      targetId: validation.link.requestingPlayerId,
      contributionLinkId: validation.link.id, // Link to contribution for contributor name
      source: 'external', // Mark as external contribution
      contributorName: contributorName || null // Store contributor name directly
    });
    
    if (!createdPhrase) {
      return res.status(500).json({ error: 'Failed to create phrase' });
    }

    // Record the contribution
    const contributorInfo = {
      name: contributorName || null,
      ip: req.ip || req.connection.remoteAddress
    };

    const recordResult = await linkGenerator.recordContribution(token, contributorInfo);

    // Send instant real-time notification to target player for immediate delivery
    const target = await DatabasePlayer.getPlayerById(validation.link.requestingPlayerId);
    if (target && target.socketId) {
      const phraseData = createdPhrase.getPublicInfo();
      // Ensure targetId and senderName are included for iOS client compatibility
      phraseData.targetId = validation.link.requestingPlayerId;
      phraseData.senderName = contributorName || 'Anonymous Contributor';
      
      io.to(target.socketId).emit('new-phrase', {
        phrase: phraseData,
        senderName: contributorName || 'Anonymous Contributor',
        timestamp: new Date().toISOString()
      });
      console.log(`📨 Sent instant new-phrase notification to ${target.name} (${target.socketId}) for contribution "${trimmedPhrase}"`);
    } else {
      console.log(`📨 Target player not connected - contribution phrase queued for later delivery`);
    }

    res.status(201).json({
      success: true,
      phrase: {
        id: createdPhrase.id,
        content: createdPhrase.content,
        hint: createdPhrase.hint,
        language: createdPhrase.language
      },
      remainingUses: recordResult.remainingUses,
      message: 'Phrase submitted successfully!'
    });

  } catch (error) {
    console.error('Error submitting contribution:', error);
    res.status(500).json({ error: 'Failed to submit phrase' });
  }
});

// Debug logging endpoint
app.post('/api/debug/log', (req, res) => {
  // Check if performance monitoring is enabled
  if (process.env.ENABLE_PERFORMANCE_MONITORING !== 'true') {
    return res.json({ status: 'monitoring_disabled' });
  }
  
  const { message, timestamp, playerId } = req.body;
  console.log(`🔍 DEBUG [${timestamp}] Player ${playerId}: ${message}`);
  res.json({ status: 'logged' });
});

app.post('/api/debug/performance', (req, res) => {
  // Check if performance monitoring is enabled
  if (process.env.ENABLE_PERFORMANCE_MONITORING !== 'true') {
    return res.json({ status: 'monitoring_disabled' });
  }
  
  const { event, fps, memory_mb, tiles_count, quake_state, timestamp, playerId, component, deviceModel } = req.body;
  console.log(`📊 PERFORMANCE [${timestamp}] Player ${playerId} (${deviceModel || 'Unknown'}): FPS=${fps}, Memory=${memory_mb}MB, Tiles=${tiles_count}, Quake=${quake_state} [${component}]`);
  res.json({ status: 'logged' });
});

// Configuration endpoint - returns client configuration
app.get('/api/config', async (req, res) => {
  try {
    const performanceMonitoringEnabled = await configService.getConfig('performance_monitoring_enabled', true);
    
    const config = {
      performanceMonitoringEnabled,
      serverVersion: '1.0.0',
      timestamp: new Date().toISOString()
    };
    
    console.log(`⚙️ CONFIG: Sent configuration to client - Performance monitoring: ${config.performanceMonitoringEnabled}`);
    res.json(config);
  } catch (error) {
    console.error('🚨 CONFIG ERROR: Failed to get configuration:', error);
    // Fallback to default configuration
    res.json({
      performanceMonitoringEnabled: true,
      serverVersion: '1.0.0',
      timestamp: new Date().toISOString()
    });
  }
});

// Admin endpoint to get all configuration (read-only)
app.get('/api/admin/config', async (req, res) => {
  try {
    const config = await configService.getAllConfig();
    res.json(config);
  } catch (error) {
    console.error('🚨 ADMIN CONFIG ERROR:', error);
    res.status(500).json({ 
      error: 'Internal server error' 
    });
  }
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

// Level configuration endpoint
app.get('/api/config/levels', async (req, res) => {
  try {
    const fs = require('fs').promises;
    const path = require('path');
    
    const configPath = path.join(__dirname, 'config', 'level-config.json');
    const configData = await fs.readFile(configPath, 'utf8');
    const config = JSON.parse(configData);
    
    res.json(config);
  } catch (error) {
    console.error('❌ LEVEL CONFIG: Error loading level configuration:', error.message);
    
    // Return default configuration if file doesn't exist or can't be read
    const defaultConfig = {
      version: "2.0.0",
      progressionMultiplier: 1.3,
      baseDifficultyPerLevel: 50,
      skillLevels: [
        { id: 0, title: "non-existent", pointsRequired: 0, maxDifficulty: 0 },
        { id: 1, title: "disastrous", pointsRequired: 100, maxDifficulty: 50 }
      ],
      milestones: [
        { level: 1, bonus: 0, description: "First skill level reached!" }
      ]
    };
    
    res.json(defaultConfig);
  }
});

/**
 * @swagger
 * /api/players/register:
 *   post:
 *     summary: Register a new player
 *     description: Creates a new player in the database with a unique UUID and establishes their presence
 *     tags: [Player Management]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - name
 *               - socketId
 *             properties:
 *               name:
 *                 type: string
 *                 description: Player display name
 *                 example: "John Doe"
 *               socketId:
 *                 type: string
 *                 description: Socket.IO connection ID for real-time communication
 *                 example: "xyz123abc"
 *     responses:
 *       201:
 *         description: Player registered successfully
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 playerId:
 *                   type: string
 *                   format: uuid
 *                   description: Unique player identifier
 *                 name:
 *                   type: string
 *                   description: Player display name
 *                 message:
 *                   type: string
 *                   example: "Player registered successfully"
 *       400:
 *         description: Invalid input data
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *             examples:
 *               invalidName:
 *                 value:
 *                   error: "Player name is required and must be a string"
 *               invalidSocketId:
 *                 value:
 *                   error: "Socket ID is required and must be a string"
 *       503:
 *         description: Database unavailable
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *       500:
 *         description: Database error during registration
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 */
app.post('/api/players/register', async (req, res) => {
  try {
    if (!isDatabaseConnected) {
      return res.status(503).json({
        error: 'Database connection required for player registration'
      });
    }
    
    const { name, deviceId, socketId } = req.body;
    
    // Development debug logging for device-user association
    if (process.env.NODE_ENV === 'development') {
      console.log(`🔍 REGISTRATION: name='${name}', deviceId='${deviceId}', socketId='${socketId}'`);
    }
    
    // Validate input
    if (!name || typeof name !== 'string') {
      return res.status(400).json({ 
        error: 'Player name is required and must be a string' 
      });
    }

    if (!deviceId || typeof deviceId !== 'string') {
      return res.status(400).json({ 
        error: 'Device ID is required and must be a string' 
      });
    }

    // Validate socketId if provided
    if (socketId !== null && socketId !== undefined && typeof socketId !== 'string') {
      return res.status(400).json({
        error: 'Socket ID must be a string or null'
      });
    }
    
    // Check if this exact player (name + device_id) already exists
    const existingPlayer = await DatabasePlayer.getPlayerByNameAndDevice(name, deviceId);
    let player;
    let isFirstLogin = false;
    
    if (existingPlayer) {
      // Existing player logging back in with same device
      player = await DatabasePlayer.updatePlayerLogin(existingPlayer.id, socketId || null);
      isFirstLogin = false;
      console.log(`👤 Existing player logged back in: ${player.name} (${player.id})`);
    } else {
      // Check if name is taken by another device
      const nameConflict = await DatabasePlayer.getPlayerByName(name);
      if (nameConflict && nameConflict.deviceId) {
        // Name exists and is tied to a different device - suggest alternatives
        const suggestions = await DatabasePlayer.generateNameSuggestions(name);
        return res.status(409).json({
          error: 'Player name is already taken by another device',
          suggestions: suggestions,
          code: 'NAME_TAKEN_OTHER_DEVICE'
        });
      } else if (nameConflict && nameConflict.deviceId === null) {
        // Name exists but no device associated - claim this player (only if device_id is explicitly NULL)
        const updatedResult = await query(`
          UPDATE players 
          SET device_id = $1, socket_id = $2, is_active = true, last_seen = CURRENT_TIMESTAMP
          WHERE id = $3 AND device_id IS NULL
          RETURNING *
        `, [deviceId, socketId || null, nameConflict.id]);
        
        if (updatedResult.rows.length > 0) {
          player = new DatabasePlayer(updatedResult.rows[0]);
          isFirstLogin = false; // This is an existing player being claimed
          console.log(`👤 Player claimed by device: ${player.name} (${player.id})`);
        } else {
          // Race condition - someone else claimed this player, suggest alternatives
          const suggestions = await DatabasePlayer.generateNameSuggestions(name);
          return res.status(409).json({
            error: 'Player name is already taken by another device',
            suggestions: suggestions,
            code: 'NAME_TAKEN_OTHER_DEVICE'
          });
        }
      } else {
        // New player registration
        player = await DatabasePlayer.createPlayerWithDevice(name, deviceId, socketId || null);
        isFirstLogin = true; // This is a brand new player
        console.log(`👤 New player registered: ${player.name} (${player.id})`);
      }
    }
    console.log(`👤 Player registered: ${player.name} (${player.id})`);
    
    // Broadcast activity to monitoring dashboard
    broadcastActivity('player', `New player registered: ${player.name}`, {
      playerId: player.id,
      name: player.name
    });
    
    // Broadcast new player joined event
    io.emit('player-joined', {
      player: player.getPublicInfo(),
      timestamp: new Date().toISOString()
    });
    
    res.status(201).json({
      success: true,
      player: player.getPublicInfo(),
      isFirstLogin: isFirstLogin,
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
    
    // Handle database conflicts with name suggestions
    if (error.message.includes('already taken') || 
        error.message.includes('duplicate') ||
        error.message.includes('unique constraint') ||
        error.message.includes('Player name and device combination already exists') ||
        error.code === '23505') {
      
      try {
        const suggestions = await DatabasePlayer.generateNameSuggestions(name || 'Player');
        return res.status(409).json({
          error: 'Player name is already taken by another device',
          suggestions: suggestions,
          code: 'NAME_TAKEN_OTHER_DEVICE'
        });
      } catch (suggestionError) {
        console.error('❌ Error generating name suggestions:', suggestionError);
        return res.status(409).json({ 
          error: 'Player name is already taken' 
        });
      }
    }
    
    res.status(500).json({ 
      error: error.message || 'Registration failed' 
    });
  }
});

/**
 * @swagger
 * /api/players/online:
 *   get:
 *     summary: Get list of online players
 *     description: Returns all currently active players with their public information
 *     tags: [Player Management]
 *     responses:
 *       200:
 *         description: List of online players retrieved successfully
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 players:
 *                   type: array
 *                   items:
 *                     $ref: '#/components/schemas/Player'
 *                 count:
 *                   type: integer
 *                   description: Number of online players
 *                   example: 5
 *                 timestamp:
 *                   type: string
 *                   format: date-time
 *                   description: Response timestamp
 *             example:
 *               players:
 *                 - id: "123e4567-e89b-12d3-a456-426614174000"
 *                   name: "John Doe"
 *                   lastSeen: "2023-12-07T10:30:00.000Z"
 *                   isActive: true
 *                   phrasesCompleted: 15
 *               count: 1
 *               timestamp: "2023-12-07T10:30:00.000Z"
 *       503:
 *         description: Database unavailable
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *       500:
 *         description: Internal server error
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 */
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


// Get monitoring stats for dashboard
app.get('/api/stats', async (req, res) => {
  try {
    if (!isDatabaseConnected) {
      return res.status(503).json({
        error: 'Database connection required for stats'
      });
    }
    
    const stats = await getMonitoringStats();
    res.json(stats);
  } catch (error) {
    console.error('❌ Error getting monitoring stats:', error);
    res.status(500).json({ 
      error: 'Failed to get monitoring stats' 
    });
  }
});

// Get legend players endpoint
app.get('/api/players/legends', async (req, res) => {
  try {
    if (!isDatabaseConnected) {
      return res.status(503).json({
        error: 'Database connection required for legend players'
      });
    }

    // Read the minimum skill level from config
    const fs = require('fs').promises;
    const path = require('path');
    const configPath = path.join(__dirname, 'config', 'level-config.json');
    
    let minimumSkillLevel = 2; // Default to wretched (level 2)
    let minimumSkillTitle = 'wretched';
    let minimumPoints = 230;
    
    try {
      const configData = await fs.readFile(configPath, 'utf8');
      const levelConfig = JSON.parse(configData);
      
      // Find the wretched skill level
      const wretchedLevel = levelConfig.skillLevels?.find(level => level.title === 'wretched');
      if (wretchedLevel) {
        minimumSkillLevel = wretchedLevel.id;
        minimumSkillTitle = wretchedLevel.title;
        minimumPoints = wretchedLevel.pointsRequired;
      }
    } catch (configError) {
      console.error('❌ LEGENDS: Error loading level config, using defaults:', configError.message);
    }

    console.log(`👑 LEGENDS: Looking for players with ${minimumPoints}+ points (${minimumSkillTitle} level)`);

    // Query for players with total scores >= minimum points required for wretched level  
    // Use same scoring logic as leaderboard system, get max score per player
    const query = `
      SELECT 
        p.id,
        p.name,
        MAX(ps.total_score) as total_score,
        MAX(ps.phrases_completed) as phrases_completed
      FROM players p
      JOIN player_scores ps ON p.id = ps.player_id
      WHERE ps.total_score >= $1
      GROUP BY p.id, p.name
      ORDER BY MAX(ps.total_score) DESC
      LIMIT 50
    `;

    const result = await pool.query(query, [minimumPoints]);
    
    const legendPlayers = result.rows.map(row => {
      const totalScore = parseInt(row.total_score);
      
      // Calculate skill level based on total score
      let skillLevel = minimumSkillLevel;
      let skillTitle = minimumSkillTitle;
      
      try {
        // Re-read config to calculate exact skill level
        const fs = require('fs');
        const configData = fs.readFileSync(configPath, 'utf8');
        const levelConfig = JSON.parse(configData);
        
        // Find the highest skill level this player has achieved
        for (let i = levelConfig.skillLevels.length - 1; i >= 0; i--) {
          const level = levelConfig.skillLevels[i];
          if (totalScore >= level.pointsRequired) {
            skillLevel = level.id;
            skillTitle = level.title;
            break;
          }
        }
      } catch (error) {
        console.error('❌ LEGENDS: Error calculating skill level:', error.message);
      }
      
      return {
        id: row.id,
        name: row.name,
        totalScore: totalScore,
        skillLevel: skillLevel,
        skillTitle: skillTitle,
        phrasesCompleted: parseInt(row.phrases_completed)
      };
    });

    console.log(`👑 LEGENDS: Found ${legendPlayers.length} legend players`);

    res.json({
      success: true,
      players: legendPlayers,
      minimumSkillLevel: minimumSkillLevel,
      minimumSkillTitle: minimumSkillTitle,
      count: legendPlayers.length,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ LEGENDS: Error getting legend players:', error);
    res.status(500).json({
      error: 'Failed to get legend players'
    });
  }
});

/**
 * @swagger
 * /api/phrases:
 *   post:
 *     summary: Create a basic phrase (legacy endpoint)
 *     description: Creates a new targeted phrase between two players with automatic hint generation
 *     tags: [Phrase Management]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - content
 *               - senderId
 *               - targetId
 *             properties:
 *               content:
 *                 type: string
 *                 description: The phrase content to be scrambled
 *                 example: "Hello world"
 *               senderId:
 *                 type: string
 *                 format: uuid
 *                 description: UUID of the player creating the phrase
 *               targetId:
 *                 type: string
 *                 format: uuid
 *                 description: UUID of the target player
 *               hint:
 *                 type: string
 *                 description: Optional hint for the phrase (auto-generated if not provided)
 *                 example: "A greeting to the world"
 *     responses:
 *       201:
 *         description: Phrase created successfully
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 message:
 *                   type: string
 *                   example: "Phrase created successfully"
 *                 phrase:
 *                   $ref: '#/components/schemas/Phrase'
 *       400:
 *         description: Invalid input data
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *             examples:
 *               missingFields:
 *                 value:
 *                   error: "Content, senderId, and targetId are required"
 *               selfTarget:
 *                 value:
 *                   error: "Cannot send phrase to yourself"
 *               invalidUuid:
 *                 value:
 *                   error: "Invalid player ID format"
 *       404:
 *         description: Player not found
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *       500:
 *         description: Database error during phrase creation
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 */
app.post('/api/phrases', async (req, res) => {
  try {
    const { content, senderId, targetId, language } = req.body;
    
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
    
    // Use provided language (no auto-detection)
    
    // Create phrase in database
    const phrase = await DatabasePhrase.createPhrase({
      content,
      senderId,
      targetId,
      hint: req.body.hint || null, // Optional hint support
      language: language
    });
    
    console.log(`📝 Phrase created: "${content}" from ${sender.name} to ${target.name}`);
    
    // Broadcast activity to monitoring dashboard
    broadcastActivity('phrase', `New phrase created: "${content.substring(0, 50)}${content.length > 50 ? '...' : ''}"`, {
      phraseId: phrase.id,
      content: content,
      senderName: sender.name,
      targetName: target.name,
      difficulty: phrase.difficulty,
      language: phrase.language
    });
    
    // Send real-time notification to target player
    if (target.socketId) {
      const phraseData = phrase.getPublicInfo();
      // Ensure targetId and senderName are included for iOS client compatibility
      phraseData.targetId = targetId;
      phraseData.senderName = sender.name;
      
      io.to(target.socketId).emit('new-phrase', {
        phrase: phraseData,
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

/**
 * @swagger
 * /api/phrases/create:
 *   post:
 *     summary: Create enhanced phrase with advanced options (Phase 4.1)
 *     description: Advanced phrase creation with support for global phrases, multiple targets, difficulty levels, and custom priorities
 *     tags: [Phrase Management]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - content
 *               - senderId
 *             properties:
 *               content:
 *                 type: string
 *                 description: The phrase content to be scrambled
 *                 example: "Advanced anagram challenge"
 *               hint:
 *                 type: string
 *                 description: Helpful hint for solving the phrase
 *                 example: "This is about word puzzles"
 *               senderId:
 *                 type: string
 *                 format: uuid
 *                 description: UUID of the player creating the phrase
 *               targetIds:
 *                 type: array
 *                 items:
 *                   type: string
 *                   format: uuid
 *                 description: Array of target player UUIDs (empty for global phrases)
 *                 example: ["123e4567-e89b-12d3-a456-426614174000"]
 *               isGlobal:
 *                 type: boolean
 *                 default: false
 *                 description: Whether phrase should be available globally
 *               difficultyLevel:
 *                 type: integer
 *                 minimum: 1
 *                 maximum: 5
 *                 default: 1
 *                 description: Difficulty level of the phrase
 *               phraseType:
 *                 type: string
 *                 enum: [custom, community, daily]
 *                 default: custom
 *                 description: Type of phrase being created
 *               priority:
 *                 type: integer
 *                 minimum: 1
 *                 maximum: 10
 *                 default: 1
 *                 description: Priority level for phrase delivery
 *     responses:
 *       201:
 *         description: Enhanced phrase created successfully
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success:
 *                   type: boolean
 *                   example: true
 *                 phrases:
 *                   type: array
 *                   items:
 *                     $ref: '#/components/schemas/Phrase'
 *                 message:
 *                   type: string
 *                   example: "Enhanced phrase created successfully"
 *                 created:
 *                   type: integer
 *                   description: Number of phrases created
 *                 targets:
 *                   type: array
 *                   items:
 *                     type: string
 *                   description: Target player names
 *       400:
 *         description: Invalid input data or validation error
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *       404:
 *         description: Sender or target players not found
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *       503:
 *         description: Database unavailable
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *       500:
 *         description: Database error during phrase creation
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 */
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
      targetId, // For backward compatibility with iOS client
      targetIds = [], // For new multi-target functionality
      isGlobal = false,
      difficultyLevel = 1,
      phraseType = 'custom',
      language // Optional - will be auto-detected if not provided
    } = req.body;

    // Handle both targetId (singular) and targetIds (plural) for compatibility
    let finalTargetIds = targetIds;
    if (targetId && targetIds.length === 0) {
      finalTargetIds = [targetId];
    }

    // TEMPORARY DEBUG: Log language parameter and all request data
    console.log(`🔍 DEBUG /api/phrases/create - Language received: "${language}" (type: ${typeof language})`);
    console.log(`🔍 DEBUG /api/phrases/create - Full request body:`, JSON.stringify(req.body, null, 2));
    console.log(`🔍 DEBUG /api/phrases/create - Destructured values:`);
    console.log(`  - content: "${content}"`);
    console.log(`  - hint: "${hint}"`);
    console.log(`  - senderId: "${senderId}" (type: ${typeof senderId})`);
    console.log(`  - targetId: "${targetId}" (type: ${typeof targetId})`);
    console.log(`  - targetIds: ${JSON.stringify(targetIds)} (type: ${typeof targetIds})`);
    console.log(`  - finalTargetIds: ${JSON.stringify(finalTargetIds)} (type: ${typeof finalTargetIds})`);
    console.log(`  - isGlobal: ${isGlobal} (type: ${typeof isGlobal})`);

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
    if (finalTargetIds.length > 0) {
      for (const targetPlayerId of finalTargetIds) {
        const target = await DatabasePlayer.getPlayerById(targetPlayerId);
        if (!target) {
          return res.status(404).json({
            error: `Target player ${targetPlayerId} not found`
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

    // Use provided language (no auto-detection)
    console.log(`🔍 DEBUG - Using provided language: "${language}", content="${content}"`);

    // Create enhanced phrase
    const result = await DatabasePhrase.createEnhancedPhrase({
      content,
      hint,
      senderId,
      targetIds: finalTargetIds,
      isGlobal,
      phraseType,
      language: language
    });

    const { phrase, targetCount, isGlobal: phraseIsGlobal } = result;

    console.log(`📝 Enhanced phrase created: "${content}" from ${sender.name}${phraseIsGlobal ? ' (global)' : ` to ${targetCount} players`}`);

    // Send real-time notifications to target players
    const notifications = [];
    for (const target of validTargets) {
      if (target.socketId) {
        const phraseData = phrase.getPublicInfo();
        // Ensure targetId and senderName are included for iOS client compatibility
        phraseData.targetId = target.id;
        phraseData.senderName = sender.name;
        
        io.to(target.socketId).emit('new-phrase', {
          phrase: phraseData,
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

/**
 * @swagger
 * /api/phrases/global:
 *   get:
 *     summary: Get global phrase bank (Phase 4.2)
 *     description: Retrieve paginated list of approved global phrases with optional difficulty filtering
 *     tags: [Phrase Management]
 *     parameters:
 *       - in: query
 *         name: limit
 *         schema:
 *           type: integer
 *           minimum: 1
 *           maximum: 100
 *           default: 50
 *         description: Number of phrases to return (max 100)
 *       - in: query
 *         name: offset
 *         schema:
 *           type: integer
 *           minimum: 0
 *           default: 0
 *         description: Number of phrases to skip for pagination
 *       - in: query
 *         name: difficulty
 *         schema:
 *           type: integer
 *           minimum: 1
 *           maximum: 5
 *         description: Filter by difficulty level (1-5)
 *       - in: query
 *         name: approved
 *         schema:
 *           type: boolean
 *           default: true
 *         description: Whether to include only approved phrases
 *     responses:
 *       200:
 *         description: Global phrases retrieved successfully
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 phrases:
 *                   type: array
 *                   items:
 *                     $ref: '#/components/schemas/Phrase'
 *                 count:
 *                   type: integer
 *                   description: Number of phrases returned
 *                   example: 25
 *                 totalCount:
 *                   type: integer
 *                   description: Total number of available phrases
 *                   example: 150
 *                 pagination:
 *                   type: object
 *                   properties:
 *                     limit:
 *                       type: integer
 *                       example: 50
 *                     offset:
 *                       type: integer
 *                       example: 0
 *                     hasMore:
 *                       type: boolean
 *                       example: true
 *                 filters:
 *                   type: object
 *                   properties:
 *                     difficulty:
 *                       type: integer
 *                       nullable: true
 *                       example: 3
 *                     approved:
 *                       type: boolean
 *                       example: true
 *                 timestamp:
 *                   type: string
 *                   format: date-time
 *       400:
 *         description: Invalid query parameters
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *       503:
 *         description: Database unavailable
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *       500:
 *         description: Database error during retrieval
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 */
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
    
    // Legacy difficulty filter (1-5 range)
    const rawDifficulty = parseInt(req.query.difficulty);
    const difficulty = (rawDifficulty >= 1 && rawDifficulty <= 5) ? rawDifficulty : null;
    
    // New difficulty range filters (1+ range, no upper limit)
    const rawMinDifficulty = parseInt(req.query.minDifficulty);
    const minDifficulty = (rawMinDifficulty >= 1) ? rawMinDifficulty : null;
    const rawMaxDifficulty = parseInt(req.query.maxDifficulty);
    const maxDifficulty = (rawMaxDifficulty >= 1) ? rawMaxDifficulty : null;
    
    const approved = req.query.approved !== 'false'; // Default to approved only

    // Check for invalid difficulty values - if provided but invalid, return empty results
    const hasInvalidMinDifficulty = req.query.minDifficulty && (isNaN(rawMinDifficulty) || rawMinDifficulty < 1);
    const hasInvalidMaxDifficulty = req.query.maxDifficulty && (isNaN(rawMaxDifficulty) || rawMaxDifficulty < 1);
    
    console.log(`🌍 REQUEST: Global phrases - limit: ${limit}, offset: ${offset}, difficulty: ${difficulty || 'all'}, minDifficulty: ${minDifficulty || 'none'}, maxDifficulty: ${maxDifficulty || 'none'}, approved: ${approved}`);

    // If invalid difficulty values were provided, return empty results
    if (hasInvalidMinDifficulty || hasInvalidMaxDifficulty) {
      console.log(`⚠️ DATABASE: Invalid difficulty parameters provided, returning empty results`);
      res.json({
        success: true,
        phrases: [],
        pagination: {
          limit,
          offset,
          total: 0,
          count: 0,
          hasMore: false
        },
        filters: {
          difficulty: difficulty || 'all',
          minDifficulty: minDifficulty || 'none',
          maxDifficulty: maxDifficulty || 'none',
          approved
        },
        timestamp: new Date().toISOString()
      });
      return;
    }

    // Get global phrases with optional filtering
    const phrases = await DatabasePhrase.getGlobalPhrases(limit, offset, difficulty, approved, minDifficulty, maxDifficulty);
    
    // Get total count for pagination
    const totalCount = await DatabasePhrase.getGlobalPhrasesCount(difficulty, approved, minDifficulty, maxDifficulty);

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
        minDifficulty: minDifficulty || 'none',
        maxDifficulty: maxDifficulty || 'none',
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

// Phrase Approval endpoint (Phase 4.2 completion)
app.post('/api/phrases/:phraseId/approve', async (req, res) => {
  try {
    if (!isDatabaseConnected) {
      return res.status(503).json({
        error: 'Database connection required for phrase approval'
      });
    }

    const { phraseId } = req.params;

    // Basic UUID validation for phraseId
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(phraseId)) {
      return res.status(400).json({
        error: 'Invalid phrase ID format'
      });
    }

    console.log(`✅ REQUEST: Approve phrase ${phraseId}`);

    // Approve the phrase (this method checks if phrase exists and is global)
    const approved = await DatabasePhrase.approvePhrase(phraseId);

    if (approved) {
      res.status(200).json({
        success: true,
        phraseId,
        approved: true,
        message: 'Phrase approved successfully',
        timestamp: new Date().toISOString()
      });

      console.log(`✅ APPROVAL: Phrase ${phraseId} approved for global use`);
    } else {
      res.status(404).json({
        error: 'Phrase not found or not eligible for approval'
      });
    }

  } catch (error) {
    console.error('❌ Error approving phrase:', error);
    
    // Handle UUID validation errors specifically
    if (error.message.includes('invalid input syntax for type uuid')) {
      return res.status(400).json({
        error: 'Invalid phrase ID format'
      });
    }

    res.status(500).json({
      error: 'Failed to approve phrase'
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
    const { level } = req.query; // Get player level from query parameters
    
    // Validate that player exists in database
    const player = await DatabasePlayer.getPlayerById(playerId);
    if (!player) {
      return res.status(404).json({ 
        error: 'Player not found' 
      });
    }
    
    // Determine max difficulty based on player level
    let maxDifficulty = null;
    if (level) {
      try {
        const fs = require('fs').promises;
        const path = require('path');
        const configPath = path.join(__dirname, 'config', 'level-config.json');
        const configData = await fs.readFile(configPath, 'utf8');
        const levelConfig = JSON.parse(configData);
        
        const playerLevel = parseInt(level);
        if (playerLevel > 0) {
          // Find the skill level that matches the player's level
          const skillLevel = levelConfig.skillLevels?.find(sl => sl.id === playerLevel);
          if (skillLevel) {
            maxDifficulty = skillLevel.maxDifficulty;
            console.log(`🎯 LEVEL FILTER: Player skill level ${playerLevel} (${skillLevel.title}), max difficulty: ${maxDifficulty}`);
          } else {
            // Fallback to legacy calculation if skill level not found
            maxDifficulty = playerLevel * (levelConfig.baseDifficultyPerLevel || 50);
            console.log(`🎯 LEVEL FILTER: Legacy calculation for level ${playerLevel}, max difficulty: ${maxDifficulty}`);
          }
        }
      } catch (configError) {
        console.error('❌ LEVEL CONFIG: Error loading level config, using no filtering:', configError.message);
      }
    }
    
    // Get phrases for player from database (with optional difficulty filtering)
    const phrases = await DatabasePhrase.getPhrasesForPlayer(playerId, maxDifficulty);
    
    const phrasesData = phrases.map(p => p.getPublicInfo());
    
    // CRITICAL DEBUG: Log the exact JSON being sent to iOS client
    if (phrasesData.length > 0 && phrasesData[0].targetId) {
      console.log('🔍 SERVER: Sending targeted phrase to iOS client:');
      console.log('🔍 SERVER: First phrase data:', JSON.stringify(phrasesData[0], null, 2));
    }
    
    res.json({
      phrases: phrasesData,
      count: phrases.length,
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    console.error('❌ Error getting phrases for player:', error);
    
    // Handle UUID format errors as client errors (400)
    if (error.message && error.message.includes('invalid input syntax for type uuid')) {
      return res.status(400).json({
        error: 'Invalid player ID format'
      });
    }
    
    res.status(500).json({ 
      error: 'Failed to get phrases' 
    });
  }
});

// Download phrases for offline play
app.get('/api/phrases/download/:playerId', async (req, res) => {
  try {
    if (!isDatabaseConnected) {
      return res.status(503).json({
        error: 'Database connection required for phrase download'
      });
    }
    
    const { playerId } = req.params;
    const countParam = req.query.count;
    const count = countParam !== undefined ? parseInt(countParam) : 15;
    
    // Validate UUID format
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(playerId)) {
      return res.status(400).json({
        error: 'Invalid player ID format'
      });
    }
    
    // Validate count parameter
    if (countParam !== undefined && (isNaN(count) || count < 1 || count > 50)) {
      return res.status(400).json({
        error: 'Count must be between 1 and 50'
      });
    }
    
    // Validate that player exists in database
    const player = await DatabasePlayer.getPlayerById(playerId);
    if (!player) {
      return res.status(404).json({ 
        error: 'Player not found' 
      });
    }
    
    // Get phrases for offline download
    const phrases = await DatabasePhrase.getOfflinePhrases(playerId, count);
    
    console.log(`📱 Phrases downloaded for offline play: ${phrases.length} phrases for player ${player.name}`);
    
    // Set appropriate message
    let message = `Downloaded ${phrases.length} phrases for offline play`;
    
    if (phrases.length === 0) {
      const { query } = require('./database/connection');
      
      // Check if there are any global phrases available at all
      const totalGlobalResult = await query(`
        SELECT COUNT(*) as total
        FROM phrases p
        WHERE p.is_global = true 
          AND p.is_approved = true
          AND p.created_by_player_id != $1
      `, [playerId]);
      
      const totalAvailable = parseInt(totalGlobalResult.rows[0].total);
      
      if (totalAvailable === 0) {
        message = "No global phrases are currently available. Check back soon for new content!";
      } else {
        message = "No new phrases available for download at this time";
      }
    }
    
    res.json({
      success: true,
      phrases: phrases.map(p => p.getPublicInfo()),
      count: phrases.length,
      requestedCount: count,
      timestamp: new Date().toISOString(),
      message: message
    });
    
  } catch (error) {
    console.error('❌ Error downloading phrases:', error);
    
    // Handle UUID format errors as client errors (400)
    if (error.message && error.message.includes('invalid input syntax for type uuid')) {
      return res.status(400).json({
        error: 'Invalid player ID format'
      });
    }
    
    res.status(500).json({ 
      error: 'Failed to download phrases' 
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

// Phrase difficulty analysis endpoint
app.post('/api/phrases/analyze-difficulty', async (req, res) => {
  try {
    const { phrase, language = 'en' } = req.body;
    
    // Validate input
    if (!phrase || typeof phrase !== 'string') {
      return res.status(400).json({
        error: 'Phrase is required and must be a string'
      });
    }
    
    if (phrase.trim().length === 0) {
      return res.status(400).json({
        error: 'Phrase cannot be empty'
      });
    }
    
    // Validate language
    const { LANGUAGES, calculateScore, getDifficultyLabel } = require('./services/difficultyScorer');
    const validLanguages = Object.values(LANGUAGES);
    
    if (!validLanguages.includes(language)) {
      return res.status(400).json({
        error: `Language must be one of: ${validLanguages.join(', ')}`
      });
    }
    
    // Calculate difficulty score
    const score = calculateScore({ phrase: phrase.trim(), language });
    const difficultyLabel = getDifficultyLabel(score);
    
    console.log(`📊 ANALYSIS: "${phrase}" (${language}) -> Score: ${score} (${difficultyLabel})`);
    
    res.json({
      phrase: phrase.trim(),
      language: language,
      score: score,
      difficulty: difficultyLabel,
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    console.error('❌ ANALYSIS: Error analyzing phrase:', error.message);
    res.status(500).json({
      error: 'Failed to analyze phrase difficulty',
      timestamp: new Date().toISOString()
    });
  }
});

// Phase 4.8: Hint System Endpoints

// Use hint endpoint
app.post('/api/phrases/:phraseId/hint/:level', async (req, res) => {
  try {
    if (!isDatabaseConnected) {
      return res.status(503).json({
        error: 'Database connection required for hint system'
      });
    }

    const { phraseId, level } = req.params;
    const { playerId } = req.body;

    // Validate input
    if (!playerId) {
      return res.status(400).json({
        error: 'Player ID is required'
      });
    }

    const hintLevel = parseInt(level);
    if (isNaN(hintLevel) || hintLevel < 1 || hintLevel > 3) {
      return res.status(400).json({
        error: 'Hint level must be 1, 2, or 3'
      });
    }

    // Validate UUIDs
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(phraseId) || !uuidRegex.test(playerId)) {
      return res.status(400).json({
        error: 'Invalid phrase ID or player ID format'
      });
    }

    // Use hint
    const result = await HintSystem.useHint(playerId, phraseId, hintLevel);

    res.json({
      success: true,
      hint: {
        level: result.hintLevel,
        content: result.hintContent,
        currentScore: result.currentScore,
        nextHintScore: result.nextHintScore,
        hintsRemaining: result.hintsRemaining,
        canUseNextHint: result.canUseNextHint
      },
      scorePreview: result.scorePreview,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ HINT: Error using hint:', error.message);
    
    if (error.message.includes('not found')) {
      return res.status(404).json({
        error: error.message
      });
    }
    
    if (error.name === 'HintValidationError' || error.message.includes('Invalid') || error.message.includes('Must use hints in order')) {
      return res.status(400).json({
        error: error.message
      });
    }

    res.status(500).json({
      error: 'Failed to use hint'
    });
  }
});

// Get hint status endpoint
app.get('/api/phrases/:phraseId/hints/status', async (req, res) => {
  try {
    if (!isDatabaseConnected) {
      return res.status(503).json({
        error: 'Database connection required for hint system'
      });
    }

    const { phraseId } = req.params;
    const { playerId } = req.query;

    // Validate input
    if (!playerId) {
      return res.status(400).json({
        error: 'Player ID is required'
      });
    }

    // Validate UUIDs
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(phraseId) || !uuidRegex.test(playerId)) {
      return res.status(400).json({
        error: 'Invalid phrase ID or player ID format'
      });
    }

    // Get hint status
    const status = await HintSystem.getHintStatus(playerId, phraseId);

    res.json({
      success: true,
      hintStatus: {
        hintsUsed: status.hintsUsed,
        nextHintLevel: status.nextHintLevel,
        hintsRemaining: status.hintsRemaining,
        currentScore: status.currentScore,
        nextHintScore: status.nextHintScore,
        canUseNextHint: status.canUseNextHint
      },
      scorePreview: status.scorePreview,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ HINT: Error getting hint status:', error.message);
    
    if (error.message.includes('not found')) {
      return res.status(404).json({
        error: error.message
      });
    }

    res.status(500).json({
      error: 'Failed to get hint status'
    });
  }
});

// Complete phrase with hint-based scoring endpoint
app.post('/api/phrases/:phraseId/complete', async (req, res) => {
  try {
    if (!isDatabaseConnected) {
      return res.status(503).json({
        error: 'Database connection required for phrase completion'
      });
    }

    const { phraseId } = req.params;
    const { playerId, completionTime = 0 } = req.body;

    // Validate input
    if (!playerId) {
      return res.status(400).json({
        error: 'Player ID is required'
      });
    }

    // Validate UUIDs
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(phraseId) || !uuidRegex.test(playerId)) {
      return res.status(400).json({
        error: 'Invalid phrase ID or player ID format'
      });
    }

    // Complete phrase with hint-based scoring
    const result = await HintSystem.completePhrase(playerId, phraseId, completionTime);

    // Get player and phrase info for activity broadcast
    const player = await DatabasePlayer.getPlayerById(playerId);
    const phrase = await DatabasePhrase.getPhraseById(phraseId);
    
    // Broadcast activity to monitoring dashboard
    if (player && phrase) {
      broadcastActivity('game', `Phrase completed: "${phrase.content.substring(0, 50)}${phrase.content.length > 50 ? '...' : ''}" by ${player.name}`, {
        phraseId: phraseId,
        playerId: playerId,
        playerName: player.name,
        content: phrase.content,
        finalScore: result.finalScore,
        hintsUsed: result.hintsUsed,
        completionTime: result.completionTime
      });

      // Notify phrase creator if this is a custom phrase completed by someone else
      if (phrase.createdByPlayerId && phrase.createdByPlayerId !== playerId) {
        const creator = await DatabasePlayer.getPlayerById(phrase.createdByPlayerId);
        if (creator && creator.socketId) {
          const notificationMessage = `${player.name} solved your anagram!`;
          
          // Send notification to creator via WebSocket
          io.to(creator.socketId).emit('phrase-completion-notification', {
            phraseId: phraseId,
            phraseContent: phrase.content,
            completedByName: player.name,
            completedByPlayerId: playerId,
            finalScore: result.finalScore,
            message: notificationMessage,
            timestamp: new Date().toISOString()
          });
          
          console.log(`📢 NOTIFICATION: Sent completion notification to ${creator.name} (creator) about phrase "${phrase.content}" solved by ${player.name}`);
        }
      }
    }

    res.json({
      success: true,
      completion: {
        finalScore: result.finalScore,
        hintsUsed: result.hintsUsed,
        completionTime: result.completionTime
      },
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ COMPLETION: Error completing phrase:', error.message);
    
    if (error.message.includes('not found') || error.message.includes('Failed to complete')) {
      return res.status(404).json({
        error: error.message
      });
    }

    res.status(500).json({
      error: 'Failed to complete phrase'
    });
  }
});

// Get phrase with hint preview endpoint
app.get('/api/phrases/:phraseId/preview', async (req, res) => {
  try {
    if (!isDatabaseConnected) {
      return res.status(503).json({
        error: 'Database connection required for phrase preview'
      });
    }

    const { phraseId } = req.params;
    const { playerId } = req.query;

    // Validate input
    if (!playerId) {
      return res.status(400).json({
        error: 'Player ID is required'
      });
    }

    // Validate UUIDs
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(phraseId) || !uuidRegex.test(playerId)) {
      return res.status(400).json({
        error: 'Invalid phrase ID or player ID format'
      });
    }

    // Get phrase with hint preview
    const phraseData = await HintSystem.getPhraseWithHintPreview(phraseId, playerId);

    res.json({
      success: true,
      phrase: {
        id: phraseData.id,
        content: phraseData.content,
        hint: phraseData.hint,
        difficultyLevel: phraseData.difficulty_level,
        isGlobal: phraseData.is_global,
        hintStatus: phraseData.hintStatus,
        scorePreview: phraseData.scorePreview
      },
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ PREVIEW: Error getting phrase preview:', error.message);
    
    if (error.message.includes('not found')) {
      return res.status(404).json({
        error: error.message
      });
    }

    res.status(500).json({
      error: 'Failed to get phrase preview'
    });
  }
});

// ============================================
// SCORING SYSTEM ENDPOINTS (Phase 4.9)
// ============================================

/**
 * @swagger
 * /api/scores/player/{playerId}:
 *   get:
 *     summary: Get player score summary
 *     description: Returns comprehensive scoring information for a player including daily, weekly, and total scores with rankings
 *     tags: [Scoring System]
 *     parameters:
 *       - in: path
 *         name: playerId
 *         required: true
 *         schema:
 *           type: string
 *           format: uuid
 *         description: UUID of the player
 *     responses:
 *       200:
 *         description: Player score summary retrieved successfully
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success:
 *                   type: boolean
 *                   example: true
 *                 scores:
 *                   type: object
 *                   properties:
 *                     dailyScore:
 *                       type: integer
 *                       example: 150
 *                     dailyRank:
 *                       type: integer
 *                       example: 5
 *                     weeklyScore:
 *                       type: integer
 *                       example: 890
 *                     weeklyRank:
 *                       type: integer
 *                       example: 12
 *                     totalScore:
 *                       type: integer
 *                       example: 2340
 *                     totalRank:
 *                       type: integer
 *                       example: 25
 *                     totalPhrases:
 *                       type: integer
 *                       example: 47
 *       400:
 *         description: Invalid player ID format
 *       404:
 *         description: Player not found
 *       503:
 *         description: Database connection required
 */
app.get('/api/scores/player/:playerId', async (req, res) => {
  try {
    if (!isDatabaseConnected) {
      return res.status(503).json({
        error: 'Database connection required for scoring system'
      });
    }

    const { playerId } = req.params;

    // Validate UUID format
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(playerId)) {
      return res.status(400).json({
        error: 'Invalid player ID format'
      });
    }

    // Verify player exists
    const player = await DatabasePlayer.getPlayerById(playerId);
    if (!player) {
      return res.status(404).json({
        error: 'Player not found'
      });
    }

    // Get player score summary
    const scores = await ScoringSystem.getPlayerScoreSummary(playerId);
    
    // Get skill level and title based on total score
    const skillInfo = ScoringSystem.getSkillLevel(scores.totalScore);

    res.json({
      success: true,
      playerId,
      playerName: player.name,
      scores: {
        ...scores,
        skillTitle: skillInfo.title,
        skillLevel: skillInfo.level
      },
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ SCORES: Error getting player scores:', error.message);
    res.status(500).json({
      error: 'Failed to get player scores'
    });
  }
});

/**
 * @swagger
 * /api/leaderboards/{period}:
 *   get:
 *     summary: Get leaderboard for specific period
 *     description: Returns leaderboard rankings for daily, weekly, or total scores
 *     tags: [Scoring System]
 *     parameters:
 *       - in: path
 *         name: period
 *         required: true
 *         schema:
 *           type: string
 *           enum: [daily, weekly, total]
 *         description: Leaderboard period
 *       - in: query
 *         name: limit
 *         schema:
 *           type: integer
 *           minimum: 1
 *           maximum: 100
 *           default: 50
 *         description: Number of top players to return
 *       - in: query
 *         name: offset
 *         schema:
 *           type: integer
 *           minimum: 0
 *           default: 0
 *         description: Number of players to skip (for pagination)
 *     responses:
 *       200:
 *         description: Leaderboard retrieved successfully
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success:
 *                   type: boolean
 *                   example: true
 *                 leaderboard:
 *                   type: array
 *                   items:
 *                     type: object
 *                     properties:
 *                       rank:
 *                         type: integer
 *                         example: 1
 *                       playerName:
 *                         type: string
 *                         example: "TopPlayer"
 *                       totalScore:
 *                         type: integer
 *                         example: 2340
 *                       phrasesCompleted:
 *                         type: integer
 *                         example: 47
 *                 pagination:
 *                   type: object
 *                   properties:
 *                     total:
 *                       type: integer
 *                       example: 150
 *                     limit:
 *                       type: integer
 *                       example: 50
 *                     offset:
 *                       type: integer
 *                       example: 0
 *                     hasMore:
 *                       type: boolean
 *                       example: true
 *       400:
 *         description: Invalid period or parameters
 *       503:
 *         description: Database connection required
 */
app.get('/api/leaderboards/:period', async (req, res) => {
  try {
    if (!isDatabaseConnected) {
      return res.status(503).json({
        error: 'Database connection required for leaderboards'
      });
    }

    const { period } = req.params;
    const limit = req.query.limit !== undefined ? Math.min(parseInt(req.query.limit), 100) : 50;
    const offset = parseInt(req.query.offset) || 0;

    // Validate period
    if (!['daily', 'weekly', 'total'].includes(period)) {
      return res.status(400).json({
        error: 'Invalid period. Must be daily, weekly, or total'
      });
    }

    // Validate pagination parameters
    if (limit < 1 || offset < 0) {
      return res.status(400).json({
        error: 'Invalid pagination parameters'
      });
    }

    // Get leaderboard
    const leaderboardData = await ScoringSystem.getLeaderboard(period, limit, offset);

    res.json({
      success: true,
      ...leaderboardData,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ LEADERBOARD: Error getting leaderboard:', error.message);
    res.status(500).json({
      error: 'Failed to get leaderboard'
    });
  }
});

/**
 * @swagger
 * /api/stats/global:
 *   get:
 *     summary: Get global scoring statistics
 *     description: Returns comprehensive statistics about the scoring system including total players, scores, and activity
 *     tags: [Scoring System]
 *     responses:
 *       200:
 *         description: Global statistics retrieved successfully
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success:
 *                   type: boolean
 *                   example: true
 *                 stats:
 *                   type: object
 *                   properties:
 *                     overall:
 *                       type: object
 *                       properties:
 *                         activePlayers:
 *                           type: integer
 *                           example: 150
 *                         totalCompletions:
 *                           type: integer
 *                           example: 2340
 *                         averageScore:
 *                           type: string
 *                           example: "45.6"
 *                         highestScore:
 *                           type: integer
 *                           example: 100
 *                         totalPointsAwarded:
 *                           type: integer
 *                           example: 156780
 *                     today:
 *                       type: object
 *                       properties:
 *                         completions:
 *                           type: integer
 *                           example: 67
 *                         activePlayers:
 *                           type: integer
 *                           example: 23
 *                         pointsAwarded:
 *                           type: integer
 *                           example: 3450
 *                     leaderboards:
 *                       type: object
 *                       properties:
 *                         daily:
 *                           type: integer
 *                           example: 23
 *                         weekly:
 *                           type: integer
 *                           example: 89
 *                         total:
 *                           type: integer
 *                           example: 150
 *       503:
 *         description: Database connection required
 */
app.get('/api/stats/global', async (req, res) => {
  try {
    if (!isDatabaseConnected) {
      return res.status(503).json({
        error: 'Database connection required for global statistics'
      });
    }

    // Get global statistics
    const globalStats = await ScoringSystem.getGlobalStats();

    res.json({
      success: true,
      stats: globalStats,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ STATS: Error getting global statistics:', error.message);
    res.status(500).json({
      error: 'Failed to get global statistics'
    });
  }
});

/**
 * @swagger
 * /api/scores/refresh:
 *   post:
 *     summary: Refresh all leaderboards (admin endpoint)
 *     description: Manually refresh all leaderboard rankings and score aggregations
 *     tags: [Scoring System]
 *     responses:
 *       200:
 *         description: Leaderboards refreshed successfully
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success:
 *                   type: boolean
 *                   example: true
 *                 updated:
 *                   type: object
 *                   properties:
 *                     dailyUpdated:
 *                       type: integer
 *                       example: 23
 *                     weeklyUpdated:
 *                       type: integer
 *                       example: 89
 *                     totalUpdated:
 *                       type: integer
 *                       example: 150
 *       503:
 *         description: Database connection required
 */
app.post('/api/scores/refresh', async (req, res) => {
  try {
    if (!isDatabaseConnected) {
      return res.status(503).json({
        error: 'Database connection required for leaderboard refresh'
      });
    }

    // Refresh all leaderboards
    const refreshResult = await ScoringSystem.refreshAllLeaderboards();

    res.json({
      success: true,
      message: 'All leaderboards refreshed successfully',
      updated: {
        dailyUpdated: refreshResult.dailyUpdated,
        weeklyUpdated: refreshResult.weeklyUpdated,
        totalUpdated: refreshResult.totalUpdated
      },
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ REFRESH: Error refreshing leaderboards:', error.message);
    res.status(500).json({
      error: 'Failed to refresh leaderboards'
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

// Emoji Collection Routes
const emojiRoutes = require('./routes/emoji');
app.use('/api/emoji', emojiRoutes);

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
    });
  } catch (error) {
    console.error('❌ Server startup failed:', error);
    process.exit(1);
  }
}

// Start the server
startServer();

module.exports = { app, server, io };