// Load environment variables
require('dotenv').config();

const express = require('express');
const cors = require('cors');
const { testConnection, shutdown: shutdownDb } = require('./shared/database/connection');
const ContributionLinkGenerator = require('./link-generator');
const RouteAnalytics = require('./shared/services/routeAnalytics');

const app = express();

// Initialize route analytics and link generator
const routeAnalytics = new RouteAnalytics('link-generator');
const linkGenerator = new ContributionLinkGenerator();

// Middleware
app.use(cors());
app.use(express.json());

// Route analytics middleware (only for API routes)
app.use('/api', routeAnalytics.createMiddleware());

// Health check endpoint
app.get('/api/status', (req, res) => {
  res.json({ 
    status: 'healthy', 
    service: 'link-generator',
    timestamp: new Date().toISOString() 
  });
});

// Link generation endpoints
app.post('/api/links/generate', async (req, res) => {
  try {
    const { type, expirationDays } = req.body;
    const link = await linkGenerator.generateLink(type, expirationDays);
    res.json({ success: true, link });
  } catch (error) {
    console.error('Link generation error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Contribution link generation endpoint (for iOS compatibility)
app.post('/api/contribution/request', async (req, res) => {
  try {
    const { playerId, expirationHours, maxUses } = req.body;
    
    console.log('📝 CONTRIBUTION: Received request:', { playerId, expirationHours, maxUses });
    
    if (!playerId) {
      return res.status(400).json({ 
        success: false, 
        error: 'playerId is required' 
      });
    }
    
    const link = await linkGenerator.createContributionLink(playerId, {
      expirationHours: expirationHours || 24,
      maxUses: maxUses || 3
    });
    
    console.log('✅ CONTRIBUTION: Link created successfully:', link);
    
    res.json({ 
      success: true, 
      link
    });
  } catch (error) {
    console.error('❌ CONTRIBUTION: Link generation error:', error);
    console.error('❌ CONTRIBUTION: Full error details:', error.stack);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

app.get('/api/links/validate/:token', async (req, res) => {
  try {
    const { token } = req.params;
    const isValid = await linkGenerator.validateLink(token);
    res.json({ valid: isValid });
  } catch (error) {
    console.error('Link validation error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

const PORT = process.env.LINK_GENERATOR_PORT || 3002;

// Initialize database and start server
async function startServer() {
  try {
    await testConnection();
    console.log('✅ Database connected successfully');
    
    app.listen(PORT, () => {
      console.log(`🔗 Link Generator Service running on port ${PORT}`);
    });
  } catch (error) {
    console.error('❌ Failed to start link generator service:', error);
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