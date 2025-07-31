const express = require('express');
const path = require('path');
const router = express.Router();

// System routes - health checks, monitoring, and configuration

module.exports = (dependencies) => {
  const { getDatabaseStatus, getDbStats, configService } = dependencies;

  // Health check endpoint
  router.get('/api/status', async (req, res) => {
    try {
      // Check database connection
      const isDatabaseConnected = getDatabaseStatus();
      const dbStats = isDatabaseConnected ? await getDbStats() : null;
      
      res.json({ 
        status: 'healthy', 
        service: 'game-server',
        database: isDatabaseConnected ? 'connected' : 'disconnected',
        timestamp: new Date().toISOString(),
        stats: dbStats
      });
    } catch (error) {
      res.status(503).json({
        status: 'unhealthy',
        service: 'game-server', 
        error: error.message,
        timestamp: new Date().toISOString()
      });
    }
  });

  // Monitoring dashboard
  router.get('/monitoring', (req, res) => {
    res.sendFile(path.join(__dirname, '../../web-dashboard/public/monitoring/index.html'));
  });

  // Contribution page
  router.get('/contribute/:token', (req, res) => {
    res.sendFile(path.join(__dirname, '../../web-dashboard/public/contribute/index.html'));
  });

  // REMOVED: /api/config - iOS uses /api/config/levels instead (Phase 3 cleanup)

  // REMOVED: /api/admin/config - Admin-only feature, no consumers found (Phase 3 cleanup)

  // Level configuration
  router.get('/api/config/levels', async (req, res) => {
    try {
      // Load level configuration from file
      const fs = require('fs').promises;
      const configPath = path.join(__dirname, '../shared/config', 'level-config.json');
      
      const configData = await fs.readFile(configPath, 'utf8');
      const levelConfig = JSON.parse(configData);
      
      res.json({
        success: true,
        config: levelConfig,
        timestamp: new Date().toISOString()
      });
      
    } catch (error) {
      console.error('❌ Error loading level config:', error);
      
      // Return fallback configuration
      res.json({
        success: false,
        error: 'Failed to load level configuration',
        fallback: {
          skillLevels: [
            { id: 1, title: 'beginner', pointsRequired: 0, maxDifficulty: 50 },
            { id: 2, title: 'wretched', pointsRequired: 230, maxDifficulty: 100 },
            { id: 3, title: 'adequate', pointsRequired: 750, maxDifficulty: 150 },
            { id: 4, title: 'competent', pointsRequired: 1800, maxDifficulty: 200 },
            { id: 5, title: 'skilled', pointsRequired: 3500, maxDifficulty: 250 }
          ],
          baseDifficultyPerLevel: 50
        },
        timestamp: new Date().toISOString()
      });
    }
  });

  return router;
};