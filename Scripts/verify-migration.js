#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const SERVER_URL = 'http://localhost:8080';
const ANAGRAMS_PATH = path.join(__dirname, '..', 'Resources', 'anagrams.txt');

// Expected clues for verification
const EXPECTED_CLUES = {
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

function queryDatabase() {
    try {
        // Connect to database and query for our phrases
        const result = execSync(`
            cd server && node -e "
            const { Pool } = require('pg');
            const pool = new Pool({
                user: 'postgres',
                host: 'localhost',
                database: 'anagram_game',
                password: 'password',
                port: 5432,
            });
            
            async function checkPhrases() {
                const phrases = Object.keys(${JSON.stringify(EXPECTED_CLUES)});
                console.log('Checking migration results...\n');
                
                let found = 0;
                let missing = 0;
                
                for (const phrase of phrases) {
                    try {
                        const result = await pool.query(
                            'SELECT content, hint, difficulty_score FROM phrases WHERE content = $1',
                            [phrase]
                        );
                        
                        if (result.rows.length > 0) {
                            const row = result.rows[0];
                            const expectedClue = ${JSON.stringify(EXPECTED_CLUES)}[phrase];
                            const clueMatch = row.hint === expectedClue;
                            
                            console.log(\`✅ \\\"\${phrase}\\\" -> hint: \\\"\${row.hint}\\\", difficulty: \${row.difficulty_score} \${clueMatch ? '✓' : '✗ (wrong clue)'}\`);
                            found++;
                        } else {
                            console.log(\`❌ \\\"\${phrase}\\\" -> NOT FOUND\`);
                            missing++;
                        }
                    } catch (error) {
                        console.log(\`❌ \\\"\${phrase}\\\" -> ERROR: \${error.message}\`);
                        missing++;
                    }
                }
                
                console.log(\`\n📊 Results: \${found} found, \${missing} missing\`);
                
                if (found === phrases.length) {
                    console.log('🎉 Migration verification successful!');
                } else {
                    console.log('⚠️ Migration verification failed - some phrases missing');
                }
                
                await pool.end();
            }
            
            checkPhrases().catch(console.error);
            "
        `, { encoding: 'utf8' });
        
        console.log(result);
        return true;
    } catch (error) {
        console.error('Database query failed:', error.message);
        return false;
    }
}

function main() {
    console.log('🔍 Verifying migration of anagrams.txt to database...\n');
    
    // Read original phrases for comparison
    const content = fs.readFileSync(ANAGRAMS_PATH, 'utf8');
    const originalPhrases = content.split('\n').map(line => line.trim()).filter(line => line.length > 0);
    
    console.log(`Original file contained ${originalPhrases.length} phrases`);
    console.log(`Expected to find ${Object.keys(EXPECTED_CLUES).length} phrases in database\n`);
    
    // Query database to verify
    queryDatabase();
}

main();