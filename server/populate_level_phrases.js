#!/usr/bin/env node

/**
 * Phrase Population Script: Clean duplicates and generate level-appropriate phrases
 * 
 * This script:
 * 1. Removes duplicate phrases (like multiple "hello world"s)
 * 2. Generates phrases targeted for specific difficulty levels
 * 3. Ensures 50+ phrases available for each level
 */

const { query, pool } = require('./database/connection');
const { calculateScore } = require('./shared/difficulty-algorithm');

// Level-appropriate phrase templates by difficulty target
const PHRASE_TEMPLATES = {
  // Level 1: ≤50 difficulty (simple 2-word phrases)
  level1: [
    'cat dog', 'red car', 'big tree', 'hot sun', 'cold ice',
    'fast run', 'slow walk', 'good day', 'bad news', 'new book',
    'old car', 'nice view', 'dark room', 'light ray', 'soft bed',
    'hard rock', 'sweet cake', 'sour milk', 'fresh air', 'clean water',
    'dirty hands', 'blue sky', 'green grass', 'yellow sun', 'white snow',
    'black cat', 'brown dog', 'pink rose', 'purple flower', 'orange fruit',
    'small house', 'big door', 'long road', 'short path', 'wide river',
    'deep lake', 'high hill', 'low valley', 'thick book', 'thin paper',
    'heavy box', 'light feather', 'strong man', 'weak link', 'young child',
    'old tree', 'new shoes', 'warm coat', 'cool breeze', 'dry land',
    'wet grass', 'bright star', 'dark night', 'quiet room', 'loud noise',
    'smooth stone', 'rough edge', 'sharp knife', 'dull blade', 'open door',
    'closed book', 'empty cup', 'full glass', 'broken toy', 'fixed bike'
  ],
  
  // Level 2: 51-100 difficulty (3-word phrases, slightly complex)
  level2: [
    'happy birthday party', 'sunny summer day', 'cold winter night', 'fresh morning air',
    'beautiful garden flowers', 'delicious home cooking', 'comfortable reading chair', 'exciting adventure story',
    'peaceful mountain view', 'busy city street', 'quiet library corner', 'colorful art gallery',
    'friendly neighborhood dog', 'mysterious old house', 'sparkling ocean waves', 'gentle evening breeze',
    'cozy fireplace warmth', 'refreshing ice cream', 'challenging puzzle game', 'relaxing beach vacation',
    'amazing magic trick', 'wonderful family dinner', 'creative writing project', 'inspiring music concert',
    'interesting history lesson', 'fantastic movie night', 'delightful picnic lunch', 'thrilling roller coaster',
    'enchanting fairy tale', 'brilliant science experiment', 'joyful celebration dance', 'thoughtful birthday gift',
    'magnificent sunset view', 'adorable baby animals', 'spectacular fireworks display', 'charming small town',
    'elegant dinner party', 'adventurous hiking trail', 'memorable school trip', 'hilarious comedy show',
    'impressive art exhibition', 'delicious chocolate cake', 'comfortable winter clothes', 'exciting treasure hunt',
    'beautiful flower arrangement', 'relaxing spa treatment', 'challenging math problem', 'inspiring book club',
    'amazing technology demo', 'wonderful nature walk', 'creative cooking class', 'fantastic sports game',
    'delightful surprise party', 'peaceful yoga session', 'exciting road trip', 'charming coffee shop'
  ],
  
  // Additional simple phrases for variety
  simple2word: [
    'jump high', 'swim fast', 'sing loud', 'dance well', 'cook food',
    'read books', 'write notes', 'play games', 'watch movies', 'listen music',
    'walk slowly', 'run quickly', 'talk softly', 'laugh hard', 'smile bright',
    'work late', 'sleep early', 'wake up', 'sit down', 'stand tall',
    'think deep', 'dream big', 'hope much', 'love truly', 'care deeply'
  ]
};

async function removeDuplicatePhrases() {
  console.log('🧹 Removing duplicate phrases...');
  
  try {
    // Find duplicates
    const duplicatesResult = await query(`
      SELECT content, array_agg(id) as ids, COUNT(*) as count
      FROM phrases 
      WHERE is_global = true AND is_approved = true
      GROUP BY content 
      HAVING COUNT(*) > 1
      ORDER BY COUNT(*) DESC
    `);
    
    const duplicates = duplicatesResult.rows;
    console.log(`📊 Found ${duplicates.length} sets of duplicate phrases`);
    
    let totalRemoved = 0;
    
    for (const duplicate of duplicates) {
      const ids = duplicate.ids;
      const keepId = ids[0]; // Keep the first one
      const removeIds = ids.slice(1); // Remove the rest
      
      console.log(`🗑️  "${duplicate.content}": keeping 1, removing ${removeIds.length} duplicates`);
      
      // Remove duplicates
      for (const id of removeIds) {
        await query('DELETE FROM phrases WHERE id = $1', [id]);
        totalRemoved++;
      }
    }
    
    console.log(`✅ Removed ${totalRemoved} duplicate phrases`);
    return totalRemoved;
  } catch (error) {
    console.error('❌ Error removing duplicates:', error.message);
    throw error;
  }
}

async function generatePhrasesForLevel(level, targetCount = 50) {
  console.log(`\n📝 Generating phrases for level ${level}...`);
  
  const maxDifficulty = level * 50;
  const minDifficulty = (level - 1) * 50 + 1;
  
  // Check current count
  const currentResult = await query(`
    SELECT COUNT(*) as count 
    FROM phrases 
    WHERE is_global = true 
      AND is_approved = true 
      AND difficulty_level >= $1 
      AND difficulty_level <= $2
  `, [level === 1 ? 0 : minDifficulty, maxDifficulty]);
  
  const currentCount = parseInt(currentResult.rows[0].count);
  console.log(`📊 Current count for level ${level}: ${currentCount} phrases`);
  
  if (currentCount >= targetCount) {
    console.log(`✅ Level ${level} already has enough phrases (${currentCount}/${targetCount})`);
    return 0;
  }
  
  const needed = targetCount - currentCount;
  console.log(`🎯 Need to generate ${needed} more phrases for level ${level}`);
  
  // Select appropriate templates
  let templates = [];
  if (level === 1) {
    templates = [...PHRASE_TEMPLATES.level1, ...PHRASE_TEMPLATES.simple2word];
  } else if (level === 2) {
    templates = PHRASE_TEMPLATES.level2;
  } else {
    // For higher levels, create more complex combinations
    templates = PHRASE_TEMPLATES.level2.map(phrase => 
      phrase + ' adventure'
    ).concat(
      PHRASE_TEMPLATES.level2.map(phrase => 
        'amazing ' + phrase
      )
    );
  }
  
  let generated = 0;
  let attempts = 0;
  const maxAttempts = templates.length * 2;
  
  // Shuffle templates for variety
  const shuffledTemplates = templates.sort(() => Math.random() - 0.5);
  
  for (const template of shuffledTemplates) {
    if (generated >= needed || attempts >= maxAttempts) break;
    attempts++;
    
    try {
      // Calculate difficulty
      const difficulty = calculateScore({ phrase: template, language: 'en' });
      const roundedDifficulty = Math.round(difficulty);
      
      // Check if it fits the level
      const fitsLevel = level === 1 ? 
        roundedDifficulty <= maxDifficulty :
        roundedDifficulty >= minDifficulty && roundedDifficulty <= maxDifficulty;
      
      if (!fitsLevel) {
        console.log(`⚠️  Skipping "${template}" (difficulty ${roundedDifficulty}, target: ${minDifficulty}-${maxDifficulty})`);
        continue;
      }
      
      // Check if it already exists
      const existsResult = await query(`
        SELECT COUNT(*) as count 
        FROM phrases 
        WHERE LOWER(content) = LOWER($1)
      `, [template]);
      
      if (parseInt(existsResult.rows[0].count) > 0) {
        console.log(`⚠️  Skipping "${template}" (already exists)`);
        continue;
      }
      
      // Generate appropriate hint
      const words = template.split(' ');
      const hint = words.length === 2 ? 
        `Unscramble these ${words.length} words` :
        `A ${words.length}-word phrase about ${words[0]} and ${words[words.length-1]}`;
      
      // Insert phrase using API format
      const insertResult = await query(`
        INSERT INTO phrases (content, hint, difficulty_level, is_global, is_approved, created_by_player_id, phrase_type, language)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING id, content, difficulty_level
      `, [template, hint, roundedDifficulty, true, true, null, 'global', 'en']);
      
      const newPhrase = insertResult.rows[0];
      console.log(`✅ Added "${newPhrase.content}" (difficulty: ${newPhrase.difficulty_level})`);
      generated++;
      
    } catch (error) {
      console.log(`❌ Failed to add "${template}": ${error.message}`);
    }
  }
  
  console.log(`📊 Generated ${generated} new phrases for level ${level}`);
  return generated;
}

async function populateLevelPhrases() {
  console.log('🚀 Starting phrase population for level-based system...');
  
  try {
    // Step 1: Remove duplicates
    const duplicatesRemoved = await removeDuplicatePhrases();
    
    // Step 2: Generate phrases for each level
    const results = {};
    for (let level = 1; level <= 3; level++) {
      results[`level${level}`] = await generatePhrasesForLevel(level, 50);
    }
    
    // Step 3: Final summary
    console.log('\n📊 Final Summary:');
    console.log(`   🗑️  Duplicates removed: ${duplicatesRemoved}`);
    
    for (let level = 1; level <= 3; level++) {
      const maxDifficulty = level * 50;
      const minDifficulty = level === 1 ? 0 : (level - 1) * 50 + 1;
      
      const finalResult = await query(`
        SELECT COUNT(*) as count 
        FROM phrases 
        WHERE is_global = true 
          AND is_approved = true 
          AND difficulty_level >= $1 
          AND difficulty_level <= $2
      `, [minDifficulty, maxDifficulty]);
      
      const finalCount = parseInt(finalResult.rows[0].count);
      console.log(`   📝 Level ${level} (${minDifficulty}-${maxDifficulty}): ${finalCount} phrases (${results[`level${level}`]} new)`);
    }
    
    console.log('\n🎉 Phrase population completed successfully!');
    
  } catch (error) {
    console.error('❌ Phrase population failed:', error.message);
    throw error;
  }
}

// Run population if called directly
if (require.main === module) {
  populateLevelPhrases()
    .then(() => {
      console.log('✅ Population script completed');
      process.exit(0);
    })
    .catch((error) => {
      console.error('❌ Population script failed:', error);
      process.exit(1);
    });
}

module.exports = { populateLevelPhrases, removeDuplicatePhrases, generatePhrasesForLevel };