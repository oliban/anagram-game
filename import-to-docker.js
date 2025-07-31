#!/usr/bin/env node

/**
 * Import phrases specifically to Docker database
 * Ensures we're using the correct Docker database connection
 */

const fs = require('fs');
const { Client } = require('pg');

// Docker database connection
const client = new Client({
  host: 'localhost',
  port: 5432,
  database: 'anagram_game',
  user: 'postgres',
  password: 'postgres',
  connectionTimeoutMillis: 10000,
});

async function importPhrasesToDocker(filePath, limit = 1000) {
  try {
    console.log(`📁 Reading phrases from: ${filePath}`);
    const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    
    if (!data.phrases || !Array.isArray(data.phrases)) {
      throw new Error('Invalid file format - missing phrases array');
    }

    await client.connect();
    console.log('🐳 Connected to Docker database');

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
          console.log(`⏭️  Skipped duplicate: "${phraseData.phrase}"`);
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
          phraseData.language || 'sv',
          'global'
        ]);

        imported++;
        console.log(`✅ Imported: "${phraseData.phrase}" (difficulty: ${phraseData.difficulty})`);
      } catch (error) {
        console.error(`❌ Failed to import "${phraseData.phrase}":`, error.message);
        skipped++;
      }
    }

    console.log(`\n🐳 Docker Database Import Summary:`);
    console.log(`   ✅ Imported: ${imported} phrases`);
    console.log(`   ⏭️  Skipped: ${skipped} phrases`);
    console.log(`   📝 Total processed: ${imported + skipped} phrases`);

    // Check final counts
    const finalCount = await client.query('SELECT COUNT(*) FROM phrases');
    const swedishCount = await client.query("SELECT COUNT(*) FROM phrases WHERE language = 'sv'");
    
    console.log(`\n📊 Final Docker Database Stats:`);
    console.log(`   Total phrases: ${finalCount.rows[0].count}`);
    console.log(`   Swedish phrases: ${swedishCount.rows[0].count}`);

  } catch (error) {
    console.error('💥 Docker import failed:', error.message);
  } finally {
    await client.end();
  }
}

// Get file path from command line arguments
const filePath = process.argv[2];
const limit = parseInt(process.argv[3]) || 1000;

if (!filePath) {
  console.error('Usage: node import-to-docker.js <path-to-analyzed-file.json> [limit]');
  process.exit(1);
}

importPhrasesToDocker(filePath, limit);