// Load environment variables
require('dotenv').config();

const express = require('express');
const cors = require('cors');
const path = require('path');
const { testConnection, shutdown: shutdownDb, pool } = require('./shared/database/connection');
const ContributionLinkGenerator = require('./link-generator');
const RouteAnalytics = require('./shared/services/routeAnalytics');
const levelConfig = require('./shared/config/level-config.json');

const app = express();

// Initialize route analytics and link generator
const routeAnalytics = new RouteAnalytics('link-generator');
const linkGenerator = new ContributionLinkGenerator();

// CORS configuration - secure but development-friendly
const isDevelopment = process.env.NODE_ENV === 'development';
const isSecurityRelaxed = process.env.SECURITY_RELAXED === 'true';

// In development with SECURITY_RELAXED, allow all origins
const corsOptions = isDevelopment && isSecurityRelaxed ? {
  origin: true, // Allow all origins in relaxed development mode
  methods: ["GET", "POST"],
  credentials: true
} : {
  origin: function (origin, callback) {
    const allowedOrigins = isDevelopment 
      ? ['http://localhost:3000', 'http://localhost:3001', 'http://localhost:3002',
         'http://192.168.1.133:3000', 'http://192.168.1.133:3001', 'http://192.168.1.133:3002']
      : ['https://your-production-domain.com', 'https://anagram-staging-alb-1354034851.eu-west-1.elb.amazonaws.com'];
    
    // Allow requests with no origin (mobile apps, curl, iOS simulator)
    if (!origin || allowedOrigins.indexOf(origin) !== -1) {
      callback(null, true);
    } else {
      if (process.env.LOG_SECURITY_EVENTS === 'true') {
        console.log(`🚫 CORS: Blocked origin: ${origin}`);
      }
      callback(new Error('Not allowed by CORS'));
    }
  },
  methods: ["GET", "POST"],
  credentials: true
};

// Middleware
app.use(cors(corsOptions));
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Route analytics middleware (only for API routes)
app.use('/api', routeAnalytics.createMiddleware());

// Health check endpoint
app.get('/api/status', (req, res) => {
  res.json({ 
    status: 'healthy', 
    service: 'link-generator',
    timestamp: new Date().toISOString(),
    debug: 'validateToken method has debug logging v2'
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

// Import route modules
const contributionRoutesFactory = require('./routes/contributions');

// Function to get route dependencies
const getRouteDependencies = () => {
  return {
    linkGenerator,
    pool,
    levelConfig,
    routeAnalytics
  };
};

// Initialize and use route modules
const initializeRoutes = () => {
  console.log('🔧 ROUTES: Initializing contribution routes...');
  const deps = getRouteDependencies();
  const contributionRoutes = contributionRoutesFactory(deps);
  app.use(contributionRoutes);
  console.log('✅ ROUTES: Contribution routes initialized');
};

// Validate contribution token with detailed info (simple endpoint for internal use)
app.get('/api/validate/:token', async (req, res) => {
  try {
    const { token } = req.params;
    console.log(`🔍 SERVER: /api/validate/${token} endpoint hit`);
    const validation = await linkGenerator.validateToken(token);
    console.log(`🔍 SERVER: Validation result:`, validation);
    res.json(validation);
  } catch (error) {
    console.error('❌ SERVER: Contribution token validation error:', error);
    res.status(500).json({ 
      valid: false, 
      reason: 'Internal server error',
      error: error.message 
    });
  }
});

const PORT = process.env.LINK_GENERATOR_PORT || 3002;

// Initialize database and start server
async function startServer() {
  try {
    console.log('🚀 SERVER: Starting server...');
    await testConnection();
    console.log('✅ Database connected successfully');
    
    // Initialize routes after database connection
    console.log('🔧 SERVER: About to initialize routes...');
    try {
      initializeRoutes();
      console.log('✅ Routes initialized');
    } catch (routeError) {
      console.error('❌ ROUTES: Error initializing routes:', routeError);
      throw routeError;
    }
    
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