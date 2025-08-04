// Load environment variables
require('dotenv').config();

const express = require('express');
const cors = require('cors');
const path = require('path');
const { testConnection, shutdown: shutdownDb } = require('./shared/database/connection');
const RouteAnalytics = require('./shared/services/routeAnalytics');

const app = express();

// Initialize route analytics
const routeAnalytics = new RouteAnalytics('admin-service');

// CORS configuration - secure but development-friendly
const isDevelopment = process.env.NODE_ENV === 'development';
const isSecurityRelaxed = process.env.SECURITY_RELAXED === 'true';

// In development with SECURITY_RELAXED, allow all origins
const corsOptions = isDevelopment && isSecurityRelaxed ? {
  origin: true, // Allow all origins in relaxed development mode
  methods: ["GET", "POST", "PUT", "DELETE"],
  credentials: true
} : {
  origin: function (origin, callback) {
    const allowedOrigins = isDevelopment 
      ? ['http://localhost:3000', 'http://localhost:3001', 'http://localhost:3002', 'http://localhost:3003',
         'http://192.168.1.133:3000', 'http://192.168.1.133:3001', 'http://192.168.1.133:3002', 'http://192.168.1.133:3003']
      : ['https://your-production-domain.com', 'https://anagram-staging-alb-1354034851.eu-west-1.elb.amazonaws.com'];
    
    // Allow requests with no origin (curl, Postman, etc.)
    if (!origin || allowedOrigins.indexOf(origin) !== -1) {
      callback(null, true);
    } else {
      if (process.env.LOG_SECURITY_EVENTS === 'true') {
        console.log(`🚫 CORS: Blocked origin: ${origin}`);
      }
      callback(new Error('Not allowed by CORS'));
    }
  },
  methods: ["GET", "POST", "PUT", "DELETE"],
  credentials: true
};

// Middleware
app.use(cors(corsOptions));
app.use(express.json({ limit: '10mb' })); // Larger limit for batch operations
app.use(express.static(path.join(__dirname, 'public')));

// Route analytics middleware (only for API routes)
app.use('/api', routeAnalytics.createMiddleware());

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