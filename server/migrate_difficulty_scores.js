#!/usr/bin/env node

/**
 * Migration Script: Calculate and Update Difficulty Scores
 * 
 * This script finds all phrases with NULL difficulty_level values
 * and calculates their difficulty scores using the shared algorithm.
 */

const { query, pool } = require('./database/connection');
const { calculateScore } = require('./shared/difficulty-algorithm');

async function migrateDifficultyScores() {
  console.log('🚀 Starting difficulty score migration...');
  
  try {
    // Get all phrases with NULL difficulty_level
    console.log('📋 Finding phrases with NULL difficulty scores...');
    const result = await query(`
      SELECT id, content, language 
      FROM phrases 
      WHERE difficulty_level IS NULL
    `);
    
    const phrasesToUpdate = result.rows;
    console.log(`📊 Found ${phrasesToUpdate.length} phrases to update`);
    
    if (phrasesToUpdate.length === 0) {
      console.log('✅ All phrases already have difficulty scores!');
      return;
    }
    
    let updated = 0;
    let errors = 0;
    
    // Process each phrase
    for (const phrase of phrasesToUpdate) {
      try {
        // Calculate difficulty score using shared algorithm
        const language = phrase.language || 'en';
        const difficultyScore = calculateScore({
          phrase: phrase.content,
          language: language
        });
        
        // Update the database
        await query(`
          UPDATE phrases 
          SET difficulty_level = $1 
          WHERE id = $2
        `, [Math.round(difficultyScore), phrase.id]);
        
        updated++;
        console.log(`✅ Updated "${phrase.content}" → ${Math.round(difficultyScore)} points`);
        
      } catch (error) {
        errors++;
        console.error(`❌ Failed to update "${phrase.content}": ${error.message}`);
      }
    }
    
    console.log('\n📊 Migration Summary:');
    console.log(`   ✅ Successfully updated: ${updated} phrases`);
    console.log(`   ❌ Errors: ${errors} phrases`);
    console.log(`   📝 Total processed: ${phrasesToUpdate.length} phrases`);
    
    // Verify migration
    console.log('\n🔍 Verifying migration...');
    const verifyResult = await query(`
      SELECT COUNT(*) as null_count 
      FROM phrases 
      WHERE difficulty_level IS NULL
    `);
    
    const remainingNulls = parseInt(verifyResult.rows[0].null_count);
    console.log(`📊 Remaining NULL difficulty scores: ${remainingNulls}`);
    
    if (remainingNulls === 0) {
      console.log('🎉 Migration completed successfully! All phrases now have difficulty scores.');
    } else {
      console.log(`⚠️  ${remainingNulls} phrases still have NULL difficulty scores.`);
    }
    
  } catch (error) {
    console.error('❌ Migration failed:', error.message);
    throw error;
  }
}

// Run migration if called directly
if (require.main === module) {
  migrateDifficultyScores()
    .then(() => {
      console.log('✅ Migration script completed');
      process.exit(0);
    })
    .catch((error) => {
      console.error('❌ Migration script failed:', error);
      process.exit(1);
    });
}

module.exports = { migrateDifficultyScores };