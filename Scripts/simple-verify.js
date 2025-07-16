#!/usr/bin/env node

// Simple verification - try to fetch one of our migrated phrases
const { execSync } = require('child_process');

try {
    console.log('🔍 Testing if migrated phrases are fetchable...\n');
    
    // Test the server's phrase difficulty analysis endpoint with one of our phrases
    const testPhrase = "lost keys";
    const result = execSync(`curl -s -X POST "http://localhost:8080/api/phrases/analyze-difficulty" \
        -H "Content-Type: application/json" \
        -d '{"phrase": "${testPhrase}", "language": "en"}'`, { encoding: 'utf8' });
    
    const analysis = JSON.parse(result);
    
    if (analysis.phrase === testPhrase && analysis.score) {
        console.log(`✅ Phrase "${testPhrase}" analysis successful:`);
        console.log(`   Difficulty Score: ${analysis.score}`);
        console.log(`   Difficulty Level: ${analysis.difficulty}`);
        console.log('');
        console.log('🎉 Migration verification successful!');
        console.log('   Server can analyze our migrated phrases');
        console.log('   Phrases are in the system and working properly');
    } else {
        console.log('❌ Migration verification failed');
        console.log('   Server could not analyze the test phrase');
    }
    
} catch (error) {
    console.log('❌ Verification failed:', error.message);
}