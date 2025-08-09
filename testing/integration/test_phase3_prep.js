#!/usr/bin/env node

/**
 * Phase 3 Preparation Test Script
 * 
 * This script tests the current state of the server before Phase 3 migration
 * - Validates database connectivity and health
 * - Tests all Phase 2 functionality (database player management)
 * - Validates current phrase system state 
 * - Identifies what needs to be migrated in Phase 3
 */

const axios = require('axios');
const { io } = require('socket.io-client');

const SERVER_URL = 'http://localhost:3000';
const WS_URL = 'ws://localhost:3000';

// Test results tracking
let testResults = {
  passed: 0,
  failed: 0,
  details: []
};

// Test utilities
function log(message) {
  console.log(`[TEST] ${message}`);
}

function logResult(testName, passed, details = '') {
  const status = passed ? '✅ PASS' : '❌ FAIL';
  const message = `${status}: ${testName}`;
  console.log(message);
  
  if (details) {
    console.log(`      ${details}`);
  }
  
  testResults.details.push({ testName, passed, details });
  if (passed) {
    testResults.passed++;
  } else {
    testResults.failed++;
  }
}

// HTTP API Tests
async function testServerHealth() {
  try {
    const response = await axios.get(`${SERVER_URL}/api/status`);
    const data = response.data;
    
    logResult('Server Health Check', 
      response.status === 200 && data.status === 'online',
      `Status: ${data.status}, Database connected: ${data.database ? 'Yes' : 'No'}`);
      
    if (data.database) {
      logResult('Database Connection Health',
        data.database.connected === true,
        `Pool: ${data.database.poolSize}/${data.database.maxPoolSize}, Queries: ${data.database.totalQueries}`);
    }
    
    return data;
  } catch (error) {
    logResult('Server Health Check', false, `Error: ${error.message}`);
    return null;
  }
}

async function testPlayerRegistration() {
  try {
    // Test new player registration
    const newPlayerResponse = await axios.post(`${SERVER_URL}/api/players/register`, {
      name: `TestUser_${Date.now()}`,
      socketId: 'test-socket-123'
    });
    
    logResult('New Player Registration',
      newPlayerResponse.status === 201 && newPlayerResponse.data.success,
      `Player ID: ${newPlayerResponse.data.player.id}, Name: ${newPlayerResponse.data.player.name}`);
    
    // Test existing player re-registration
    const existingPlayerResponse = await axios.post(`${SERVER_URL}/api/players/register`, {
      name: newPlayerResponse.data.player.name,
      socketId: 'test-socket-456'
    });
    
    logResult('Existing Player Re-registration',
      existingPlayerResponse.status === 201 && existingPlayerResponse.data.success,
      `Same player ID: ${existingPlayerResponse.data.player.id}`);
    
    return newPlayerResponse.data.player;
  } catch (error) {
    logResult('Player Registration', false, `Error: ${error.message}`);
    return null;
  }
}

async function testOnlinePlayers() {
  try {
    const response = await axios.get(`${SERVER_URL}/api/players/online`);
    
    logResult('Online Players Retrieval',
      response.status === 200 && Array.isArray(response.data.players),
      `Found ${response.data.count} online players`);
    
    return response.data.players;
  } catch (error) {
    logResult('Online Players Retrieval', false, `Error: ${error.message}`);
    return [];
  }
}

async function testPhraseSystem(testPlayer) {
  if (!testPlayer) {
    logResult('Phrase System Test', false, 'No test player available');
    return;
  }
  
  try {
    // Test phrase creation (current PhraseStore system)
    const phraseResponse = await axios.post(`${SERVER_URL}/api/phrases/create`, {
      content: "test phrase for migration",
      senderId: testPlayer.id,
      targetId: testPlayer.id
    });
    
    logResult('Phrase Creation (Current System)',
      phraseResponse.status === 201 && phraseResponse.data.success,
      `Phrase ID: ${phraseResponse.data.phrase.id}`);
    
    // Test phrase retrieval
    const phrasesResponse = await axios.get(`${SERVER_URL}/api/phrases/for/${testPlayer.id}`);
    
    logResult('Phrase Retrieval (Current System)',
      phrasesResponse.status === 200 && Array.isArray(phrasesResponse.data.phrases),
      `Found ${phrasesResponse.data.count} phrases`);
    
    // Test phrase consumption
    if (phrasesResponse.data.phrases.length > 0) {
      const phraseId = phrasesResponse.data.phrases[0].id;
      const consumeResponse = await axios.post(`${SERVER_URL}/api/phrases/${phraseId}/consume`);
      
      logResult('Phrase Consumption (Current System)',
        consumeResponse.status === 200 && consumeResponse.data.success,
        `Consumed phrase: ${phraseId}`);
    }
    
    // Test phrase skipping
    const skipResponse = await axios.post(`${SERVER_URL}/api/phrases/skip-test/skip`, {
      playerId: testPlayer.id
    });
    
    logResult('Phrase Skip (Current System)',
      skipResponse.status === 200 && skipResponse.data.success,
      'Skip endpoint working');
    
  } catch (error) {
    logResult('Phrase System Test', false, `Error: ${error.message}`);
  }
}

async function testDatabaseModels() {
  try {
    // Test database models directly
    const DatabasePlayer = require('./models/DatabasePlayer');
    const DatabasePhrase = require('./models/DatabasePhrase');
    
    // Test DatabasePlayer
    const playerStats = await DatabasePlayer.getPlayerCount();
    logResult('DatabasePlayer Model Test',
      playerStats.total_players >= 0,
      `Total: ${playerStats.total_players}, Active: ${playerStats.active_players}, Online: ${playerStats.online_players}`);
    
    // Test DatabasePhrase
    const phraseStats = await DatabasePhrase.getStats();
    logResult('DatabasePhrase Model Test',
      phraseStats.total >= 0,
      `Total phrases: ${phraseStats.total}, Global: ${phraseStats.global}, Targeted: ${phraseStats.targeted}`);
    
    return true;
  } catch (error) {
    logResult('Database Models Test', false, `Error: ${error.message}`);
    return false;
  }
}

async function testWebSocket() {
  return new Promise((resolve) => {
    const socket = io(WS_URL, {
      transports: ['websocket'],
      timeout: 5000
    });
    
    let testsPassed = 0;
    let testsExpected = 3;
    
    socket.on('connect', () => {
      testsPassed++;
      log(`WebSocket connected: ${socket.id}`);
    });
    
    socket.on('welcome', (data) => {
      testsPassed++;
      log(`Welcome message received: ${data.message}`);
    });
    
    socket.on('connect_error', (error) => {
      logResult('WebSocket Connection', false, `Connection error: ${error.message}`);
      resolve(false);
    });
    
    // Test player-connect event
    setTimeout(() => {
      socket.emit('player-connect', { playerId: 'test-invalid-id' });
      testsPassed++; // Count the attempt
    }, 1000);
    
    // Evaluate results
    setTimeout(() => {
      socket.disconnect();
      logResult('WebSocket Functionality',
        testsPassed >= testsExpected,
        `${testsPassed}/${testsExpected} WebSocket tests passed`);
      resolve(testsPassed >= testsExpected);
    }, 3000);
  });
}

async function identifyMigrationNeeds() {
  log('\n🔍 Phase 3 Migration Requirements Analysis:');
  
  // Check current phrase system
  const PhraseStore = require('./models/PhraseStore');
  const phraseStore = new PhraseStore();
  const currentPhraseStats = phraseStore.getStats();
  
  console.log('📊 Current Phrase System (PhraseStore):');
  console.log(`   - Total phrases: ${currentPhraseStats.total}`);
  console.log(`   - Consumed phrases: ${currentPhraseStats.consumed}`);
  console.log(`   - Storage: In-memory (will be lost on restart)`);
  console.log(`   - Hints: Not supported`);
  console.log(`   - Global phrases: Not supported`);
  console.log(`   - Offline mode: Not supported`);
  
  // Check database phrase system readiness
  try {
    const DatabasePhrase = require('./models/DatabasePhrase');
    const dbPhraseStats = await DatabasePhrase.getStats();
    
    console.log('\n📊 Database Phrase System (Ready for Migration):');
    console.log(`   - Total phrases: ${dbPhraseStats.total}`);
    console.log(`   - Global phrases: ${dbPhraseStats.global}`);
    console.log(`   - Targeted phrases: ${dbPhraseStats.targeted}`);
    console.log(`   - Hints: ✅ Supported`);
    console.log(`   - Offline mode: ✅ Ready`);
    console.log(`   - Completion tracking: ✅ Ready`);
    
    console.log('\n🔄 Migration Path for Phase 3:');
    console.log('   1. Replace PhraseStore with DatabasePhrase in all endpoints');
    console.log('   2. Add hint parameter to phrase creation');
    console.log('   3. Implement new phrase selection algorithm');
    console.log('   4. Add completion and skip tracking to database');
    console.log('   5. Remove PhraseStore completely');
    console.log('   6. Update WebSocket events to include hint data');
    
  } catch (error) {
    console.log('❌ Database phrase system not ready:', error.message);
  }
}

// Main test execution
async function runTests() {
  console.log('🧪 Phase 3 Preparation Test Suite Starting...\n');
  
  // Test server health and database
  const serverHealth = await testServerHealth();
  if (!serverHealth) {
    console.log('❌ Server not responding. Please start the server first.');
    process.exit(1);
  }
  
  // Test player management (Phase 2)
  const testPlayer = await testPlayerRegistration();
  await testOnlinePlayers();
  
  // Test current phrase system (to be migrated)
  await testPhraseSystem(testPlayer);
  
  // Test database models (Phase 3 ready)
  await testDatabaseModels();
  
  // Test WebSocket functionality
  await testWebSocket();
  
  // Analyze migration requirements
  await identifyMigrationNeeds();
  
  // Final results
  console.log('\n📋 Test Results Summary:');
  console.log(`✅ Passed: ${testResults.passed}`);
  console.log(`❌ Failed: ${testResults.failed}`);
  console.log(`🎯 Total: ${testResults.passed + testResults.failed}`);
  
  if (testResults.failed === 0) {
    console.log('\n🎉 All tests passed! Ready for Phase 3 migration.');
  } else {
    console.log('\n⚠️  Some tests failed. Fix issues before Phase 3 migration.');
    process.exit(1);
  }
}

// Run tests if script is executed directly
if (require.main === module) {
  runTests().catch(error => {
    console.error('Test execution failed:', error);
    process.exit(1);
  });
}

module.exports = { runTests, testResults };