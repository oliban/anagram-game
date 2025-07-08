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
const { HintSystem, HintValidationError } = require('./services/hintSystem');
const ScoringSystem = require('./services/scoringSystem');
const { detectLanguage } = require('./services/difficultyScorer');

// Swagger documentation setup
const swaggerUi = require('swagger-ui-express');
const swaggerFile = require('./swagger-output.json');

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

// Swagger UI setup
app.use('/api/docs', swaggerUi.serve, swaggerUi.setup(swaggerFile, {
  customCss: '.swagger-ui .topbar { display: none }',
  customSiteTitle: 'Anagram Game API Documentation'
}));

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
    
    const { name, socketId } = req.body;
    
    // Validate input
    if (!name || typeof name !== 'string') {
      return res.status(400).json({ 
        error: 'Player name is required and must be a string' 
      });
    }

    // Validate socketId if provided
    if (socketId !== null && socketId !== undefined && typeof socketId !== 'string') {
      return res.status(400).json({
        error: 'Socket ID must be a string or null'
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
    
    // Auto-detect language if not provided
    const detectedLanguage = language || detectLanguage(content);

    // Create phrase in database
    const phrase = await DatabasePhrase.createPhrase({
      content,
      senderId,
      targetId,
      hint: req.body.hint || null, // Optional hint support
      language: detectedLanguage
    });
    
    console.log(`📝 Phrase created: "${content}" from ${sender.name} to ${target.name}`);
    
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
      targetIds = [],
      isGlobal = false,
      difficultyLevel = 1,
      phraseType = 'custom',
      language // Optional - will be auto-detected if not provided
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

    // Auto-detect language if not provided
    const detectedLanguage = language || detectLanguage(content);

    // Create enhanced phrase
    const result = await DatabasePhrase.createEnhancedPhrase({
      content,
      hint,
      senderId,
      targetIds,
      isGlobal,
      phraseType,
      language: detectedLanguage
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

    res.json({
      success: true,
      playerId,
      playerName: player.name,
      scores,
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