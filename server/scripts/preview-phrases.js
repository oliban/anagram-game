#!/usr/bin/env node

/**
 * Phrase Preview Script
 * 
 * Preview generated phrases before importing to database.
 * Shows phrase, clue, difficulty score, and quality metrics.
 */

const fs = require('fs');
const path = require('path');

/**
 * Parse command line arguments
 */
function parseArgs() {
  const args = process.argv.slice(2);
  const parsed = {
    input: null,
    format: 'detailed',
    filter: null,
    limit: null,
    help: false
  };
  
  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--input':
        parsed.input = args[++i];
        break;
      case '--format':
        parsed.format = args[++i];
        break;
      case '--filter':
        parsed.filter = args[++i];
        break;
      case '--limit':
        parsed.limit = parseInt(args[++i]);
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
📋 Phrase Preview Script

Usage:
  node preview-phrases.js --input FILE [options]

Options:
  --input FILE       Input analyzed phrases JSON file
  --format FORMAT    Output format: detailed, simple, table, csv (default: detailed)
  --filter RANGE     Filter by difficulty range (e.g., "200-250")
  --limit N          Show only first N phrases
  --help, -h         Show this help

Examples:
  node preview-phrases.js --input analyzed-200-250-25.json
  node preview-phrases.js --input analyzed-phrases.json --format simple --limit 5
  node preview-phrases.js --input analyzed-phrases.json --format table --filter "200-250"
  node preview-phrases.js --input analyzed-phrases.json --format csv > phrases.csv
`);
}

/**
 * Filter phrases based on criteria
 */
function filterPhrases(phrases, criteria) {
  let filtered = [...phrases];
  
  if (criteria.filter) {
    const [min, max] = criteria.filter.split('-').map(n => parseInt(n));
    filtered = filtered.filter(p => p.difficulty >= min && p.difficulty <= max);
  }
  
  if (criteria.limit) {
    filtered = filtered.slice(0, criteria.limit);
  }
  
  return filtered;
}

/**
 * Format phrases for display
 */
function formatPhrases(phrases, format, metadata = null) {
  switch (format) {
    case 'simple':
      phrases.forEach((p, i) => {
        console.log(`${i + 1}. "${p.phrase}" (${p.difficulty})`);
      });
      break;
      
    case 'table':
      console.log('DIFFICULTY\tPHRASE\tCLUE');
      console.log('─'.repeat(80));
      phrases.forEach(p => {
        console.log(`${p.difficulty}\t${p.phrase}\t${p.clue}`);
      });
      break;
      
    case 'csv':
      console.log('difficulty,phrase,clue,quality_score');
      phrases.forEach(p => {
        console.log(`${p.difficulty},"${p.phrase}","${p.clue}",${p.quality?.score || 'N/A'}`);
      });
      break;
      
    case 'detailed':
    default:
      console.log('📋 PHRASE PREVIEW');
      if (metadata?.target_range) {
        console.log(`🎯 Target Range: ${metadata.target_range}`);
      }
      console.log('═'.repeat(80));
      
      phrases.forEach((p, i) => {
        console.log(`${i + 1}. PHRASE: ${p.phrase}`);
        console.log(`   CLUE: ${p.clue}`);
        console.log(`   DIFFICULTY: ${p.difficulty} (${p.difficultyLabel || 'N/A'})`);
        
        if (p.quality) {
          console.log(`   QUALITY: ${p.quality.score} ${p.quality.passesThreshold ? '✅' : '❌'}`);
        }
        
        if (p.metrics) {
          console.log(`   METRICS: ${p.metrics.wordCount} words, ${p.metrics.letterCount} letters, ${p.metrics.uniqueLetters} unique`);
        }
        
        console.log('');
      });
      
      break;
  }
}

/**
 * Display summary statistics
 */
function displaySummary(data, filteredPhrases) {
  console.log('📊 SUMMARY:');
  console.log(`   Total phrases: ${filteredPhrases.length}${data.phrases.length !== filteredPhrases.length ? ` (${data.phrases.length} total)` : ''}`);
  
  if (data.report?.qualityMetrics) {
    const metrics = data.report.qualityMetrics;
    console.log(`   Average difficulty: ${metrics.averageDifficulty}`);
    console.log(`   Average quality: ${metrics.averageQualityScore}`);
    console.log(`   Quality threshold passed: ${metrics.passedQualityThreshold}`);
  }
  
  if (data.report?.difficultyDistribution) {
    console.log('   Difficulty distribution:');
    Object.entries(data.report.difficultyDistribution).sort().forEach(([range, count]) => {
      console.log(`     ${range}: ${count} phrases`);
    });
  }
  
  if (data.report?.rangeAnalysis) {
    const analysis = data.report.rangeAnalysis;
    console.log(`   In target range: ${analysis.phrasesInRange} (${analysis.percentageInRange}%)`);
  }
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
  
  if (!args.input) {
    console.error('❌ Error: --input parameter is required');
    console.error('Use --help for usage information');
    process.exit(1);
  }
  
  // Check if input file exists
  if (!fs.existsSync(args.input)) {
    console.error(`❌ Error: Input file "${args.input}" not found`);
    process.exit(1);
  }
  
  try {
    // Load data
    const data = JSON.parse(fs.readFileSync(args.input, 'utf8'));
    
    let phrases = [];
    if (Array.isArray(data)) {
      phrases = data;
    } else if (data.phrases && Array.isArray(data.phrases)) {
      phrases = data.phrases;
    } else {
      throw new Error('Invalid input format. Expected array of phrases or object with phrases property.');
    }
    
    // Filter phrases
    const filteredPhrases = filterPhrases(phrases, args);
    
    if (filteredPhrases.length === 0) {
      console.log('📭 No phrases match the specified criteria.');
      process.exit(0);
    }
    
    // Format and display
    formatPhrases(filteredPhrases, args.format, data.metadata);
    
    // Show summary (except for CSV format)
    if (args.format !== 'csv') {
      console.log('');
      displaySummary(data, filteredPhrases);
    }
    
  } catch (error) {
    console.error(`❌ Preview failed: ${error.message}`);
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
  filterPhrases,
  formatPhrases
};