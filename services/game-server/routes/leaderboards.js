const express = require('express');
const router = express.Router();

// Leaderboard routes - statistics and leaderboard data

module.exports = (dependencies) => {
  const { getDatabaseStatus, ScoringSystem } = dependencies;

  // Get leaderboards (plural endpoint)
  router.get('/api/leaderboards/:period', async (req, res) => {
    try {
      if (!getDatabaseStatus()) {
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

  // Get leaderboard (singular endpoint for iOS app compatibility)
  router.get('/api/leaderboard/:period', async (req, res) => {
    try {
      if (!getDatabaseStatus()) {
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

      console.log(`📊 LEADERBOARD (SINGULAR): Getting ${period} leaderboard for iOS app`);

      // Get leaderboard - same logic as plural endpoint
      const leaderboardData = await ScoringSystem.getLeaderboard(period, limit, offset);

      res.json({
        success: true,
        ...leaderboardData,
        timestamp: new Date().toISOString()
      });

    } catch (error) {
      console.error('❌ LEADERBOARD (SINGULAR): Error getting leaderboard:', error.message);
      res.status(500).json({
        error: 'Failed to get leaderboard'
      });
    }
  });

  // Get global statistics
  router.get('/api/stats/global', async (req, res) => {
    try {
      if (!getDatabaseStatus()) {
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

  // Refresh all leaderboards
  router.post('/api/scores/refresh', async (req, res) => {
    try {
      if (!getDatabaseStatus()) {
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

  return router;
};