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
// Use built-in fetch (Node.js 18+) or fallback to node-fetch
const fetch = global.fetch || require('node-fetch');

// Configuration
const CONFIG = {
  batchSize: 50,
  duplicateCheck: true,
  validateSchema: true,
  outputDir: path.join(__dirname, '../data'),
  apiUrl: 'http://localhost:3000'
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
 * Insert single phrase via API (handles scoring automatically)
 */
async function insertPhraseViaAPI(phrase, dryRun = false) {
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
      action: 'would_insert_via_api',
      dryRun: true
    };
  }
  
  try {
    const response = await fetch(`${CONFIG.apiUrl}/api/phrases/create`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        content: phrase.phrase,
        hint: phrase.clue,
        language: phrase.language || 'en',
        isGlobal: true,
        senderId: "7949d9d4-6e31-428d-b2be-7b1efdc1342a", // System import user
        phraseType: 'global'
      })
    });
    
    if (!response.ok) {
      const errorText = await response.text();
      return {
        success: false,
        error: `API error (${response.status}): ${errorText}`,
        phrase: phrase.phrase
      };
    }
    
    const result = await response.json();
    return {
      success: true,
      phrase: phrase.phrase,
      id: result.id,
      difficulty: result.difficultyLevel,
      action: 'inserted_via_api'
    };
    
  } catch (error) {
    return {
      success: false,
      error: `API request failed: ${error.message}`,
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
    onProgress = null,
    useAPI = false
  } = options;
  
  console.log(`📥 ${dryRun ? 'Simulating' : 'Starting'} import of ${phrases.length} phrases via ${useAPI ? 'API' : 'direct database'}...`);
  
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
      const result = await insertPhraseViaAPI(phrase, dryRun);
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
 * Parse command line arguments
 */
function parseArgs() {
  const args = process.argv.slice(2);
  const parsed = {
    input: null,
    output: null,
    dryRun: false,
    import: false,
    batchSize: CONFIG.batchSize,
    useAPI: true, // Default to API mode
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
      case '--batch-size':
        parsed.batchSize = parseInt(args[++i]);
        break;
      case '--use-api':
        parsed.useAPI = true;
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

Options:
  --input FILE          Input JSON file with analyzed phrases
  --output FILE         Output report file (default: auto-generated)
  --dry-run            Simulate import without making changes
  --use-api            Use API endpoints for import (handles automatic scoring) [DEFAULT]
  --batch-size SIZE     Number of phrases per batch (default: 50)
  --help, -h           Show this help

Examples:
  node phrase-importer.js --input analyzed-phrases.json --dry-run
  node phrase-importer.js --input analyzed-phrases.json --import
  node phrase-importer.js --input analyzed-phrases.json --import --use-api
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
    console.log(`   Method: ${args.useAPI ? 'API' : 'Direct Database'}`);
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
        batchSize: args.batchSize,
        useAPI: args.useAPI
      });
      
      // Generate report
      const report = generateImportReport(results, {
        input_file: args.input,
        dry_run: args.dryRun,
        batch_size: args.batchSize,
        use_api: args.useAPI,
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
  validatePhraseData
};