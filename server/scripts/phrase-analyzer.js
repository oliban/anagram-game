#!/usr/bin/env node

/**
 * Phrase Analyzer Script
 * 
 * Analyzes existing phrases against the difficulty algorithm.
 * Filters phrases to match target difficulty ranges.
 * Validates phrase quality and generates analysis reports.
 */

const fs = require('fs');
const path = require('path');
const { calculateScore, getDifficultyLabel } = require('../../shared/difficulty-algorithm');

// Configuration
const CONFIG = {
  difficultyTolerance: 5,
  outputDir: path.join(__dirname, '../data'),
  qualityThreshold: 0.8,
  duplicateCheck: true
};

/**
 * Analyze a single phrase
 */
function analyzePhrase(phraseData, targetRange = null, language = 'en') {
  const phrase = phraseData.phrase || phraseData.content || phraseData;
  
  if (!phrase || typeof phrase !== 'string') {
    return null;
  }
  
  try {
    const difficulty = calculateScore({ phrase, language });
    const roundedDifficulty = Math.round(difficulty);
    const difficultyLabel = getDifficultyLabel(difficulty);
    
    // Calculate phrase metrics
    const words = phrase.trim().split(/\s+/);
    const wordCount = words.length;
    const letterCount = phrase.replace(/[^a-zA-Z]/g, '').length;
    const uniqueLetters = new Set(phrase.toLowerCase().replace(/[^a-z]/g, '')).size;
    const averageWordLength = letterCount / wordCount;
    
    // Quality score based on various factors
    let qualityScore = 1.0;
    
    // Penalize very short phrases
    if (wordCount < 2) qualityScore *= 0.3;
    if (letterCount < 4) qualityScore *= 0.5;
    
    // Penalize phrases with too many repeated words
    const uniqueWords = new Set(words.map(w => w.toLowerCase())).size;
    const wordRepetitionRatio = uniqueWords / wordCount;
    if (wordRepetitionRatio < 0.8) qualityScore *= 0.7;
    
    // Penalize phrases with excessive letter repetition
    const letterRepetitionRatio = uniqueLetters / letterCount;
    if (letterRepetitionRatio < 0.3) qualityScore *= 0.8;
    
    // Bonus for balanced phrase length
    if (wordCount >= 2 && wordCount <= 6 && averageWordLength >= 3 && averageWordLength <= 8) {
      qualityScore *= 1.1;
    }
    
    const analysis = {
      phrase: phrase,
      clue: phraseData.clue || phraseData.hint || `Unscramble these ${wordCount} words`,
      difficulty: roundedDifficulty,
      difficultyLabel: difficultyLabel,
      language: language,
      metrics: {
        wordCount: wordCount,
        letterCount: letterCount,
        uniqueLetters: uniqueLetters,
        averageWordLength: parseFloat(averageWordLength.toFixed(2)),
        wordRepetitionRatio: parseFloat(wordRepetitionRatio.toFixed(3)),
        letterRepetitionRatio: parseFloat(letterRepetitionRatio.toFixed(3))
      },
      quality: {
        score: parseFloat(qualityScore.toFixed(3)),
        passesThreshold: qualityScore >= CONFIG.qualityThreshold
      },
      analyzed_at: new Date().toISOString()
    };
    
    // Add original data if it exists
    if (phraseData.generated_at) analysis.generated_at = phraseData.generated_at;
    if (phraseData.pattern) analysis.pattern = phraseData.pattern;
    
    // Check if it fits target range
    if (targetRange) {
      const [minDiff, maxDiff] = targetRange.split('-').map(n => parseInt(n));
      analysis.fitsTargetRange = roundedDifficulty >= (minDiff - CONFIG.difficultyTolerance) && 
                                 roundedDifficulty <= (maxDiff + CONFIG.difficultyTolerance);
    }
    
    return analysis;
    
  } catch (error) {
    console.warn(`⚠️ Error analyzing phrase "${phrase}": ${error.message}`);
    return null;
  }
}

/**
 * Analyze multiple phrases from input data
 */
async function analyzePhrases(inputData, targetRange = null, language = 'en') {
  console.log(`🔍 Analyzing phrases...`);
  
  let phrases = [];
  
  // Handle different input formats
  if (Array.isArray(inputData)) {
    phrases = inputData;
  } else if (inputData.phrases && Array.isArray(inputData.phrases)) {
    phrases = inputData.phrases;
  } else if (typeof inputData === 'object') {
    // Try to extract phrases from object
    phrases = Object.values(inputData).filter(item => 
      item && (item.phrase || item.content)
    );
  } else {
    throw new Error('Invalid input format. Expected array of phrases or object with phrases property.');
  }
  
  console.log(`📊 Found ${phrases.length} phrases to analyze`);
  
  const analyzed = [];
  const duplicates = new Set();
  let skipped = 0;
  
  for (let i = 0; i < phrases.length; i++) {
    const phrase = phrases[i];
    
    // Show progress
    if ((i + 1) % 100 === 0 || (i + 1) === phrases.length) {
      console.log(`📈 Progress: ${i + 1}/${phrases.length} phrases analyzed`);
    }
    
    const analysis = analyzePhrase(phrase, targetRange, language);
    
    if (!analysis) {
      skipped++;
      continue;
    }
    
    // Check for duplicates if enabled
    if (CONFIG.duplicateCheck) {
      const normalizedPhrase = analysis.phrase.toLowerCase().replace(/[^a-z]/g, '');
      if (duplicates.has(normalizedPhrase)) {
        console.log(`⚠️ Skipping duplicate phrase: "${analysis.phrase}"`);
        skipped++;
        continue;
      }
      duplicates.add(normalizedPhrase);
    }
    
    analyzed.push(analysis);
  }
  
  console.log(`✅ Analysis complete: ${analyzed.length} phrases analyzed, ${skipped} skipped`);
  return analyzed;
}

/**
 * Generate analysis report
 */
function generateAnalysisReport(analyzedPhrases, targetRange = null) {
  const report = {
    summary: {
      totalPhrases: analyzedPhrases.length,
      analyzedAt: new Date().toISOString(),
      targetRange: targetRange
    },
    qualityMetrics: {
      passedQualityThreshold: 0,
      averageQualityScore: 0,
      averageDifficulty: 0
    },
    difficultyDistribution: {},
    qualityDistribution: {
      excellent: 0,  // >= 0.9
      good: 0,       // >= 0.8
      acceptable: 0, // >= 0.6
      poor: 0        // < 0.6
    },
    wordCountDistribution: {},
    rangeAnalysis: {}
  };
  
  if (analyzedPhrases.length === 0) {
    return report;
  }
  
  let totalQuality = 0;
  let totalDifficulty = 0;
  let inTargetRange = 0;
  
  analyzedPhrases.forEach(phrase => {
    // Quality metrics
    totalQuality += phrase.quality.score;
    if (phrase.quality.passesThreshold) {
      report.qualityMetrics.passedQualityThreshold++;
    }
    
    // Quality distribution
    if (phrase.quality.score >= 0.9) report.qualityDistribution.excellent++;
    else if (phrase.quality.score >= 0.8) report.qualityDistribution.good++;
    else if (phrase.quality.score >= 0.6) report.qualityDistribution.acceptable++;
    else report.qualityDistribution.poor++;
    
    // Difficulty metrics
    totalDifficulty += phrase.difficulty;
    
    // Difficulty distribution (10-point buckets)
    const bucket = Math.floor(phrase.difficulty / 10) * 10;
    const bucketKey = `${bucket}-${bucket + 9}`;
    report.difficultyDistribution[bucketKey] = (report.difficultyDistribution[bucketKey] || 0) + 1;
    
    // Word count distribution
    const wordCount = phrase.metrics.wordCount;
    report.wordCountDistribution[wordCount] = (report.wordCountDistribution[wordCount] || 0) + 1;
    
    // Target range analysis
    if (phrase.fitsTargetRange !== undefined && phrase.fitsTargetRange) {
      inTargetRange++;
    }
  });
  
  // Calculate averages
  report.qualityMetrics.averageQualityScore = parseFloat((totalQuality / analyzedPhrases.length).toFixed(3));
  report.qualityMetrics.averageDifficulty = parseFloat((totalDifficulty / analyzedPhrases.length).toFixed(1));
  
  // Target range analysis
  if (targetRange) {
    report.rangeAnalysis = {
      targetRange: targetRange,
      phrasesInRange: inTargetRange,
      percentageInRange: parseFloat(((inTargetRange / analyzedPhrases.length) * 100).toFixed(1))
    };
  }
  
  return report;
}

/**
 * Generate table preview of all phrases with difficulty scores
 */
function generateTablePreview(analyzedPhrases, outputPath, language = 'en') {
  const previewPath = outputPath.replace(/\.json$/, '-preview.txt');
  
  let preview = '';
  preview += '📊 Phrase Analysis Preview\n';
  preview += '==========================\n\n';
  
  // Header
  preview += 'Phrase'.padEnd(25) + ' | ' + 'Score'.padEnd(5) + ' | ' + 'Clue\n';
  preview += ''.padEnd(25, '-') + '-+-' + ''.padEnd(5, '-') + '-+-' + ''.padEnd(50, '-') + '\n';
  
  // Sort phrases by difficulty score for better readability
  const sortedPhrases = [...analyzedPhrases].sort((a, b) => a.difficulty - b.difficulty);
  
  // Generate table rows
  sortedPhrases.forEach(p => {
    const phrase = (p.phrase || '').padEnd(25);
    const score = p.difficulty.toString().padEnd(5);
    const clue = p.clue || 'No clue provided';
    preview += phrase + ' | ' + score + ' | ' + clue + '\n';
  });
  
  // Summary
  preview += '\n📈 Summary:\n';
  preview += `- Total phrases: ${analyzedPhrases.length}\n`;
  preview += `- Average difficulty: ${(analyzedPhrases.reduce((sum, p) => sum + p.difficulty, 0) / analyzedPhrases.length).toFixed(1)}\n`;
  preview += `- Language: ${language}\n`;
  preview += `- Generated: ${new Date().toISOString()}\n`;
  
  // Difficulty distribution
  const distribution = {};
  analyzedPhrases.forEach(p => {
    const bucket = Math.floor(p.difficulty / 10) * 10;
    const key = `${bucket}-${bucket + 9}`;
    distribution[key] = (distribution[key] || 0) + 1;
  });
  
  preview += '\n📊 Difficulty Distribution:\n';
  Object.entries(distribution).sort().forEach(([range, count]) => {
    preview += `- ${range}: ${count} phrases\n`;
  });
  
  // Write preview file
  fs.writeFileSync(previewPath, preview);
  
  console.log(`📋 Table preview saved: ${previewPath}`);
  return previewPath;
}

/**
 * Filter phrases by criteria
 */
function filterPhrases(analyzedPhrases, criteria = {}) {
  let filtered = [...analyzedPhrases];
  
  // Filter by target range
  if (criteria.targetRange) {
    filtered = filtered.filter(p => p.fitsTargetRange === true);
  }
  
  // Filter by quality threshold
  if (criteria.minQuality !== undefined) {
    filtered = filtered.filter(p => p.quality.score >= criteria.minQuality);
  }
  
  // Filter by difficulty range
  if (criteria.minDifficulty !== undefined) {
    filtered = filtered.filter(p => p.difficulty >= criteria.minDifficulty);
  }
  if (criteria.maxDifficulty !== undefined) {
    filtered = filtered.filter(p => p.difficulty <= criteria.maxDifficulty);
  }
  
  // Filter by word count
  if (criteria.minWords !== undefined) {
    filtered = filtered.filter(p => p.metrics.wordCount >= criteria.minWords);
  }
  if (criteria.maxWords !== undefined) {
    filtered = filtered.filter(p => p.metrics.wordCount <= criteria.maxWords);
  }
  
  return filtered;
}

/**
 * Parse command line arguments
 */
function parseArgs() {
  const args = process.argv.slice(2);
  const parsed = {
    input: null,
    output: null,
    targetRange: null,
    language: 'en',
    minQuality: CONFIG.qualityThreshold,
    reportOnly: false,
    filter: false,
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
      case '--target-range':
        parsed.targetRange = args[++i];
        break;
      case '--language':
        parsed.language = args[++i];
        break;
      case '--min-quality':
        parsed.minQuality = parseFloat(args[++i]);
        break;
      case '--report-only':
        parsed.reportOnly = true;
        break;
      case '--filter':
        parsed.filter = true;
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
🔍 Phrase Analyzer Script

Usage:
  node phrase-analyzer.js --input FILE [options]

Options:
  --input FILE           Input JSON file with phrases
  --output FILE          Output JSON file (default: auto-generated)
  --target-range RANGE   Target difficulty range (e.g., "200-250")
  --language LANG        Language code (default: en)
  --min-quality SCORE    Minimum quality score (default: 0.8)
  --report-only          Generate report without saving analyzed phrases
  --filter               Filter phrases to only include those meeting criteria
  --help, -h            Show this help

Examples:
  node phrase-analyzer.js --input generated-phrases.json
  node phrase-analyzer.js --input phrases.json --target-range "200-250" --filter
  node phrase-analyzer.js --input phrases.json --min-quality 0.9 --report-only
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
  
  // Generate output filename if not specified
  if (!args.output && !args.reportOnly) {
    const inputBase = path.basename(args.input, path.extname(args.input));
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19); // YYYY-MM-DDTHH-MM-SS
    // Extract language from input filename or default to unknown
    const languageMatch = inputBase.match(/-(en|sv)-/) || ['', 'unknown'];
    const language = languageMatch[1];
    args.output = path.join(CONFIG.outputDir, `analyzed-${language}-${inputBase}-${timestamp}.json`);
  }
  
  console.log(`🚀 Starting phrase analysis...`);
  console.log(`   Input: ${args.input}`);
  if (args.output) console.log(`   Output: ${args.output}`);
  if (args.targetRange) console.log(`   Target range: ${args.targetRange}`);
  console.log(`   Language: ${args.language}`);
  console.log(`   Min quality: ${args.minQuality}`);
  
  try {
    // Load input data
    const inputData = JSON.parse(fs.readFileSync(args.input, 'utf8'));
    
    // Analyze phrases
    const analyzedPhrases = await analyzePhrases(inputData, args.targetRange, args.language);
    
    // Apply filters if requested
    let finalPhrases = analyzedPhrases;
    if (args.filter) {
      const filterCriteria = {
        targetRange: args.targetRange,
        minQuality: args.minQuality
      };
      
      finalPhrases = filterPhrases(analyzedPhrases, filterCriteria);
      console.log(`📊 Filtered to ${finalPhrases.length} high-quality phrases`);
    }
    
    // Generate report
    const report = generateAnalysisReport(analyzedPhrases, args.targetRange);
    
    // Display summary
    console.log(`\n📊 Analysis Summary:`);
    console.log(`   Total phrases: ${report.summary.totalPhrases}`);
    console.log(`   Average difficulty: ${report.qualityMetrics.averageDifficulty}`);
    console.log(`   Average quality: ${report.qualityMetrics.averageQualityScore}`);
    console.log(`   Quality threshold passed: ${report.qualityMetrics.passedQualityThreshold}`);
    
    if (args.targetRange && report.rangeAnalysis) {
      console.log(`   In target range: ${report.rangeAnalysis.phrasesInRange} (${report.rangeAnalysis.percentageInRange}%)`);
    }
    
    console.log(`   Difficulty distribution:`);
    Object.entries(report.difficultyDistribution).sort().forEach(([range, count]) => {
      console.log(`     ${range}: ${count} phrases`);
    });
    
    // Save output
    if (!args.reportOnly && args.output) {
      const output = {
        metadata: {
          analyzed_at: new Date().toISOString(),
          input_file: args.input,
          target_range: args.targetRange,
          language: args.language,
          min_quality: args.minQuality,
          filtered: args.filter,
          analyzer_version: '1.0.0'
        },
        report: report,
        phrases: finalPhrases
      };
      
      // Ensure output directory exists
      fs.mkdirSync(path.dirname(args.output), { recursive: true });
      fs.writeFileSync(args.output, JSON.stringify(output, null, 2));
      
      // Generate table preview with all phrases
      const previewPath = generateTablePreview(finalPhrases, args.output, args.language);
      
      console.log(`\n✅ Analysis complete!`);
      console.log(`   Output saved: ${args.output}`);
      console.log(`   Preview saved: ${previewPath}`);
      console.log(`   Final phrase count: ${finalPhrases.length}`);
    } else {
      console.log(`\n✅ Analysis complete! (Report only mode)`);
    }
    
  } catch (error) {
    console.error(`❌ Analysis failed: ${error.message}`);
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
  analyzePhrase,
  analyzePhrases,
  generateAnalysisReport,
  filterPhrases
};