#!/usr/bin/env node

/**
 * Phrase Importer Script - Direct Database Access
 * 
 * Imports analyzed phrases directly into the database.
 * Replaces admin API endpoints with secure direct database operations.
 * Handles duplicates, validation, and batch processing.
 * Provides dry-run mode for testing imports.
 * 
 * SECURITY: Uses direct database access instead of HTTP API endpoints.
 */

const fs = require('fs');
const path = require('path');
const { glob } = require('glob');
const { query, pool } = require('../database/connection');

// Import DatabasePhrase for direct database operations (replacing API calls)
const DatabasePhrase = require('../../services/shared/database/models/DatabasePhrase');

// Import difficulty algorithm for score calculation
const { calculateScore } = require('../../services/shared/difficulty-algorithm');

// Configuration
const CONFIG = {
  batchSize: 50,
  duplicateCheck: true,
  validateSchema: true,
  outputDir: path.join(__dirname, '../data'),
  importedDir: path.join(__dirname, '../data/imported')
};

/**
 * Expand glob patterns to get list of files
 */
function expandFilePatterns(inputPattern) {
  try {
    // Check if it's a glob pattern or a simple file path
    if (inputPattern.includes('*') || inputPattern.includes('?') || inputPattern.includes('[')) {
      // Use glob to expand the pattern
      const files = glob.sync(inputPattern, { absolute: false });
      return files.length > 0 ? files : [inputPattern]; // Return original pattern if no matches
    } else {
      // Single file
      return [inputPattern];
    }
  } catch (error) {
    console.warn(`⚠️ Error expanding file pattern: ${error.message}`);
    return [inputPattern]; // Return original pattern on error
  }
}

/**
 * Move imported file to imported directory
 */
function moveImportedFile(filePath, dryRun = false) {
  try {
    // Ensure imported directory exists
    fs.mkdirSync(CONFIG.importedDir, { recursive: true });
    
    const fileName = path.basename(filePath);
    const destinationPath = path.join(CONFIG.importedDir, fileName);
    
    if (dryRun) {
      console.log(`📁 Would move: ${filePath} → ${destinationPath}`);
      return destinationPath;
    }
    
    // Move the file
    fs.renameSync(filePath, destinationPath);
    console.log(`📁 Moved imported file: ${fileName} → imported/`);
    return destinationPath;
    
  } catch (error) {
    console.warn(`⚠️ Failed to move imported file: ${error.message}`);
    return filePath; // Return original path if move fails
  }
}

/**
 * Validate phrase data against database schema
 */
function validatePhraseData(phrase) {
  const errors = [];
  
  // Required fields
  if (!phrase.phrase || typeof phrase.phrase !== 'string') {
    errors.push('Missing or invalid phrase content');
  }
  
  if (!phrase.clue || typeof phrase.clue !== 'string') {
    errors.push('Missing or invalid clue');
  }
  
  // Note: difficulty will be calculated using the shared algorithm, not accepted from input
  
  // Optional field validation
  if (phrase.language && typeof phrase.language !== 'string') {
    errors.push('Invalid language code');
  }
  
  // Content validation
  if (phrase.phrase) {
    if (phrase.phrase.length > 500) {
      errors.push('Phrase too long (max 500 characters)');
    }
    
    if (phrase.phrase.trim().length === 0) {
      errors.push('Phrase cannot be empty');
    }
    
    const words = phrase.phrase.trim().split(/\s+/);
    if (words.length < 1) {
      errors.push('Phrase must contain at least one word');
    }
    
    if (words.length > 20) {
      errors.push('Phrase too complex (max 20 words)');
    }
  }
  
  if (phrase.clue && phrase.clue.length > 200) {
    errors.push('Clue too long (max 200 characters)');
  }
  
  return errors;
}

/**
 * Check if phrase already exists in database
 */
async function checkPhraseExists(phrase) {
  try {
    const result = await query(`
      SELECT id, content, difficulty_level 
      FROM phrases 
      WHERE LOWER(TRIM(content)) = LOWER(TRIM($1))
      LIMIT 1
    `, [phrase.phrase]);
    
    return result.rows.length > 0 ? result.rows[0] : null;
  } catch (error) {
    console.warn(`⚠️ Error checking phrase existence: ${error.message}`);
    return null;
  }
}

/**
 * Check multiple phrases for duplicates in a single query
 */
async function checkPhrasesExistBatch(phrases) {
  if (phrases.length === 0) return new Map();
  
  try {
    const contents = phrases.map(p => p.phrase.trim().toLowerCase());
    const placeholders = contents.map((_, i) => `$${i + 1}`).join(',');
    
    const result = await query(`
      SELECT id, LOWER(TRIM(content)) as content_key
      FROM phrases 
      WHERE LOWER(TRIM(content)) IN (${placeholders})
    `, contents);
    
    // Create a map of content -> existing record
    const existingMap = new Map();
    result.rows.forEach(row => {
      existingMap.set(row.content_key, { id: row.id });
    });
    
    return existingMap;
  } catch (error) {
    console.warn(`⚠️ Error checking phrases existence: ${error.message}`);
    return new Map();
  }
}

/**
 * Insert single phrase into database
 */
async function insertPhrase(phrase, dryRun = false, apiUrl = CONFIG.apiUrl) {
  const validation = validatePhraseData(phrase);
  if (validation.length > 0) {
    return {
      success: false,
      error: `Validation failed: ${validation.join(', ')}`,
      phrase: phrase.phrase
    };
  }
  
  // Check for duplicates if enabled
  if (CONFIG.duplicateCheck) {
    const existing = await checkPhraseExists(phrase);
    if (existing) {
      return {
        success: false,
        error: `Duplicate phrase (existing ID: ${existing.id})`,
        phrase: phrase.phrase,
        isDuplicate: true
      };
    }
  }
  
  if (dryRun) {
    return {
      success: true,
      phrase: phrase.phrase,
      action: 'would_insert',
      dryRun: true
    };
  }
  
  try {
    // Calculate difficulty using the shared algorithm - NEVER accept pre-calculated scores
    const calculatedDifficulty = calculateScore({
      phrase: phrase.phrase,
      language: phrase.language || 'en'
    });
    
    console.log(`📊 CALCULATED DIFFICULTY: "${phrase.phrase}" (${phrase.language || 'en'}) -> ${calculatedDifficulty}`);
    
    const result = await query(`
      INSERT INTO phrases (
        content, 
        hint, 
        difficulty_level, 
        is_global, 
        is_approved, 
        created_by_player_id, 
        phrase_type, 
        language
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      RETURNING id, content, difficulty_level
    `, [
      phrase.phrase,
      phrase.clue,
      calculatedDifficulty, // Use calculated difficulty, NOT input difficulty
      true, // is_global
      true, // is_approved
      null, // created_by_player_id (system generated)
      'global', // phrase_type
      phrase.language || 'en'
    ]);
    
    const newPhrase = result.rows[0];
    return {
      success: true,
      phrase: phrase.phrase,
      id: newPhrase.id,
      difficulty: newPhrase.difficulty_level,
      action: 'inserted'
    };
    
  } catch (error) {
    return {
      success: false,
      error: `Database error: ${error.message}`,
      phrase: phrase.phrase
    };
  }
}

/**
 * Insert batch of phrases in a single query for better performance
 * Uses VALUES clause to insert multiple rows at once
 */
async function insertPhrasesBatch(phrases, dryRun = false) {
  if (phrases.length === 0) {
    return [];
  }

  const results = [];
  
  if (dryRun) {
    // For dry run, do basic validation but skip all database operations
    const results = [];
    for (const phrase of phrases) {
      const validation = validatePhraseData(phrase);
      if (validation.length > 0) {
        results.push({
          success: false,
          error: `Validation failed: ${validation.join(', ')}`,
          phrase: phrase.phrase
        });
      } else {
        results.push({
          success: true,
          phrase: phrase.phrase,
          action: 'would_insert_via_batch',
          dryRun: true
        });
      }
    }
    return results;
  }

  try {
    // Validate all phrases first (fast, in-memory)
    const validatedPhrases = [];
    for (const phrase of phrases) {
      const validation = validatePhraseData(phrase);
      if (validation.length > 0) {
        results.push({
          success: false,
          error: `Validation failed: ${validation.join(', ')}`,
          phrase: phrase.phrase
        });
        continue;
      }
      validatedPhrases.push(phrase);
    }
    
    // Check for duplicates in a single batch query (fast!)
    let finalPhrases = validatedPhrases;
    if (CONFIG.duplicateCheck && validatedPhrases.length > 0) {
      const existingMap = await checkPhrasesExistBatch(validatedPhrases);
      finalPhrases = [];
      
      for (const phrase of validatedPhrases) {
        const contentKey = phrase.phrase.trim().toLowerCase();
        if (existingMap.has(contentKey)) {
          results.push({
            success: false,
            error: `Duplicate phrase (existing ID: ${existingMap.get(contentKey).id})`,
            phrase: phrase.phrase,
            isDuplicate: true
          });
        } else {
          finalPhrases.push(phrase);
        }
      }
    }
    
    if (finalPhrases.length === 0) {
      return results;
    }
    
    // Build VALUES clause for batch insert
    const values = [];
    const params = [];
    let paramIndex = 1;
    
    finalPhrases.forEach(phrase => {
      values.push(`($${paramIndex}, $${paramIndex + 1}, $${paramIndex + 2}, $${paramIndex + 3}, $${paramIndex + 4}, $${paramIndex + 5}, $${paramIndex + 6}, $${paramIndex + 7}, $${paramIndex + 8})`);
      
      // Calculate difficulty using shared algorithm - NEVER accept pre-calculated scores
      const calculatedDifficulty = calculateScore({
        phrase: phrase.phrase,
        language: phrase.language || 'en'
      });
      
      console.log(`📊 BATCH CALCULATED: "${phrase.phrase}" (${phrase.language || 'en'}) -> ${calculatedDifficulty}`);
      
      params.push(
        phrase.phrase.trim(),                    // content
        phrase.clue?.trim() || '',              // hint
        calculatedDifficulty,                   // Use calculated difficulty, NOT input
        true,                                   // is_global
        true,                                   // is_approved
        null,                                   // created_by_player_id (system generated)
        'community',                            // phrase_type
        phrase.language || 'en',               // language
        phrase.theme || null                   // theme
      );
      
      paramIndex += 9;
    });
    
    const batchQuery = `
      INSERT INTO phrases (content, hint, difficulty_level, is_global, is_approved, created_by_player_id, phrase_type, language, theme)
      VALUES ${values.join(', ')}
      RETURNING id, content, difficulty_level
    `;
    
    console.log(`📥 BATCH INSERT: Inserting ${finalPhrases.length} phrases in single query...`);
    const result = await query(batchQuery, params);
    
    // Create success results for all inserted phrases
    result.rows.forEach((row, index) => {
      results.push({
        success: true,
        phrase: finalPhrases[index].phrase,
        id: row.id,
        difficulty: row.difficulty_level,
        action: 'inserted_batch'
      });
    });
    
    console.log(`✅ BATCH INSERT: Successfully inserted ${result.rows.length} phrases`);
    return results;
    
  } catch (error) {
    console.error(`❌ BATCH INSERT ERROR: ${error.message}`);
    // If batch insert fails, fall back to individual inserts for error reporting
    return phrases.map(phrase => ({
      success: false,
      error: `Batch insert failed: ${error.message}`,
      phrase: phrase.phrase
    }));
  }
}

/**
 * Insert single phrase via direct database access (replacing API calls)
 * Uses the same logic as admin API but without network overhead
 */
async function insertPhraseDirectly(phrase, dryRun = false) {
  const validation = validatePhraseData(phrase);
  if (validation.length > 0) {
    return {
      success: false,
      error: `Validation failed: ${validation.join(', ')}`,
      phrase: phrase.phrase
    };
  }
  
  if (dryRun) {
    return {
      success: true,
      phrase: phrase.phrase,
      action: 'would_insert_via_database',
      dryRun: true
    };
  }
  
  try {
    // Use the exact same creation logic as admin API
    const result = await DatabasePhrase.createEnhancedPhrase({
      content: phrase.phrase.trim(),
      hint: phrase.clue?.trim() || '',
      senderId: null, // System-generated phrases (same as admin API)
      targetIds: [], // No targeting for bulk imports
      isGlobal: true, // Default to global for bulk imports
      phraseType: 'community', // Default to community for bulk imports
      language: phrase.language || 'en',
      theme: phrase.theme || null,
      source: 'app'  // Direct database imports use 'app' source
    });

    const { phrase: createdPhrase, targetCount, isGlobal } = result;

    return {
      success: true,
      phrase: phrase.phrase,
      id: createdPhrase.id,
      difficulty: createdPhrase.difficultyLevel,
      action: 'inserted_via_database',
      isGlobal,
      targetCount
    };
    
  } catch (error) {
    return {
      success: false,
      error: `Database insertion failed: ${error.message}`,
      phrase: phrase.phrase
    };
  }
}

// Admin service health check removed - using direct database access only

/**
 * Check if database is available and ready
 */
async function checkDatabaseHealth() {
  try {
    console.log(`🗄️ Checking database connection...`);
    
    // Test basic connection
    const result = await query('SELECT 1 as test', []);
    if (result.rows.length === 0) {
      throw new Error('Database query returned no results');
    }
    
    // Check if phrases table exists and is accessible
    const tableCheck = await query(`
      SELECT COUNT(*) as total_phrases 
      FROM phrases 
      LIMIT 1
    `, []);
    
    const totalPhrases = parseInt(tableCheck.rows[0].total_phrases);
    console.log(`✅ Database is ready (${totalPhrases} existing phrases)`);
    
    return { 
      available: true, 
      totalPhrases: totalPhrases,
      status: 'ready'
    };
    
  } catch (error) {
    console.log(`❌ Database is not available: ${error.message}`);
    return { 
      available: false, 
      error: error.message,
      suggestion: 'Check if PostgreSQL is running and database exists'
    };
  }
}

/**
 * Import phrases in batches
 */
async function importPhrases(phrases, options = {}) {
  const {
    dryRun = false,
    batchSize = CONFIG.batchSize,
    onProgress = null
  } = options;
  
  // Health check is now done once at the start, not per batch
  
  console.log(`📥 ${dryRun ? 'Simulating' : 'Starting'} import of ${phrases.length} phrases via direct database access...`);
  
  const results = {
    total: phrases.length,
    successful: 0,
    failed: 0,
    duplicates: 0,
    errors: [],
    details: []
  };
  
  // Process in batches
  for (let i = 0; i < phrases.length; i += batchSize) {
    const batch = phrases.slice(i, i + batchSize);
    const batchNum = Math.floor(i / batchSize) + 1;
    const totalBatches = Math.ceil(phrases.length / batchSize);
    
    console.log(`📦 Processing batch ${batchNum}/${totalBatches} (${batch.length} phrases)...`);
    
    // Process entire batch in a single query
    const batchResults = await insertPhrasesBatch(batch, dryRun);
    results.details.push(...batchResults);
    
    // Update counters
    for (const result of batchResults) {
      if (result.success) {
        results.successful++;
      } else {
        results.failed++;
        if (result.isDuplicate) {
          results.duplicates++;
        }
        results.errors.push({
          phrase: result.phrase,
          error: result.error
        });
      }
      
      // Progress callback
      if (onProgress) {
        onProgress(results.successful + results.failed, phrases.length, result);
      }
    }
    
    // Progress update
    const processed = Math.min(i + batchSize, phrases.length);
    console.log(`📊 Progress: ${processed}/${phrases.length} phrases processed`);
  }
  
  return results;
}

/**
 * Display final readable report
 */
function displayFinalReport(report, dryRun = false) {
  console.log(`\n📋 FINAL ${dryRun ? 'SIMULATION' : 'IMPORT'} REPORT`);
  console.log(`════════════════════════════════════════`);
  console.log(`📅 Date: ${new Date(report.import.timestamp).toLocaleString()}`);
  console.log(`📊 Total Processed: ${report.import.total_phrases} phrases`);
  console.log(`✅ Successful: ${report.import.successful}`);
  console.log(`❌ Failed: ${report.import.failed}`);
  console.log(`🔄 Duplicates: ${report.import.duplicates}`);
  console.log(`📈 Success Rate: ${report.import.success_rate}%`);
  
  if (Object.keys(report.difficulty_distribution).length > 0) {
    console.log(`\n🎯 Difficulty Distribution:`);
    Object.entries(report.difficulty_distribution)
      .sort(([a], [b]) => parseInt(a) - parseInt(b))
      .forEach(([range, count]) => {
        console.log(`   ${range}: ${count} phrases`);
      });
  }
  
  if (report.sample_imported.length > 0) {
    console.log(`\n✨ Successfully Imported Phrases:`);
    report.sample_imported.forEach(phrase => {
      const idDisplay = phrase.id ? `ID: ${phrase.id.substring(0, 8)}...` : 'simulation mode';
      console.log(`   • "${phrase.phrase}" (difficulty: ${phrase.difficulty || 'N/A'}, ${idDisplay})`);
    });
  }
  
  if (report.errors && report.errors.length > 0) {
    console.log(`\n❌ Errors Encountered:`);
    report.errors.slice(0, 3).forEach(error => {
      console.log(`   • "${error.phrase}": ${error.error}`);
    });
    if (report.errors.length > 3) {
      console.log(`   ... and ${report.errors.length - 3} more errors`);
    }
  }
  
  console.log(`════════════════════════════════════════`);
}

/**
 * Generate import report
 */
function generateImportReport(results, metadata = {}) {
  const report = {
    import: {
      timestamp: new Date().toISOString(),
      total_phrases: results.total,
      successful: results.successful,
      failed: results.failed,
      duplicates: results.duplicates,
      success_rate: parseFloat(((results.successful / results.total) * 100).toFixed(1))
    },
    metadata: metadata,
    errors: results.errors.slice(0, 20), // Limit error list
    difficulty_distribution: {},
    sample_imported: []
  };
  
  // Calculate difficulty distribution for successful imports
  const successfulDetails = results.details.filter(d => d.success);
  successfulDetails.forEach(detail => {
    if (detail.difficulty) {
      const bucket = Math.floor(detail.difficulty / 10) * 10;
      const key = `${bucket}-${bucket + 9}`;
      report.difficulty_distribution[key] = (report.difficulty_distribution[key] || 0) + 1;
    }
  });
  
  // Add sample of imported phrases
  report.sample_imported = successfulDetails
    .slice(0, 10)
    .map(d => ({ phrase: d.phrase, id: d.id, difficulty: d.difficulty }));
  
  return report;
}

/**
 * Clean duplicate phrases from database
 */
async function cleanDuplicates(dryRun = false) {
  console.log(`🧹 ${dryRun ? 'Simulating' : 'Starting'} duplicate cleanup...`);
  
  try {
    // Find duplicates
    const duplicatesResult = await query(`
      SELECT content, array_agg(id ORDER BY id) as ids, COUNT(*) as count
      FROM phrases 
      WHERE is_global = true 
      GROUP BY LOWER(TRIM(content))
      HAVING COUNT(*) > 1
      ORDER BY COUNT(*) DESC
    `);
    
    const duplicates = duplicatesResult.rows;
    console.log(`📊 Found ${duplicates.length} sets of duplicate phrases`);
    
    let totalRemoved = 0;
    
    if (!dryRun) {
      for (const duplicate of duplicates) {
        const ids = duplicate.ids;
        const keepId = ids[0]; // Keep the first one
        const removeIds = ids.slice(1); // Remove the rest
        
        console.log(`🗑️  "${duplicate.content}": keeping ID ${keepId}, removing ${removeIds.length} duplicates`);
        
        // Remove duplicates
        for (const id of removeIds) {
          await query('DELETE FROM phrases WHERE id = $1', [id]);
          totalRemoved++;
        }
      }
    } else {
      totalRemoved = duplicates.reduce((sum, dup) => sum + (dup.count - 1), 0);
    }
    
    console.log(`✅ ${dryRun ? 'Would remove' : 'Removed'} ${totalRemoved} duplicate phrases`);
    return totalRemoved;
    
  } catch (error) {
    console.error('❌ Error cleaning duplicates:', error.message);
    throw error;
  }
}

/**
 * Verify import success by checking database
 */
async function verifyImportSuccess(expectedCount, report) {
  console.log(`\n🔍 Verifying import success...`);
  
  try {
    // Get database stats before and after
    const currentStats = await getDatabaseStats();
    
    // Check total phrases
    const actualImported = report.import.successful;
    const verificationResults = {
      success: true,
      issues: []
    };
    
    // Verify expected vs actual
    if (actualImported !== expectedCount) {
      verificationResults.success = false;
      verificationResults.issues.push(`Expected ${expectedCount} phrases, but ${actualImported} were imported`);
    }
    
    // Verify database consistency
    if (report.import.success_rate < 100) {
      verificationResults.issues.push(`Import success rate was ${report.import.success_rate}%, some phrases failed`);
    }
    
    if (report.import.failed > 0) {
      verificationResults.issues.push(`${report.import.failed} phrases failed to import`);
    }
    
    // Sample verification - check if some imported phrases exist in database
    if (report.sample_imported.length > 0) {
      const samplePhrase = report.sample_imported[0];
      const checkResult = await query('SELECT id FROM phrases WHERE content = $1 LIMIT 1', [samplePhrase.phrase]);
      
      if (checkResult.rows.length === 0) {
        verificationResults.success = false;
        verificationResults.issues.push(`Sample phrase "${samplePhrase.phrase}" not found in database`);
      }
    }
    
    // Report verification results
    if (verificationResults.success && verificationResults.issues.length === 0) {
      console.log(`✅ Import verification PASSED`);
      console.log(`   ✓ ${actualImported} phrases successfully imported`);
      console.log(`   ✓ Database consistency verified`);
      console.log(`   ✓ Sample phrases found in database`);
      console.log(`   ✓ Current database total: ${currentStats.total} phrases`);
    } else {
      console.log(`❌ Import verification FAILED`);
      verificationResults.issues.forEach(issue => {
        console.log(`   ✗ ${issue}`);
      });
      if (verificationResults.success) console.log(`⚠️  Import succeeded but with warnings`);
    }
    
    return verificationResults;
    
  } catch (error) {
    console.log(`❌ Import verification ERROR: ${error.message}`);
    return { success: false, issues: [`Verification failed: ${error.message}`] };
  }
}

/**
 * Get database statistics
 */
async function getDatabaseStats() {
  try {
    const totalResult = await query(`
      SELECT COUNT(*) as total FROM phrases WHERE is_global = true AND is_approved = true
    `);
    
    const difficultyResult = await query(`
      SELECT 
        CASE 
          WHEN difficulty_level <= 50 THEN '0-50'
          WHEN difficulty_level <= 100 THEN '51-100' 
          WHEN difficulty_level <= 150 THEN '101-150'
          WHEN difficulty_level <= 200 THEN '151-200'
          ELSE '200+'
        END as range,
        COUNT(*) as count,
        AVG(difficulty_level) as avg_difficulty
      FROM phrases 
      WHERE is_global = true AND is_approved = true
      GROUP BY 
        CASE 
          WHEN difficulty_level <= 50 THEN '0-50'
          WHEN difficulty_level <= 100 THEN '51-100'
          WHEN difficulty_level <= 150 THEN '101-150'
          WHEN difficulty_level <= 200 THEN '151-200'
          ELSE '200+'
        END
      ORDER BY range
    `);
    
    return {
      total: parseInt(totalResult.rows[0].total),
      by_difficulty: difficultyResult.rows.map(row => ({
        range: row.range,
        count: parseInt(row.count),
        average_difficulty: parseFloat(parseFloat(row.avg_difficulty).toFixed(1))
      }))
    };
    
  } catch (error) {
    console.error('❌ Error getting database stats:', error.message);
    return null;
  }
}

/**
 * Parse command line arguments
 */
function parseArgs() {
  const args = process.argv.slice(2);
  const parsed = {
    input: null,
    output: null,
    dryRun: false,
    import: false,
    cleanDuplicates: false,
    stats: false,
    batchSize: CONFIG.batchSize,
    help: false
  };
  
  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--input':
        parsed.input = args[++i];
        break;
      case '--output':
        parsed.output = args[++i];
        break;
      case '--dry-run':
        parsed.dryRun = true;
        break;
      case '--import':
        parsed.import = true;
        break;
      case '--clean-duplicates':
        parsed.cleanDuplicates = true;
        break;
      case '--stats':
        parsed.stats = true;
        break;
      case '--batch-size':
        parsed.batchSize = parseInt(args[++i]);
        break;
      // Staging removed - script connects to database based on execution environment
      case '--help':
      case '-h':
        parsed.help = true;
        break;
    }
  }
  
  return parsed;
}

/**
 * Show help information
 */
function showHelp() {
  console.log(`
📥 Phrase Importer Script

Usage:
  node phrase-importer.js [action] [options]

Actions:
  --import               Import phrases from JSON file
  --clean-duplicates     Remove duplicate phrases from database
  --stats               Show database statistics

Options:
  --input FILE          Input JSON file with analyzed phrases (supports glob patterns)
  --output FILE         Output report file (default: auto-generated)
  --dry-run            Simulate import without making changes
  --batch-size SIZE     Number of phrases per batch (default: 50)
  --staging            Import to staging server instead of localhost
  --help, -h           Show this help

Examples:
  node phrase-importer.js --stats
  node phrase-importer.js --input analyzed-phrases.json --dry-run
  node phrase-importer.js --input analyzed-phrases.json --import
  node phrase-importer.js --input "data/2025-08-11*.json" --import
  node phrase-importer.js --input analyzed-phrases.json --import --staging
  node phrase-importer.js --clean-duplicates --dry-run
  node phrase-importer.js --clean-duplicates

Note: All imports use direct database access (secure, no HTTP exposure)
`);
}

/**
 * Main execution function
 */
async function main() {
  const args = parseArgs();
  
  if (args.help) {
    showHelp();
    process.exit(0);
  }
  
  // Show database stats
  if (args.stats) {
    console.log('📊 Database Statistics:');
    const stats = await getDatabaseStats();
    if (stats) {
      console.log(`   Total phrases: ${stats.total}`);
      console.log('   Distribution by difficulty:');
      stats.by_difficulty.forEach(range => {
        console.log(`     ${range.range}: ${range.count} phrases (avg: ${range.average_difficulty})`);
      });
    }
    return;
  }
  
  // Clean duplicates
  if (args.cleanDuplicates) {
    await cleanDuplicates(args.dryRun);
    return;
  }
  
  // Import phrases
  if (args.import || args.dryRun) {
    if (!args.input) {
      console.error('❌ Error: --input parameter is required for import');
      console.error('Use --help for usage information');
      process.exit(1);
    }
    
    // Expand file patterns to get list of files
    const inputFiles = expandFilePatterns(args.input);
    
    // Check if any files exist
    const existingFiles = inputFiles.filter(file => fs.existsSync(file));
    if (existingFiles.length === 0) {
      console.error(`❌ Error: No files found matching "${args.input}"`);
      process.exit(1);
    }
    
    console.log(`🚀 Starting phrase import...`);
    console.log(`   Pattern: ${args.input}`);
    console.log(`   Files found: ${existingFiles.length} (${existingFiles.join(', ')})`);
    console.log(`   Mode: ${args.dryRun ? 'DRY RUN' : 'LIVE IMPORT'}`);
    console.log(`   Method: Direct Database Access`);
    console.log(`   Batch size: ${args.batchSize}`);
    
    // Single health check at the start (not per batch)
    if (!args.dryRun) {
      console.log(`🔍 Checking database health...`);
      const dbHealthCheck = await checkDatabaseHealth();
      if (!dbHealthCheck.available) {
        console.error(`❌ Database is not available: ${dbHealthCheck.error}`);
        console.error(`💡 Suggestion: ${dbHealthCheck.suggestion}`);
        process.exit(1);
      }
      console.log(`✅ Database is ready`);
    }
    
    try {
      // Collect all phrases from all files
      let allPhrases = [];
      let globalTheme = null;
      const processedFiles = [];
      
      for (const inputFile of existingFiles) {
        console.log(`\n📄 Processing file: ${inputFile}`);
        
        try {
          // Load input data
          const inputData = JSON.parse(fs.readFileSync(inputFile, 'utf8'));
          
          let phrases = [];
          let defaultTheme = null;
          
          if (Array.isArray(inputData)) {
            phrases = inputData;
          } else if (inputData.phrases && Array.isArray(inputData.phrases)) {
            phrases = inputData.phrases;
            // Extract theme from metadata if available
            if (inputData.metadata && inputData.metadata.theme) {
              defaultTheme = inputData.metadata.theme;
              console.log(`   📚 Using theme from metadata: ${defaultTheme}`);
              if (!globalTheme) globalTheme = defaultTheme; // Set global theme from first file
            }
          } else {
            console.warn(`   ⚠️ Skipping ${inputFile}: Invalid format. Expected array or object with phrases property.`);
            continue;
          }
          
          // Apply default theme to phrases that don't have one
          if (defaultTheme) {
            phrases = phrases.map(p => ({
              ...p,
              theme: p.theme || defaultTheme,
              _sourceFile: inputFile // Track source file
            }));
          } else {
            phrases = phrases.map(p => ({
              ...p,
              _sourceFile: inputFile // Track source file
            }));
          }
          
          console.log(`   ✅ Loaded ${phrases.length} phrases from ${inputFile}`);
          allPhrases.push(...phrases);
          processedFiles.push(inputFile);
          
        } catch (fileError) {
          console.warn(`   ❌ Error processing ${inputFile}: ${fileError.message}`);
        }
      }
      
      if (allPhrases.length === 0) {
        console.error('❌ No valid phrases found in any files');
        process.exit(1);
      }
      
      console.log(`\n📊 Total phrases collected: ${allPhrases.length} from ${processedFiles.length} files`);
      
      // Filter out phrases that don't meet quality threshold
      // Accept phrases without quality property (from new AI generation system)
      const qualityPhrases = allPhrases.filter(p => 
        !p.quality || p.quality.passesThreshold !== false
      );
      
      if (qualityPhrases.length < allPhrases.length) {
        console.log(`📊 Filtered to ${qualityPhrases.length} high-quality phrases (${allPhrases.length - qualityPhrases.length} excluded)`);
      }
      
      // Import phrases via direct database access
      const results = await importPhrases(qualityPhrases, {
        dryRun: args.dryRun,
        batchSize: args.batchSize
      });
      
      // Generate report
      const report = generateImportReport(results, {
        input_files: processedFiles,
        input_pattern: args.input,
        dry_run: args.dryRun,
        batch_size: args.batchSize,
        original_count: allPhrases.length,
        quality_filtered_count: qualityPhrases.length,
        processed_files_count: processedFiles.length
      });
      
      // Display summary
      console.log(`\n📊 Import ${args.dryRun ? 'Simulation' : 'Results'}:`);
      console.log(`   Total phrases: ${report.import.total_phrases}`);
      console.log(`   Successful: ${report.import.successful}`);
      console.log(`   Failed: ${report.import.failed}`);
      console.log(`   Duplicates: ${report.import.duplicates}`);
      console.log(`   Success rate: ${report.import.success_rate}%`);
      
      if (report.difficulty_distribution && Object.keys(report.difficulty_distribution).length > 0) {
        console.log('   Difficulty distribution:');
        Object.entries(report.difficulty_distribution).sort().forEach(([range, count]) => {
          console.log(`     ${range}: ${count} phrases`);
        });
      }
      
      // Detailed phrase breakdown in table format
      if (results.details && results.details.length > 0) {
        console.log(`\n📝 Import Results Table:`);
        
        // Table format showing all phrases with status
        console.log(`\n┌─────────────────┬─────────────────┬───────┬──────────┬───────────┬─────────────────────┐`);
        console.log(`│ Phrase          │ Clue            │ Score │ Language │ Imported  │ Reason              │`);
        console.log(`├─────────────────┼─────────────────┼───────┼──────────┼───────────┼─────────────────────┤`);
        
        results.details.forEach(detail => {
          // Find the original phrase data to get clue and language
          const originalPhrase = qualityPhrases.find(p => p.phrase === detail.phrase);
          const phrase = (detail.phrase || '').padEnd(15).substring(0, 15);
          const clue = (originalPhrase?.clue || 'No clue').padEnd(15).substring(0, 15);
          const score = String(detail.difficulty || 'N/A').padStart(5);
          const language = (originalPhrase?.language || 'en').padEnd(8).substring(0, 8);
          
          // Status and reason
          let imported, reason;
          if (detail.success && !detail.isDuplicate) {
            imported = '    ✅    ';
            reason = args.dryRun ? 'Simulation mode   ' : 'Successfully added';
          } else if (detail.isDuplicate) {
            imported = '    ❌    ';
            reason = 'Duplicate phrase  ';
          } else {
            imported = '    ❌    ';
            reason = (detail.error || 'Unknown error').padEnd(19).substring(0, 19);
          }
          
          console.log(`│ ${phrase} │ ${clue} │ ${score} │ ${language} │ ${imported} │ ${reason} │`);
        });
        
        console.log(`└─────────────────┴─────────────────┴───────┴──────────┴───────────┴─────────────────────┘`);
        
        // Summary counts
        const successful = results.details.filter(d => d.success && !d.isDuplicate).length;
        const duplicates = results.details.filter(d => d.isDuplicate).length;
        const failed = results.details.filter(d => !d.success && !d.isDuplicate).length;
        
        console.log(`\n📊 Summary: ${successful} imported, ${duplicates} duplicates, ${failed} failed`);
      }
      
      // Show errors if any
      if (results.errors.length > 0) {
        console.log(`\n⚠️  First ${Math.min(5, results.errors.length)} errors:`);
        results.errors.slice(0, 5).forEach(error => {
          console.log(`   "${error.phrase}": ${error.error}`);
        });
      }
      
      // Save report
      if (args.output || !args.dryRun) {
        const outputFile = args.output || path.join(CONFIG.outputDir, `import-report-${Date.now()}.json`);
        fs.mkdirSync(path.dirname(outputFile), { recursive: true });
        fs.writeFileSync(outputFile, JSON.stringify(report, null, 2));
        console.log(`\n📄 Report saved: ${outputFile}`);
      }
      
      // Verify import success (only for live imports)
      if (!args.dryRun && report.import.total_phrases > 0) {
        const verification = await verifyImportSuccess(qualityPhrases.length, report);
        if (!verification.success) {
          console.log(`\n⚠️  Import completed but verification found issues!`);
          process.exit(1);
        }
      }
      
      // Display final readable report
      displayFinalReport(report, args.dryRun);
      
      // Move imported files to imported directory if import was successful
      if (!args.dryRun && report.import.successful > 0) {
        console.log(`\n📁 Moving ${processedFiles.length} imported files...`);
        processedFiles.forEach(file => moveImportedFile(file, false));
      } else if (args.dryRun) {
        // For dry run, just show what would happen
        console.log(`\n📁 Would move ${processedFiles.length} files...`);
        processedFiles.forEach(file => moveImportedFile(file, true));
      }
      
      console.log(`\n✅ Import ${args.dryRun ? 'simulation' : ''} complete!`);
      
    } catch (error) {
      console.error(`❌ Import failed: ${error.message}`);
      process.exit(1);
    }
  } else {
    console.error('❌ Error: No action specified');
    console.error('Use --help for usage information');
    process.exit(1);
  }
}

// Run if called directly
if (require.main === module) {
  main().catch(error => {
    console.error('❌ Unexpected error:', error);
    process.exit(1);
  });
}

module.exports = {
  importPhrases,
  cleanDuplicates,
  getDatabaseStats,
  validatePhraseData
};