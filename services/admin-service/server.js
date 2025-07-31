// Load environment variables
require('dotenv').config();

const express = require('express');
const cors = require('cors');
const path = require('path');
const { testConnection, shutdown: shutdownDb } = require('./shared/database/connection');

const app = express();

// Middleware
app.use(cors());
app.use(express.json({ limit: '10mb' })); // Larger limit for batch operations
app.use(express.static(path.join(__dirname, 'public')));

// Health check endpoint
app.get('/api/status', (req, res) => {
  res.json({ 
    status: 'healthy', 
    service: 'admin-service',
    timestamp: new Date().toISOString() 
  });
});

// Admin routes
app.use('/api/admin', require('./admin-routes'));

const PORT = process.env.ADMIN_SERVICE_PORT || 3003;

// Initialize database and start server
async function startServer() {
  try {
    await testConnection();
    console.log('✅ Database connected successfully');
    
    app.listen(PORT, () => {
      console.log(`🔧 Admin Service running on port ${PORT}`);
      console.log(`🛠️  Admin API: http://localhost:${PORT}/api/admin`);
    });
  } catch (error) {
    console.error('❌ Failed to start admin service:', error);
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('🛑 Received SIGTERM, shutting down gracefully...');
  await shutdownDb();
  process.exit(0);
});

startServer();