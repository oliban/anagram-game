// Load environment variables
require('dotenv').config();

const express = require('express');
const cors = require('cors');
const { createServer } = require('http');
const { Server } = require('socket.io');

// Database modules
const { testConnection, getStats: getDbStats, shutdown: shutdownDb, pool, query } = require('./shared/database/connection');
const DatabasePlayer = require('./shared/database/models/DatabasePlayer');
const DatabasePhrase = require('./shared/database/models/DatabasePhrase');
const { HintSystem, HintValidationError } = require('./shared/services/hintSystem');
const ScoringSystem = require('./shared/services/scoringSystem');

const app = express();
const server = createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// Health check endpoint
app.get('/api/status', (req, res) => {
  res.json({ 
    status: 'healthy', 
    service: 'game-server',
    timestamp: new Date().toISOString() 
  });
});

// Game server routes (TODO: Create these route files)
// app.use(require('./routes/players'));
// app.use(require('./routes/phrases'));
// app.use(require('./routes/games'));

// WebSocket connection handling
io.on('connection', (socket) => {
  console.log('Player connected:', socket.id);
  
  socket.on('disconnect', () => {
    console.log('Player disconnected:', socket.id);
  });
});

const PORT = process.env.PORT || 3000;

// Initialize database and start server
async function startServer() {
  try {
    await testConnection();
    console.log('✅ Database connected successfully');
    
    server.listen(PORT, () => {
      console.log(`🎮 Game Server running on port ${PORT}`);
      console.log(`📡 WebSocket server ready`);
    });
  } catch (error) {
    console.error('❌ Failed to start server:', error);
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('🛑 Received SIGTERM, shutting down gracefully...');
  await shutdownDb();
  server.close(() => {
    console.log('✅ Game server closed');
    process.exit(0);
  });
});

startServer();