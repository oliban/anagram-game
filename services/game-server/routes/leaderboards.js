const express = require('express');
const router = express.Router();

// Leaderboard routes - statistics and leaderboard data

module.exports = (dependencies) => {
  const { getDatabaseStatus, ScoringSystem } = dependencies;

  // REMOVED: /api/leaderboards/:period - Legacy plural endpoint (Legacy cleanup)

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

  // Get player ranking in specific leaderboard - NEW endpoint for iOS app
  router.get('/api/leaderboard/:type/player/:playerId', async (req, res) => {
    try {
      if (!getDatabaseStatus()) {
        return res.status(503).json({
          error: 'Database connection required for player ranking lookup'
        });
      }

      const { type, playerId } = req.params;

      // Validate leaderboard type - map iOS naming to internal naming
      const leaderboardTypeMapping = {
        'daily': 'daily',
        'weekly': 'weekly', 
        'alltime': 'total'
      };

      const internalType = leaderboardTypeMapping[type];
      if (!internalType) {
        return res.status(400).json({
          error: 'Invalid leaderboard type. Must be daily, weekly, or alltime'
        });
      }

      // Validate UUID format for playerId
      const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      if (!uuidRegex.test(playerId)) {
        return res.status(400).json({
          error: 'Invalid player ID format'
        });
      }

      console.log(`🔍 RANKING: Looking up player ${playerId} ranking in ${type} leaderboard`);

      // Get player's rank from the scoring system
      const playerRank = await ScoringSystem.getPlayerRank(playerId, internalType);

      if (playerRank === null) {
        return res.status(404).json({
          error: 'Player not found in leaderboard or has no scores'
        });
      }

      const result = {
        success: true,
        playerId: playerId,
        leaderboardType: type,
        rank: playerRank,
        timestamp: new Date().toISOString()
      };

      console.log(`✅ RANKING: Player ${playerId} is rank ${playerRank} in ${type} leaderboard`);
      
      res.json(result);

    } catch (error) {
      console.error('❌ RANKING: Error getting player ranking:', error.message);
      
      // Handle UUID format errors as client errors (400)
      if (error.message && error.message.includes('invalid input syntax for type uuid')) {
        return res.status(400).json({
          error: 'Invalid player ID format'
        });
      }

      res.status(500).json({
        error: 'Failed to get player ranking'
      });
    }
  });

  // REMOVED: /api/stats/global - Admin/monitoring feature, no consumers (Phase 3 cleanup)

  // REMOVED: /api/scores/refresh - Admin-only feature, no consumers (Phase 3 cleanup)

  return router;
};