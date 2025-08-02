// Load environment variables
require('dotenv').config();

const express = require('express');
const cors = require('cors');
const path = require('path');
const { testConnection, shutdown: shutdownDb } = require('./shared/database/connection');
const RouteAnalytics = require('./shared/services/routeAnalytics');

const app = express();

// Initialize route analytics
const routeAnalytics = new RouteAnalytics('web-dashboard');

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));
app.use('/web', express.static(path.join(__dirname, 'public')));

// Route analytics middleware (only for API routes)
app.use('/api', routeAnalytics.createMiddleware());

// Health check endpoint
app.get('/api/status', (req, res) => {
  res.json({ 
    status: 'healthy', 
    service: 'web-dashboard',
    timestamp: new Date().toISOString() 
  });
});

// Web dashboard routes
app.use('/api', require('./web-routes'));

// Serve dashboard pages
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.get('/contribute', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'contribute', 'index.html'));
});

// Handle contribution links with tokens
app.get('/contribute/:token', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'contribute', 'index.html'));
});

app.get('/monitoring', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'monitoring', 'index.html'));
});

const PORT = process.env.WEB_DASHBOARD_PORT || 3001;

// Initialize database and start server
async function startServer() {
  try {
    await testConnection();
    console.log('✅ Database connected successfully');
    
    app.listen(PORT, () => {
      console.log(`📊 Web Dashboard running on port ${PORT}`);
      console.log(`🌐 Dashboard: http://localhost:${PORT}`);
    });
  } catch (error) {
    console.error('❌ Failed to start web dashboard:', error);
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