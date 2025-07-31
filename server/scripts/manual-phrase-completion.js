#!/usr/bin/env node

/**
 * Manual Phrase Generation Completion Helper
 * 
 * Use this script to complete the phrase generation process after
 * Claude has generated phrases using the Task tool.
 */

const fs = require('fs');
const path = require('path');

/**
 * Complete the phrase generation by saving AI-generated phrases to the output file
 */
function completePhraseGeneration(phrases, outputFile, metadata = {}) {
  console.log(`💾 Saving ${phrases.length} phrases to ${outputFile}`);
  
  const output = {
    metadata: {
      generated_at: new Date().toISOString(),
      target_range: metadata.target_range || 'unknown',
      requested_count: metadata.requested_count || phrases.length,
      actual_count: phrases.length,
      language: metadata.language || 'en',
      generator_version: '1.0.0',
      generated_by: 'claude_task_tool'
    },
    phrases: phrases
  };
  
  // Ensure output directory exists
  fs.mkdirSync(path.dirname(outputFile), { recursive: true });
  
  // Save the file
  fs.writeFileSync(outputFile, JSON.stringify(output, null, 2));
  
  console.log(`✅ Phrase generation completed successfully!`);
  console.log(`📁 Output saved: ${outputFile}`);
  console.log(`📊 Generated: ${phrases.length} phrases`);
  
  return output;
}

/**
 * Show usage instructions
 */
function showUsage() {
  console.log(`
📝 Manual Phrase Generation Completion Helper

Usage:
  node manual-phrase-completion.js <output-file> [options]

Arguments:
  output-file    Path to save the generated phrases JSON file

Options:
  --input FILE   Read phrases from JSON file (array of {phrase, clue} objects)
  --range RANGE  Target difficulty range (e.g., "50-100")
  --count COUNT  Requested phrase count
  --language LANG Language code (default: "en")

Examples:
  # Complete with phrases from stdin (paste JSON array)
  node manual-phrase-completion.js ./data/generated-phrases.json --range "50-100" --count 50

  # Complete with phrases from file
  node manual-phrase-completion.js ./data/generated-phrases.json --input phrases.json

Interactive Mode:
  If no --input is provided, the script will prompt you to paste the JSON array.
`);
}

/**
 * Read phrases interactively from stdin
 */
function readPhrasesInteractively() {
  return new Promise((resolve) => {
    console.log(`📝 Please paste the JSON array of phrases (then press Enter and Ctrl+D):`);
    
    let input = '';
    process.stdin.setEncoding('utf8');
    
    process.stdin.on('data', (chunk) => {
      input += chunk;
    });
    
    process.stdin.on('end', () => {
      try {
        const phrases = JSON.parse(input.trim());
        if (!Array.isArray(phrases)) {
          throw new Error('Expected JSON array');
        }
        resolve(phrases);
      } catch (error) {
        console.error(`❌ Error parsing JSON: ${error.message}`);
        process.exit(1);
      }
    });
  });
}

/**
 * Main execution
 */
async function main() {
  const args = process.argv.slice(2);
  
  if (args.length === 0 || args.includes('--help') || args.includes('-h')) {
    showUsage();
    process.exit(0);
  }
  
  const outputFile = args[0];
  if (!outputFile) {
    console.error('❌ Error: Output file path is required');
    showUsage();
    process.exit(1);
  }
  
  // Parse arguments
  let inputFile = null;
  let targetRange = 'unknown';
  let requestedCount = null;
  let language = 'en';
  
  for (let i = 1; i < args.length; i++) {
    switch (args[i]) {
      case '--input':
        inputFile = args[++i];
        break;
      case '--range':
        targetRange = args[++i];
        break;
      case '--count':
        requestedCount = parseInt(args[++i]);
        break;
      case '--language':
        language = args[++i];
        break;
    }
  }
  
  let phrases;
  
  if (inputFile) {
    // Read from file
    console.log(`📁 Reading phrases from: ${inputFile}`);
    if (!fs.existsSync(inputFile)) {
      console.error(`❌ Error: Input file not found: ${inputFile}`);
      process.exit(1);
    }
    
    const content = fs.readFileSync(inputFile, 'utf8');
    phrases = JSON.parse(content);
  } else {
    // Read interactively
    phrases = await readPhrasesInteractively();
  }
  
  // Validate phrases format
  if (!Array.isArray(phrases)) {
    console.error('❌ Error: Expected JSON array of phrases');
    process.exit(1);
  }
  
  for (const phrase of phrases) {
    if (!phrase.phrase || !phrase.clue) {
      console.error('❌ Error: Each phrase must have "phrase" and "clue" properties');
      process.exit(1);
    }
  }
  
  // Complete the generation
  const metadata = {
    target_range: targetRange,
    requested_count: requestedCount || phrases.length,
    language: language
  };
  
  completePhraseGeneration(phrases, outputFile, metadata);
  
  console.log(`\n🎯 Next steps:`);
  console.log(`   1. Run the phrase analyzer on this file`);
  console.log(`   2. Import the analyzed phrases to the database`);
  console.log(`   Or continue with the original generation script`);
}

// Run if called directly
if (require.main === module) {
  main().catch(error => {
    console.error('❌ Unexpected error:', error);
    process.exit(1);
  });
}

module.exports = {
  completePhraseGeneration
};