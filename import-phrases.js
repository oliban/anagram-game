#!/usr/bin/env node

/**
 * Import phrases from analyzed JSON files into microservices database
 * Works with Docker Compose PostgreSQL setup
 */

const fs = require('fs');
const { Client } = require('pg');

// Detect environment and set database host accordingly
// In Docker containers, use service name; locally use localhost
const isDocker = process.env.DOCKER_ENV === 'true' || fs.existsSync('/.dockerenv');
const dbHost = process.env.DB_HOST || (isDocker ? 'postgres' : 'localhost');

// Database connection for microservices
const client = new Client({
  host: dbHost,
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'anagram_game',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres'
});

async function importPhrases(filePath, limit = 50) {
  try {
    console.log(`📁 Reading phrases from: ${filePath}`);
    console.log(`🔌 Connecting to database at: ${dbHost}`);
    const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    
    if (!data.phrases || !Array.isArray(data.phrases)) {
      throw new Error('Invalid file format - missing phrases array');
    }

    await client.connect();
    console.log('🔗 Connected to database');

    // First, get all existing phrases in one query for efficiency
    const existingPhrasesResult = await client.query('SELECT content FROM phrases');
    const existingPhrases = new Set(existingPhrasesResult.rows.map(row => row.content));
    
    // Prepare batch data
    const phrasesToImport = [];
    let skipped = 0;
    
    for (const phraseData of data.phrases.slice(0, limit)) {
      // Handle different field names in JSON
      const phraseContent = phraseData.text || phraseData.original || phraseData.phrase;
      const phraseHint = phraseData.hint || phraseData.clue || phraseContent.split(' ').slice(0, 3).join(' ') + '...';
      const phraseDifficulty = phraseData.difficulty || 1;
      const phraseLanguage = phraseData.language || data.metadata?.language || 'sv';
      const phraseTheme = (phraseData.theme_tags && phraseData.theme_tags[0]) || phraseData.category || 'general';
      
      // Check if phrase already exists
      if (existingPhrases.has(phraseContent)) {
        skipped++;
        continue;
      }
      
      phrasesToImport.push({
        content: phraseContent,
        hint: phraseHint,
        difficulty: phraseDifficulty,
        language: phraseLanguage,
        theme: phraseTheme
      });
    }
    
    let imported = 0;
    
    if (phrasesToImport.length > 0) {
      // Build a single INSERT query for all phrases
      const values = [];
      const placeholders = [];
      let paramIndex = 1;
      
      for (const phrase of phrasesToImport) {
        placeholders.push(
          `($${paramIndex}, $${paramIndex+1}, $${paramIndex+2}, $${paramIndex+3}, $${paramIndex+4}, $${paramIndex+5}, $${paramIndex+6}, $${paramIndex+7}, $${paramIndex+8})`
        );
        values.push(
          phrase.content,
          phrase.hint,
          phrase.difficulty,
          true,  // is_global
          true,  // is_approved
          phrase.language,
          'generated',  // phrase_type
          phrase.theme,
          'import'  // source
        );
        paramIndex += 9;
      }
      
      const batchInsertQuery = `
        INSERT INTO phrases (content, hint, difficulty_level, is_global, is_approved, language, phrase_type, theme, source)
        VALUES ${placeholders.join(', ')}
      `;
      
      try {
        const result = await client.query(batchInsertQuery, values);
        imported = result.rowCount;
        console.log(`✅ Batch imported ${imported} phrases in a single query`);
      } catch (error) {
        console.error(`⚠️  Batch insert failed, trying individual inserts...`);
        // Fall back to individual inserts if batch fails
        // This ensures we import as many phrases as possible
        for (const phrase of phrasesToImport) {
          try {
            await client.query(`
              INSERT INTO phrases (content, hint, difficulty_level, is_global, is_approved, language, phrase_type, theme, source)
              VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            `, [
              phrase.content,
              phrase.hint,
              phrase.difficulty,
              true,  // is_global
              true,  // is_approved
              phrase.language,
              'generated',
              phrase.theme,
              'import'
            ]);
            imported++;
            console.log(`  ✓ Imported: "${phrase.content}"`);
          } catch (err) {
            console.log(`  ✗ Skipped: "${phrase.content}" - ${err.message}`);
          }
        }
        console.log(`✅ Individual imports complete: ${imported}/${phrasesToImport.length} succeeded`);
      }
    }

    console.log(`\n📊 Import Summary:`);
    console.log(`   ✅ Imported: ${imported} phrases`);
    console.log(`   ⏭️  Skipped: ${skipped} phrases`);
    console.log(`   📝 Total processed: ${imported + skipped} phrases`);

  } catch (error) {
    console.error('💥 Import failed:', error.message);
  } finally {
    await client.end();
  }
}

// Get file path from command line arguments
const filePath = process.argv[2];
const limit = parseInt(process.argv[3]) || 50;

if (!filePath) {
  console.error('Usage: node import-phrases.js <path-to-analyzed-file.json> [limit]');
  process.exit(1);
}

importPhrases(filePath, limit);