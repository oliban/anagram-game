/**
 * Scoring System Service
 * Handles player scoring, leaderboards, and score aggregations
 */

const { pool } = require('../database/connection');

class ScoringSystem {
  
  /**
   * Update player score aggregations after phrase completion
   * Called automatically when a phrase is completed
   */
  static async updatePlayerScores(playerId) {
    try {
      const client = await pool.connect();
      try {
        // Update all score aggregations for the player
        await client.query('SELECT update_player_score_aggregations($1)', [playerId]);
        
        // Update leaderboard rankings for all periods
        await client.query('SELECT update_leaderboard_rankings($1)', ['daily']);
        await client.query('SELECT update_leaderboard_rankings($1)', ['weekly']);
        await client.query('SELECT update_leaderboard_rankings($1)', ['total']);
        
        console.log(`📊 SCORING: Updated scores and rankings for player ${playerId}`);
        return true;
      } finally {
        client.release();
      }
    } catch (error) {
      console.error('❌ SCORING: Error updating player scores:', error);
      throw error;
    }
  }

  /**
   * Get comprehensive player score summary
   */
  static async getPlayerScoreSummary(playerId) {
    try {
      const client = await pool.connect();
      try {
        const result = await client.query(
          'SELECT * FROM get_player_score_summary($1)',
          [playerId]
        );
        
        if (result.rows.length === 0) {
          return {
            dailyScore: 0,
            dailyRank: 0,
            weeklyScore: 0,
            weeklyRank: 0,
            totalScore: 0,
            totalRank: 0,
            totalPhrases: 0
          };
        }
        
        const row = result.rows[0];
        return {
          dailyScore: row.daily_score,
          dailyRank: row.daily_rank,
          weeklyScore: row.weekly_score,
          weeklyRank: row.weekly_rank,
          totalScore: row.total_score,
          totalRank: row.total_rank,
          totalPhrases: row.total_phrases
        };
      } finally {
        client.release();
      }
    } catch (error) {
      console.error('❌ SCORING: Error getting player score summary:', error);
      throw error;
    }
  }

  /**
   * Get leaderboard for specific period
   */
  static async getLeaderboard(period, limit = 50, offset = 0) {
    if (!['daily', 'weekly', 'total'].includes(period)) {
      throw new Error('Invalid period. Must be daily, weekly, or total');
    }

    try {
      const client = await pool.connect();
      try {
        let periodStart;
        switch (period) {
          case 'daily':
            periodStart = new Date().toISOString().split('T')[0]; // Today
            break;
          case 'weekly':
            // Get start of current week (Monday)
            const now = new Date();
            const dayOfWeek = now.getDay();
            const mondayOffset = dayOfWeek === 0 ? -6 : 1 - dayOfWeek;
            const monday = new Date(now);
            monday.setDate(now.getDate() + mondayOffset);
            periodStart = monday.toISOString().split('T')[0];
            break;
          case 'total':
            periodStart = '1970-01-01';
            break;
        }

        const result = await client.query(
          `SELECT 
             rank_position,
             player_name,
             total_score,
             phrases_completed,
             created_at
           FROM leaderboards 
           WHERE score_period = $1 
           AND period_start = $2
           ORDER BY rank_position 
           LIMIT $3 OFFSET $4`,
          [period, periodStart, limit, offset]
        );

        // Get total count for pagination
        const countResult = await client.query(
          `SELECT COUNT(*) as total_count 
           FROM leaderboards 
           WHERE score_period = $1 
           AND period_start = $2`,
          [period, periodStart]
        );

        return {
          leaderboard: result.rows.map(row => ({
            rank: row.rank_position,
            playerName: row.player_name,
            totalScore: row.total_score,
            phrasesCompleted: row.phrases_completed,
            lastUpdated: row.created_at
          })),
          pagination: {
            total: parseInt(countResult.rows[0].total_count),
            limit,
            offset,
            hasMore: offset + limit < parseInt(countResult.rows[0].total_count)
          },
          period,
          periodStart
        };
      } finally {
        client.release();
      }
    } catch (error) {
      console.error('❌ SCORING: Error getting leaderboard:', error);
      throw error;
    }
  }

  /**
   * Get player ranking in specific period
   */
  static async getPlayerRanking(playerId, period) {
    if (!['daily', 'weekly', 'total'].includes(period)) {
      throw new Error('Invalid period. Must be daily, weekly, or total');
    }

    try {
      const client = await pool.connect();
      try {
        let periodStart;
        switch (period) {
          case 'daily':
            periodStart = new Date().toISOString().split('T')[0];
            break;
          case 'weekly':
            const now = new Date();
            const dayOfWeek = now.getDay();
            const mondayOffset = dayOfWeek === 0 ? -6 : 1 - dayOfWeek;
            const monday = new Date(now);
            monday.setDate(now.getDate() + mondayOffset);
            periodStart = monday.toISOString().split('T')[0];
            break;
          case 'total':
            periodStart = '1970-01-01';
            break;
        }

        const result = await client.query(
          `SELECT 
             rank_position,
             total_score,
             phrases_completed,
             (SELECT COUNT(*) FROM leaderboards WHERE score_period = $1 AND period_start = $2) as total_players
           FROM leaderboards 
           WHERE score_period = $1 
           AND period_start = $2
           AND player_id = $3`,
          [period, periodStart, playerId]
        );

        if (result.rows.length === 0) {
          return {
            rank: 0,
            score: 0,
            phrasesCompleted: 0,
            totalPlayers: 0,
            period
          };
        }

        const row = result.rows[0];
        return {
          rank: row.rank_position,
          score: row.total_score,
          phrasesCompleted: row.phrases_completed,
          totalPlayers: row.total_players,
          period
        };
      } finally {
        client.release();
      }
    } catch (error) {
      console.error('❌ SCORING: Error getting player ranking:', error);
      throw error;
    }
  }

  /**
   * Get global scoring statistics
   */
  static async getGlobalStats() {
    try {
      const client = await pool.connect();
      try {
        // Get overall statistics
        const statsResult = await client.query(`
          SELECT 
            (SELECT COUNT(*) FROM players WHERE is_active = true) as active_players,
            (SELECT COUNT(*) FROM completed_phrases) as total_completions,
            (SELECT AVG(score) FROM completed_phrases) as avg_score,
            (SELECT MAX(score) FROM completed_phrases) as highest_score,
            (SELECT SUM(score) FROM completed_phrases) as total_points_awarded,
            (SELECT COUNT(DISTINCT player_id) FROM completed_phrases) as players_with_completions
        `);

        // Get today's activity
        const todayResult = await client.query(`
          SELECT 
            COUNT(*) as completions_today,
            COUNT(DISTINCT player_id) as active_players_today,
            COALESCE(SUM(score), 0) as points_today
          FROM completed_phrases 
          WHERE DATE(completed_at) = CURRENT_DATE
        `);

        // Get leaderboard sizes
        const leaderboardSizes = await client.query(`
          SELECT 
            score_period,
            COUNT(*) as player_count
          FROM leaderboards 
          WHERE period_start = CASE 
            WHEN score_period = 'daily' THEN CURRENT_DATE
            WHEN score_period = 'weekly' THEN DATE_TRUNC('week', CURRENT_DATE)
            WHEN score_period = 'total' THEN '1970-01-01'
          END
          GROUP BY score_period
        `);

        const stats = statsResult.rows[0];
        const today = todayResult.rows[0];
        const leaderboards = {};
        
        leaderboardSizes.rows.forEach(row => {
          leaderboards[row.score_period] = parseInt(row.player_count);
        });

        return {
          overall: {
            activePlayers: parseInt(stats.active_players),
            totalCompletions: parseInt(stats.total_completions),
            averageScore: parseFloat(stats.avg_score || 0).toFixed(1),
            highestScore: parseInt(stats.highest_score || 0),
            totalPointsAwarded: parseInt(stats.total_points_awarded || 0),
            playersWithCompletions: parseInt(stats.players_with_completions)
          },
          today: {
            completions: parseInt(today.completions_today),
            activePlayers: parseInt(today.active_players_today),
            pointsAwarded: parseInt(today.points_today)
          },
          leaderboards: {
            daily: leaderboards.daily || 0,
            weekly: leaderboards.weekly || 0,
            total: leaderboards.total || 0
          }
        };
      } finally {
        client.release();
      }
    } catch (error) {
      console.error('❌ SCORING: Error getting global stats:', error);
      throw error;
    }
  }

  /**
   * Refresh all leaderboards (for scheduled maintenance)
   */
  static async refreshAllLeaderboards() {
    try {
      const client = await pool.connect();
      try {
        console.log('📊 SCORING: Refreshing all leaderboards...');
        
        // Update rankings for all periods
        const dailyResult = await client.query('SELECT update_leaderboard_rankings($1)', ['daily']);
        const weeklyResult = await client.query('SELECT update_leaderboard_rankings($1)', ['weekly']);
        const totalResult = await client.query('SELECT update_leaderboard_rankings($1)', ['total']);
        
        console.log(`📊 SCORING: Leaderboard refresh complete`);
        console.log(`   - Daily: ${dailyResult.rows[0].update_leaderboard_rankings} players ranked`);
        console.log(`   - Weekly: ${weeklyResult.rows[0].update_leaderboard_rankings} players ranked`);
        console.log(`   - Total: ${totalResult.rows[0].update_leaderboard_rankings} players ranked`);
        
        return {
          success: true,
          dailyUpdated: dailyResult.rows[0].update_leaderboard_rankings,
          weeklyUpdated: weeklyResult.rows[0].update_leaderboard_rankings,
          totalUpdated: totalResult.rows[0].update_leaderboard_rankings
        };
      } finally {
        client.release();
      }
    } catch (error) {
      console.error('❌ SCORING: Error refreshing leaderboards:', error);
      throw error;
    }
  }
}

module.exports = ScoringSystem;