#!/usr/bin/env node

/**
 * Import phrases from analyzed JSON files into microservices database
 * Works with Docker Compose PostgreSQL setup
 */

const fs = require('fs');
const { Client } = require('pg');

// Database connection for microservices
const client = new Client({
  host: 'localhost',
  port: 5432,
  database: 'anagram_game',
  user: 'postgres',
  password: 'postgres'
});

async function importPhrases(filePath, limit = 50) {
  try {
    console.log(`📁 Reading phrases from: ${filePath}`);
    const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    
    if (!data.phrases || !Array.isArray(data.phrases)) {
      throw new Error('Invalid file format - missing phrases array');
    }

    await client.connect();
    console.log('🔗 Connected to database');

    let imported = 0;
    let skipped = 0;

    for (const phraseData of data.phrases.slice(0, limit)) {
      try {
        // Check if phrase already exists
        const existsResult = await client.query(
          'SELECT id FROM phrases WHERE content = $1',
          [phraseData.phrase]
        );

        if (existsResult.rows.length > 0) {
          skipped++;
          continue;
        }

        // Insert as global approved phrase
        await client.query(`
          INSERT INTO phrases (content, hint, difficulty_level, is_global, is_approved, language, phrase_type)
          VALUES ($1, $2, $3, $4, $5, $6, $7)
        `, [
          phraseData.phrase,
          phraseData.clue,
          phraseData.difficulty,
          true,  // is_global
          true,  // is_approved
          phraseData.language || 'en',
          'global'
        ]);

        imported++;
        console.log(`✅ Imported: "${phraseData.phrase}" (difficulty: ${phraseData.difficulty})`);
      } catch (error) {
        console.error(`❌ Failed to import "${phraseData.phrase}":`, error.message);
        skipped++;
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