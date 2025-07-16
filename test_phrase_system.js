#!/usr/bin/env node

/**
 * Integration test for the redesigned phrase system
 * Tests server API endpoints and difficulty filtering
 */

const http = require('http');

const SERVER_URL = 'http://localhost:8080';

// Test configuration
const TEST_CONFIG = {
    serverUrl: SERVER_URL,
    testPlayerId: '550e8400-e29b-41d4-a716-446655440000', // Test UUID
    testPlayerName: 'TestPlayer_' + Date.now()
};

console.log('🧪 Testing Phrase System Redesign');
console.log('==================================');

async function makeRequest(path, method = 'GET', data = null) {
    return new Promise((resolve, reject) => {
        const url = new URL(path, TEST_CONFIG.serverUrl);
        const options = {
            hostname: url.hostname,
            port: url.port,
            path: url.pathname + url.search,
            method: method,
            headers: {
                'Content-Type': 'application/json'
            }
        };

        const req = http.request(options, (res) => {
            let body = '';
            res.on('data', chunk => body += chunk);
            res.on('end', () => {
                try {
                    const result = {
                        status: res.statusCode,
                        data: body ? JSON.parse(body) : null
                    };
                    resolve(result);
                } catch (error) {
                    resolve({
                        status: res.statusCode,
                        data: body
                    });
                }
            });
        });

        req.on('error', reject);

        if (data) {
            req.write(JSON.stringify(data));
        }

        req.end();
    });
}

async function testServerHealth() {
    console.log('\n📊 Testing server health...');
    try {
        const result = await makeRequest('/api/status');
        if (result.status === 200) {
            console.log('✅ Server is healthy');
            return true;
        } else {
            console.log(`❌ Server health check failed: ${result.status}`);
            return false;
        }
    } catch (error) {
        console.log(`❌ Server is not accessible: ${error.message}`);
        return false;
    }
}

async function testPlayerRegistration() {
    console.log('\n👤 Testing player registration...');
    try {
        const result = await makeRequest('/api/players/register', 'POST', {
            name: TEST_CONFIG.testPlayerName,
            deviceId: 'test-device-' + Date.now()
        });

        if (result.status === 201 && result.data && result.data.player) {
            TEST_CONFIG.testPlayerId = result.data.player.id;
            console.log(`✅ Player registered: ${result.data.player.name} (${result.data.player.id})`);
            return true;
        } else {
            console.log(`❌ Player registration failed: ${result.status}`);
            console.log(`   Response: ${JSON.stringify(result.data)}`);
            return false;
        }
    } catch (error) {
        console.log(`❌ Player registration error: ${error.message}`);
        return false;
    }
}

async function testBasicPhraseAPI() {
    console.log('\n📝 Testing basic phrase API...');
    try {
        const result = await makeRequest(`/api/phrases/for/${TEST_CONFIG.testPlayerId}`);
        
        if (result.status === 200 && result.data) {
            console.log(`✅ Basic phrase API works`);
            console.log(`   Phrases returned: ${result.data.count}`);
            if (result.data.phrases && result.data.phrases.length > 0) {
                console.log(`   Sample phrase: "${result.data.phrases[0].content}"`);
            }
            return true;
        } else {
            console.log(`❌ Basic phrase API failed: ${result.status}`);
            return false;
        }
    } catch (error) {
        console.log(`❌ Basic phrase API error: ${error.message}`);
        return false;
    }
}

async function testDifficultyFiltering() {
    console.log('\n🎯 Testing difficulty filtering...');
    
    const testCases = [
        { min: 0, max: 50, name: 'Easy phrases (0-50)' },
        { min: 50, max: 100, name: 'Medium phrases (50-100)' },
        { min: 100, max: 200, name: 'Hard phrases (100-200)' }
    ];

    let passedTests = 0;

    for (const testCase of testCases) {
        try {
            const result = await makeRequest(
                `/api/phrases/for/${TEST_CONFIG.testPlayerId}?minDifficulty=${testCase.min}&maxDifficulty=${testCase.max}`
            );

            if (result.status === 200 && result.data) {
                console.log(`✅ ${testCase.name}: ${result.data.count} phrases`);
                
                // Verify difficulty filtering worked
                if (result.data.difficultyFilter) {
                    const filter = result.data.difficultyFilter;
                    if (filter.min === testCase.min && filter.max === testCase.max) {
                        console.log(`   ✓ Filter applied correctly: ${filter.min}-${filter.max}`);
                        passedTests++;
                    } else {
                        console.log(`   ❌ Filter mismatch: expected ${testCase.min}-${testCase.max}, got ${filter.min}-${filter.max}`);
                    }
                }
            } else {
                console.log(`❌ ${testCase.name} failed: ${result.status}`);
            }
        } catch (error) {
            console.log(`❌ ${testCase.name} error: ${error.message}`);
        }
    }

    return passedTests === testCases.length;
}

async function testGlobalPhrases() {
    console.log('\n🌍 Testing global phrases inclusion...');
    try {
        const result = await makeRequest(`/api/phrases/for/${TEST_CONFIG.testPlayerId}?minDifficulty=0&maxDifficulty=200`);
        
        if (result.status === 200 && result.data && result.data.phrases) {
            const globalPhrases = result.data.phrases.filter(p => p.phraseType === 'global');
            const targetedPhrases = result.data.phrases.filter(p => p.phraseType === 'targeted');
            
            console.log(`✅ Global phrases test passed`);
            console.log(`   Global phrases: ${globalPhrases.length}`);
            console.log(`   Targeted phrases: ${targetedPhrases.length}`);
            console.log(`   Total phrases: ${result.data.phrases.length}`);
            
            if (globalPhrases.length > 0) {
                console.log(`   Sample global phrase: "${globalPhrases[0].content}"`);
            }
            
            return true;
        } else {
            console.log(`❌ Global phrases test failed: ${result.status}`);
            return false;
        }
    } catch (error) {
        console.log(`❌ Global phrases test error: ${error.message}`);
        return false;
    }
}

async function testMigratedPhrases() {
    console.log('\n📦 Testing migrated anagrams.txt phrases...');
    try {
        const result = await makeRequest(`/api/phrases/for/${TEST_CONFIG.testPlayerId}?minDifficulty=0&maxDifficulty=200`);
        
        if (result.status === 200 && result.data && result.data.phrases) {
            // Look for phrases that should have been migrated from anagrams.txt
            const expectedPhrases = ['be kind', 'hello world', 'time flies', 'lost keys'];
            const foundPhrases = [];
            
            for (const phrase of result.data.phrases) {
                if (expectedPhrases.includes(phrase.content.toLowerCase())) {
                    foundPhrases.push(phrase.content);
                }
            }
            
            console.log(`✅ Migrated phrases test`);
            console.log(`   Found migrated phrases: ${foundPhrases.length}/${expectedPhrases.length}`);
            foundPhrases.forEach(phrase => {
                console.log(`   ✓ "${phrase}"`);
            });
            
            return foundPhrases.length > 0;
        } else {
            console.log(`❌ Migrated phrases test failed: ${result.status}`);
            return false;
        }
    } catch (error) {
        console.log(`❌ Migrated phrases test error: ${error.message}`);
        return false;
    }
}

async function runAllTests() {
    console.log(`\n🚀 Starting integration tests at ${new Date().toISOString()}`);
    
    const tests = [
        { name: 'Server Health', fn: testServerHealth },
        { name: 'Player Registration', fn: testPlayerRegistration },
        { name: 'Basic Phrase API', fn: testBasicPhraseAPI },
        { name: 'Difficulty Filtering', fn: testDifficultyFiltering },
        { name: 'Global Phrases', fn: testGlobalPhrases },
        { name: 'Migrated Phrases', fn: testMigratedPhrases }
    ];

    let passedTests = 0;
    let totalTests = tests.length;

    for (const test of tests) {
        try {
            const result = await test.fn();
            if (result) {
                passedTests++;
            }
        } catch (error) {
            console.log(`❌ ${test.name} crashed: ${error.message}`);
        }
    }

    console.log('\n📊 Test Results');
    console.log('===============');
    console.log(`Passed: ${passedTests}/${totalTests}`);
    console.log(`Success Rate: ${Math.round((passedTests / totalTests) * 100)}%`);

    if (passedTests === totalTests) {
        console.log('\n🎉 All tests passed! Phrase system redesign is working correctly.');
        process.exit(0);
    } else {
        console.log('\n⚠️  Some tests failed. Check the logs above for details.');
        process.exit(1);
    }
}

// Run tests
runAllTests().catch(error => {
    console.error('❌ Test suite crashed:', error);
    process.exit(1);
});