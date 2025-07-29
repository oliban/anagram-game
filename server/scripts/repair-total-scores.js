#!/usr/bin/env node

/**
 * Database Repair Script: Recalculate Total Scores
 * 
 * This script fixes the total score inconsistency issue where:
 * - Regular score display shows incorrect totals (e.g., Harry: 57, Assad: 72)
 * - Legends page shows correct totals from daily scores max (e.g., Harry: 495, Assad: 177)
 * 
 * The script will:
 * 1. Recalculate all total scores using the existing stored procedures
 * 2. Update player_scores table with correct total scores
 * 3. Refresh leaderboard rankings
 */

const { pool } = require('../database/connection');

async function repairTotalScores() {
  console.log('🔧 Starting total score repair process...\n');
  
  const client = await pool.connect();
  
  try {
    // Get all players who have completed phrases
    console.log('📋 Finding players with completed phrases...');
    const playersResult = await client.query(`
      SELECT DISTINCT p.id, p.name, COUNT(cp.id) as completed_count
      FROM players p
      JOIN completed_phrases cp ON p.id = cp.player_id
      GROUP BY p.id, p.name
      ORDER BY p.name
    `);
    
    const players = playersResult.rows;
    console.log(`Found ${players.length} players with completed phrases\n`);
    
    // Show current vs expected scores for debugging
    console.log('📊 Current score comparison:');
    console.log('Player Name | Current Total | Expected Total (from max daily) | Phrases Completed');
    console.log('------------|---------------|--------------------------------|------------------');
    
    for (const player of players) {
      // Get current total score from player_scores table
      const currentResult = await client.query(`
        SELECT total_score 
        FROM player_scores 
        WHERE player_id = $1 AND score_period = 'total' AND period_start = '1970-01-01'
      `, [player.id]);
      
      const currentTotal = currentResult.rows.length > 0 ? currentResult.rows[0].total_score : 0;
      
      // Get expected total score from completed_phrases
      const expectedResult = await client.query(`
        SELECT SUM(score) as total_score
        FROM completed_phrases 
        WHERE player_id = $1
      `, [player.id]);
      
      const expectedTotal = expectedResult.rows[0].total_score || 0;
      
      console.log(`${player.name.padEnd(11)} | ${currentTotal.toString().padStart(13)} | ${expectedTotal.toString().padStart(30)} | ${player.completed_count.toString().padStart(16)}`);
    }
    
    console.log('\n🔄 Recalculating scores for all players...\n');
    
    let updatedCount = 0;
    
    for (const player of players) {
      console.log(`⚡ Processing ${player.name}...`);
      
      try {
        // Call the stored procedure to update all score aggregations
        await client.query('SELECT update_player_score_aggregations($1)', [player.id]);
        
        // Get the updated total score
        const updatedResult = await client.query(`
          SELECT total_score, phrases_completed
          FROM player_scores 
          WHERE player_id = $1 AND score_period = 'total' AND period_start = '1970-01-01'
        `, [player.id]);
        
        if (updatedResult.rows.length > 0) {
          const { total_score, phrases_completed } = updatedResult.rows[0];
          console.log(`   ✅ Updated: ${total_score} points, ${phrases_completed} phrases`);
          updatedCount++;
        } else {
          console.log(`   ❌ No total score record found after update`);
        }
      } catch (error) {
        console.log(`   ❌ Error updating ${player.name}:`, error.message);
      }
    }
    
    console.log(`\n📊 Successfully updated ${updatedCount} player records\n`);
    
    // Update leaderboard rankings for all periods
    console.log('🏆 Refreshing leaderboard rankings...');
    
    try {
      const dailyResult = await client.query('SELECT update_leaderboard_rankings($1)', ['daily']);
      const weeklyResult = await client.query('SELECT update_leaderboard_rankings($1)', ['weekly']);
      const totalResult = await client.query('SELECT update_leaderboard_rankings($1)', ['total']);
      
      console.log(`   ✅ Daily leaderboard: ${dailyResult.rows[0].update_leaderboard_rankings} players ranked`);
      console.log(`   ✅ Weekly leaderboard: ${weeklyResult.rows[0].update_leaderboard_rankings} players ranked`);
      console.log(`   ✅ Total leaderboard: ${totalResult.rows[0].update_leaderboard_rankings} players ranked`);
    } catch (error) {
      console.log(`   ❌ Error refreshing leaderboards:`, error.message);
    }
    
    console.log('\n🎉 Total score repair completed successfully!');
    console.log('\nNext steps:');
    console.log('1. Test the application to verify scores display correctly');
    console.log('2. Check that Harry and Assad now see their correct scores in both places');
    console.log('3. Monitor future score updates to ensure they work properly');
    
  } catch (error) {
    console.error('❌ Fatal error during repair process:', error);
    throw error;
  } finally {
    client.release();
  }
}

// Execute the repair if run directly
if (require.main === module) {
  repairTotalScores()
    .then(() => {
      console.log('\n✅ Repair process completed');
      process.exit(0);
    })
    .catch((error) => {
      console.error('\n❌ Repair process failed:', error);
      process.exit(1);
    });
}

module.exports = { repairTotalScores };