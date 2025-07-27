#!/usr/bin/env node

/**
 * Re-scoring Script: Calculate and Update ALL Phrase Difficulty Scores
 * 
 * This script re-calculates difficulty scores for ALL phrases in the database
 * using the current shared algorithm, ensuring consistency between server-stored
 * scores and the latest scoring logic.
 */

const { query, pool } = require('./database/connection');
const { calculateScore } = require('./shared/difficulty-algorithm');

async function rescoreAllPhrases() {
  console.log('🚀 Starting complete phrase re-scoring...');
  
  try {
    // Get ALL phrases regardless of current difficulty_level
    console.log('📋 Loading all phrases from database...');
    const result = await query(`
      SELECT id, content, language, difficulty_level as current_score
      FROM phrases 
      ORDER BY created_at ASC
    `);
    
    const allPhrases = result.rows;
    console.log(`📊 Found ${allPhrases.length} total phrases to re-score`);
    
    if (allPhrases.length === 0) {
      console.log('❌ No phrases found in database!');
      return;
    }
    
    let updated = 0;
    let unchanged = 0;
    let errors = 0;
    const changes = [];
    
    console.log('\n🔄 Processing phrases...\n');
    
    // Process each phrase
    for (const phrase of allPhrases) {
      try {
        // Calculate new difficulty score using current algorithm
        const language = phrase.language || 'en';
        const newScore = calculateScore({
          phrase: phrase.content,
          language: language
        });
        
        const roundedNewScore = Math.round(newScore);
        const currentScore = phrase.current_score;
        
        // Update the database with new score
        await query(`
          UPDATE phrases 
          SET difficulty_level = $1 
          WHERE id = $2
        `, [roundedNewScore, phrase.id]);
        
        if (currentScore !== roundedNewScore) {
          changes.push({
            content: phrase.content,
            oldScore: currentScore,
            newScore: roundedNewScore,
            change: roundedNewScore - (currentScore || 0)
          });
          updated++;
          console.log(`📊 "${phrase.content}" → ${currentScore || 'NULL'} to ${roundedNewScore} (${roundedNewScore - (currentScore || 0) > 0 ? '+' : ''}${roundedNewScore - (currentScore || 0)})`);
        } else {
          unchanged++;
          console.log(`✅ "${phrase.content}" → ${roundedNewScore} (unchanged)`);
        }
        
      } catch (error) {
        errors++;
        console.error(`❌ Failed to re-score "${phrase.content}": ${error.message}`);
      }
    }
    
    console.log('\n📊 Re-scoring Summary:');
    console.log(`   🔄 Total phrases processed: ${allPhrases.length}`);
    console.log(`   📈 Updated with new scores: ${updated}`);
    console.log(`   ✅ Unchanged (same score): ${unchanged}`);
    console.log(`   ❌ Errors: ${errors}`);
    
    // Show significant changes
    if (changes.length > 0) {
      console.log('\n📋 Significant Changes:');
      const significantChanges = changes
        .filter(c => Math.abs(c.change) >= 10)
        .sort((a, b) => Math.abs(b.change) - Math.abs(a.change))
        .slice(0, 10);
      
      if (significantChanges.length > 0) {
        console.log('   📊 Top 10 largest changes:');
        significantChanges.forEach(c => {
          console.log(`     "${c.content}": ${c.oldScore || 'NULL'} → ${c.newScore} (${c.change > 0 ? '+' : ''}${c.change})`);
        });
      } else {
        console.log('   ✅ No changes ≥10 points detected');
      }
    }
    
    // Verify final state
    console.log('\n🔍 Verifying final state...');
    const verifyResult = await query(`
      SELECT 
        COUNT(*) as total_phrases,
        COUNT(*) FILTER (WHERE difficulty_level IS NULL) as null_scores,
        MIN(difficulty_level) as min_score,
        MAX(difficulty_level) as max_score,
        AVG(difficulty_level) as avg_score
      FROM phrases
    `);
    
    const stats = verifyResult.rows[0];
    console.log(`📊 Database state after re-scoring:`);
    console.log(`   📝 Total phrases: ${stats.total_phrases}`);
    console.log(`   ❌ NULL scores remaining: ${stats.null_scores || 0}`);
    console.log(`   📊 Score range: ${Math.round(stats.min_score)} - ${Math.round(stats.max_score)}`);
    console.log(`   📈 Average score: ${Math.round(stats.avg_score)}`);
    
    if (parseInt(stats.null_scores) === 0) {
      console.log('\n🎉 Re-scoring completed successfully! All phrases now have current difficulty scores.');
    } else {
      console.log(`\n⚠️  ${stats.null_scores} phrases still have NULL difficulty scores.`);
    }
    
  } catch (error) {
    console.error('❌ Re-scoring failed:', error.message);
    throw error;
  }
}

// Run re-scoring if called directly
if (require.main === module) {
  rescoreAllPhrases()
    .then(() => {
      console.log('✅ Re-scoring script completed');
      process.exit(0);
    })
    .catch((error) => {
      console.error('❌ Re-scoring script failed:', error);
      process.exit(1);
    });
}

module.exports = { rescoreAllPhrases };