#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const SERVER_URL = 'http://localhost:8080';
const ANAGRAMS_PATH = path.join(__dirname, '..', 'Resources', 'anagrams.txt');

// Simple clues for each phrase
const CLUES = {
    'be kind': 'Compassion',
    'hello world': 'Programming greeting',
    'time flies': 'Quick passage',
    'open door': 'Portal access',
    'quick brown fox jumps': 'Typing practice',
    'make it count': 'Value importance',
    'lost keys': 'Misplaced items',
    'coffee break': 'Work pause',
    'bright sunny day': 'Perfect weather',
    'code works': 'Programming success'
};

function createPhrase(phrase, clue) {
    const payload = JSON.stringify({
        content: phrase,
        clue: clue,
        targetIds: [],
        isGlobal: true,
        language: 'en'
    });
    
    try {
        execSync(`curl -s -X POST "${SERVER_URL}/api/phrases/create" \
            -H "Content-Type: application/json" \
            -d '${payload}'`, { stdio: 'pipe' });
        return true;
    } catch (error) {
        return false;
    }
}

function main() {
    console.log('🔄 Migrating anagrams.txt to database...\n');
    
    // Read phrases from file
    const content = fs.readFileSync(ANAGRAMS_PATH, 'utf8');
    const phrases = content.split('\n').map(line => line.trim()).filter(line => line.length > 0);
    
    console.log(`Found ${phrases.length} phrases to migrate:\n`);
    
    let successful = 0;
    let failed = 0;
    
    // Loop through each phrase and create via API
    for (const phrase of phrases) {
        const clue = CLUES[phrase] || 'Word puzzle';
        
        if (createPhrase(phrase, clue)) {
            console.log(`✅ "${phrase}" -> "${clue}"`);
            successful++;
        } else {
            console.log(`❌ "${phrase}" -> Failed`);
            failed++;
        }
    }
    
    console.log(`\n📊 Results: ${successful} successful, ${failed} failed`);
    
    if (successful === phrases.length) {
        console.log('🎉 Migration complete!');
    }
}

main();