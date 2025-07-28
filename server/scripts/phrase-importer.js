#!/usr/bin/env node

/**
 * Phrase Importer Script
 * 
 * Imports analyzed phrases into the database.
 * Handles duplicates, validation, and batch processing.
 * Provides dry-run mode for testing imports.
 */

const fs = require('fs');
const path = require('path');
const { query, pool } = require('../database/connection');

// Configuration
const CONFIG = {
  batchSize: 50,
  duplicateCheck: true,
  validateSchema: true,
  outputDir: path.join(__dirname, '../data')
};

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
  
  if (typeof phrase.difficulty !== 'number' || phrase.difficulty < 1) {
    errors.push('Missing or invalid difficulty score');
  }
  
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
 * Insert single phrase into database
 */
async function insertPhrase(phrase, dryRun = false) {
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
      Math.round(phrase.difficulty),
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
 * Import phrases in batches
 */
async function importPhrases(phrases, options = {}) {
  const {
    dryRun = false,
    batchSize = CONFIG.batchSize,
    onProgress = null
  } = options;
  
  console.log(`📥 ${dryRun ? 'Simulating' : 'Starting'} import of ${phrases.length} phrases...`);
  
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
    
    // Process batch
    for (const phrase of batch) {
      const result = await insertPhrase(phrase, dryRun);
      results.details.push(result);
      
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
        onProgress(i + batch.indexOf(phrase) + 1, phrases.length, result);
      }
    }
    
    // Progress update
    const processed = Math.min(i + batchSize, phrases.length);
    console.log(`📊 Progress: ${processed}/${phrases.length} phrases processed`);
  }
  
  return results;
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
  --input FILE          Input JSON file with analyzed phrases
  --output FILE         Output report file (default: auto-generated)
  --dry-run            Simulate import without making changes
  --batch-size SIZE     Number of phrases per batch (default: 50)
  --help, -h           Show this help

Examples:
  node phrase-importer.js --stats
  node phrase-importer.js --input analyzed-phrases.json --dry-run
  node phrase-importer.js --input analyzed-phrases.json --import
  node phrase-importer.js --clean-duplicates --dry-run
  node phrase-importer.js --clean-duplicates
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
    
    // Check if input file exists
    if (!fs.existsSync(args.input)) {
      console.error(`❌ Error: Input file "${args.input}" not found`);
      process.exit(1);
    }
    
    console.log(`🚀 Starting phrase import...`);
    console.log(`   Input: ${args.input}`);
    console.log(`   Mode: ${args.dryRun ? 'DRY RUN' : 'LIVE IMPORT'}`);
    console.log(`   Batch size: ${args.batchSize}`);
    
    try {
      // Load input data
      const inputData = JSON.parse(fs.readFileSync(args.input, 'utf8'));
      
      let phrases = [];
      if (Array.isArray(inputData)) {
        phrases = inputData;
      } else if (inputData.phrases && Array.isArray(inputData.phrases)) {
        phrases = inputData.phrases;
      } else {
        throw new Error('Invalid input format. Expected array of phrases or object with phrases property.');
      }
      
      // Filter out phrases that don't meet quality threshold
      const qualityPhrases = phrases.filter(p => 
        p.quality && p.quality.passesThreshold !== false
      );
      
      if (qualityPhrases.length < phrases.length) {
        console.log(`📊 Filtered to ${qualityPhrases.length} high-quality phrases (${phrases.length - qualityPhrases.length} excluded)`);
      }
      
      // Import phrases
      const results = await importPhrases(qualityPhrases, {
        dryRun: args.dryRun,
        batchSize: args.batchSize
      });
      
      // Generate report
      const report = generateImportReport(results, {
        input_file: args.input,
        dry_run: args.dryRun,
        batch_size: args.batchSize,
        original_count: phrases.length,
        quality_filtered_count: qualityPhrases.length
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