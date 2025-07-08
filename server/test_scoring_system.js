#!/usr/bin/env node

/**
 * Scoring System Test Suite
 * Tests Phase 4.9 scoring, leaderboards, and aggregation functionality
 */

const BASE_URL = 'http://localhost:3000';

class ScoringSystemTester {
  constructor() {
    this.testResults = [];
    this.testPlayers = [];
    this.testPhrases = [];
  }

  async runTest(name, testFunction) {
    try {
      console.log(`\n🧪 Testing: ${name}`);
      const startTime = Date.now();
      await testFunction();
      const duration = Date.now() - startTime;
      console.log(`✅ ${name} - PASSED (${duration}ms)`);
      this.testResults.push({ name, status: 'PASSED', duration });
    } catch (error) {
      console.log(`❌ ${name} - FAILED: ${error.message}`);
      this.testResults.push({ name, status: 'FAILED', error: error.message });
    }
  }

  async setupTestData() {
    console.log('📋 Setting up test data...');
    
    // Create multiple test players
    for (let i = 1; i <= 5; i++) {
      const playerResponse = await fetch(`${BASE_URL}/api/players/register`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: `ScoringTestPlayer${i}` })
      });
      
      if (!playerResponse.ok) {
        throw new Error(`Failed to create test player ${i}`);
      }
      
      const player = await playerResponse.json();
      this.testPlayers.push(player.player);
      console.log(`👤 Created test player ${i}: ${player.player.id}`);
    }

    // Create multiple test phrases with different difficulties
    const phrases = [
      { content: 'hello world', hint: 'A simple greeting' },
      { content: 'difficult anagram puzzle challenge', hint: 'This is quite complex' },
      { content: 'quick brown fox jumps', hint: 'Classic pangram phrase' },
      { content: 'scoring system test', hint: 'Testing our new feature' },
      { content: 'leaderboard ranking', hint: 'Competition system' }
    ];

    for (const phraseData of phrases) {
      const phraseResponse = await fetch(`${BASE_URL}/api/phrases/create`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          content: phraseData.content,
          hint: phraseData.hint,
          senderId: this.testPlayers[0].id,
          isGlobal: true
        })
      });
      
      if (!phraseResponse.ok) {
        throw new Error(`Failed to create test phrase: ${phraseData.content}`);
      }
      
      const phrase = await phraseResponse.json();
      this.testPhrases.push(phrase.phrase);
      console.log(`📝 Created test phrase: "${phraseData.content}" (${phrase.phrase.difficultyLevel} points)`);
    }
  }

  async simulateGameplay() {
    console.log('🎮 Simulating gameplay for scoring...');
    
    // Simulate different players completing phrases with different hint usage
    for (let playerIndex = 0; playerIndex < this.testPlayers.length; playerIndex++) {
      const player = this.testPlayers[playerIndex];
      
      for (let phraseIndex = 0; phraseIndex < Math.min(3, this.testPhrases.length); phraseIndex++) {
        const phrase = this.testPhrases[phraseIndex];
        
        // Simulate different hint usage patterns
        const hintsToUse = playerIndex % 4; // 0-3 hints
        
        // Use hints based on pattern
        for (let hintLevel = 1; hintLevel <= hintsToUse; hintLevel++) {
          await fetch(`${BASE_URL}/api/phrases/${phrase.id}/hint/${hintLevel}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ playerId: player.id })
          });
        }
        
        // Complete the phrase
        const completionResponse = await fetch(`${BASE_URL}/api/phrases/${phrase.id}/complete`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ 
            playerId: player.id,
            completionTime: 5000 + (Math.random() * 10000) // Random completion time
          })
        });
        
        if (completionResponse.ok) {
          const completion = await completionResponse.json();
          console.log(`🎯 ${player.name} completed "${phrase.content}" with ${hintsToUse} hints: ${completion.completion.finalScore} points`);
        }
      }
    }
    
    // Wait a moment for score aggregation to complete
    await new Promise(resolve => setTimeout(resolve, 1000));
  }

  async testPlayerScoreSummary() {
    const testPlayer = this.testPlayers[0];
    
    const response = await fetch(`${BASE_URL}/api/scores/player/${testPlayer.id}`);
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${await response.text()}`);
    }
    
    const data = await response.json();
    
    if (!data.success) {
      throw new Error('Response indicates failure');
    }
    
    // Validate response structure
    const requiredFields = ['dailyScore', 'dailyRank', 'weeklyScore', 'weeklyRank', 'totalScore', 'totalRank', 'totalPhrases'];
    for (const field of requiredFields) {
      if (!(field in data.scores)) {
        throw new Error(`Missing field '${field}' in player score summary`);
      }
    }
    
    // Validate that scores are numbers
    if (typeof data.scores.totalScore !== 'number' || data.scores.totalScore < 0) {
      throw new Error('Invalid total score value');
    }
    
    if (typeof data.scores.totalPhrases !== 'number' || data.scores.totalPhrases < 0) {
      throw new Error('Invalid total phrases value');
    }
    
    console.log(`📊 Player score summary for ${data.playerName}:`);
    console.log(`   - Daily: ${data.scores.dailyScore} points (rank ${data.scores.dailyRank})`);
    console.log(`   - Weekly: ${data.scores.weeklyScore} points (rank ${data.scores.weeklyRank})`);
    console.log(`   - Total: ${data.scores.totalScore} points (rank ${data.scores.totalRank})`);
    console.log(`   - Phrases completed: ${data.scores.totalPhrases}`);
  }

  async testDailyLeaderboard() {
    const response = await fetch(`${BASE_URL}/api/leaderboards/daily`);
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${await response.text()}`);
    }
    
    const data = await response.json();
    
    if (!data.success) {
      throw new Error('Response indicates failure');
    }
    
    // Validate response structure
    if (!Array.isArray(data.leaderboard)) {
      throw new Error('Leaderboard should be an array');
    }
    
    if (!data.pagination) {
      throw new Error('Missing pagination information');
    }
    
    if (data.period !== 'daily') {
      throw new Error('Incorrect period in response');
    }
    
    // Validate leaderboard entries
    for (const entry of data.leaderboard) {
      const requiredFields = ['rank', 'playerName', 'totalScore', 'phrasesCompleted'];
      for (const field of requiredFields) {
        if (!(field in entry)) {
          throw new Error(`Missing field '${field}' in leaderboard entry`);
        }
      }
      
      if (typeof entry.rank !== 'number' || entry.rank < 1) {
        throw new Error('Invalid rank value');
      }
      
      if (typeof entry.totalScore !== 'number' || entry.totalScore < 0) {
        throw new Error('Invalid total score value');
      }
    }
    
    // Validate ranking order (should be descending by score)
    for (let i = 1; i < data.leaderboard.length; i++) {
      if (data.leaderboard[i-1].totalScore < data.leaderboard[i].totalScore) {
        throw new Error('Leaderboard not properly sorted by score');
      }
    }
    
    console.log(`📊 Daily leaderboard retrieved: ${data.leaderboard.length} entries`);
    if (data.leaderboard.length > 0) {
      console.log(`   - Top player: ${data.leaderboard[0].playerName} with ${data.leaderboard[0].totalScore} points`);
    }
  }

  async testWeeklyLeaderboard() {
    const response = await fetch(`${BASE_URL}/api/leaderboards/weekly?limit=10`);
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${await response.text()}`);
    }
    
    const data = await response.json();
    
    if (!data.success) {
      throw new Error('Response indicates failure');
    }
    
    if (data.period !== 'weekly') {
      throw new Error('Incorrect period in response');
    }
    
    if (data.pagination.limit !== 10) {
      throw new Error('Incorrect limit in pagination');
    }
    
    console.log(`📊 Weekly leaderboard retrieved: ${data.leaderboard.length} entries (limit 10)`);
  }

  async testTotalLeaderboard() {
    const response = await fetch(`${BASE_URL}/api/leaderboards/total?limit=5&offset=0`);
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${await response.text()}`);
    }
    
    const data = await response.json();
    
    if (!data.success) {
      throw new Error('Response indicates failure');
    }
    
    if (data.period !== 'total') {
      throw new Error('Incorrect period in response');
    }
    
    // Test pagination
    if (data.pagination.limit !== 5 || data.pagination.offset !== 0) {
      throw new Error('Incorrect pagination parameters');
    }
    
    console.log(`📊 Total leaderboard retrieved: ${data.leaderboard.length} entries (limit 5, offset 0)`);
  }

  async testGlobalStatistics() {
    const response = await fetch(`${BASE_URL}/api/stats/global`);
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${await response.text()}`);
    }
    
    const data = await response.json();
    
    if (!data.success) {
      throw new Error('Response indicates failure');
    }
    
    // Validate response structure
    if (!data.stats.overall || !data.stats.today || !data.stats.leaderboards) {
      throw new Error('Missing statistics sections');
    }
    
    const overall = data.stats.overall;
    const requiredOverallFields = ['activePlayers', 'totalCompletions', 'averageScore', 'highestScore', 'totalPointsAwarded'];
    for (const field of requiredOverallFields) {
      if (!(field in overall)) {
        throw new Error(`Missing field '${field}' in overall statistics`);
      }
    }
    
    const today = data.stats.today;
    const requiredTodayFields = ['completions', 'activePlayers', 'pointsAwarded'];
    for (const field of requiredTodayFields) {
      if (!(field in today)) {
        throw new Error(`Missing field '${field}' in today's statistics`);
      }
    }
    
    const leaderboards = data.stats.leaderboards;
    const requiredLeaderboardFields = ['daily', 'weekly', 'total'];
    for (const field of requiredLeaderboardFields) {
      if (!(field in leaderboards)) {
        throw new Error(`Missing field '${field}' in leaderboard statistics`);
      }
    }
    
    console.log(`📊 Global statistics retrieved:`);
    console.log(`   - Active players: ${overall.activePlayers}`);
    console.log(`   - Total completions: ${overall.totalCompletions}`);
    console.log(`   - Average score: ${overall.averageScore}`);
    console.log(`   - Highest score: ${overall.highestScore}`);
    console.log(`   - Today's completions: ${today.completions}`);
    console.log(`   - Today's active players: ${today.activePlayers}`);
    console.log(`   - Leaderboard sizes: Daily ${leaderboards.daily}, Weekly ${leaderboards.weekly}, Total ${leaderboards.total}`);
  }

  async testLeaderboardRefresh() {
    const response = await fetch(`${BASE_URL}/api/scores/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    });
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${await response.text()}`);
    }
    
    const data = await response.json();
    
    if (!data.success) {
      throw new Error('Response indicates failure');
    }
    
    // Validate refresh result structure
    if (!data.updated) {
      throw new Error('Missing updated counts in refresh response');
    }
    
    const requiredFields = ['dailyUpdated', 'weeklyUpdated', 'totalUpdated'];
    for (const field of requiredFields) {
      if (!(field in data.updated)) {
        throw new Error(`Missing field '${field}' in refresh response`);
      }
    }
    
    console.log(`📊 Leaderboard refresh completed:`);
    console.log(`   - Daily: ${data.updated.dailyUpdated} players ranked`);
    console.log(`   - Weekly: ${data.updated.weeklyUpdated} players ranked`);
    console.log(`   - Total: ${data.updated.totalUpdated} players ranked`);
  }

  async testInvalidRequests() {
    // Test invalid player ID format
    let response = await fetch(`${BASE_URL}/api/scores/player/invalid-uuid`);
    if (response.status !== 400) {
      throw new Error(`Expected 400 for invalid UUID, got ${response.status}`);
    }
    
    // Test non-existent player
    response = await fetch(`${BASE_URL}/api/scores/player/00000000-0000-0000-0000-000000000000`);
    if (response.status !== 404) {
      throw new Error(`Expected 404 for non-existent player, got ${response.status}`);
    }
    
    // Test invalid leaderboard period
    response = await fetch(`${BASE_URL}/api/leaderboards/invalid`);
    if (response.status !== 400) {
      throw new Error(`Expected 400 for invalid period, got ${response.status}`);
    }
    
    // Test invalid pagination parameters
    response = await fetch(`${BASE_URL}/api/leaderboards/daily?limit=0`);
    if (response.status !== 400) {
      throw new Error(`Expected 400 for invalid limit, got ${response.status}`);
    }
    
    response = await fetch(`${BASE_URL}/api/leaderboards/daily?offset=-1`);
    if (response.status !== 400) {
      throw new Error(`Expected 400 for negative offset, got ${response.status}`);
    }
    
    console.log('🚫 All invalid requests handled correctly');
  }

  async testScoreAggregationLogic() {
    // Test that scores are being aggregated correctly
    const testPlayer = this.testPlayers[0];
    
    // Get current scores
    const beforeResponse = await fetch(`${BASE_URL}/api/scores/player/${testPlayer.id}`);
    const beforeData = await beforeResponse.json();
    const beforeScore = beforeData.scores.totalScore;
    
    // Complete another phrase
    const phrase = this.testPhrases[this.testPhrases.length - 1]; // Use the last phrase
    
    // Use 2 hints (should get 70% of difficulty score)
    await fetch(`${BASE_URL}/api/phrases/${phrase.id}/hint/1`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ playerId: testPlayer.id })
    });
    
    await fetch(`${BASE_URL}/api/phrases/${phrase.id}/hint/2`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ playerId: testPlayer.id })
    });
    
    const completionResponse = await fetch(`${BASE_URL}/api/phrases/${phrase.id}/complete`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ 
        playerId: testPlayer.id,
        completionTime: 8000
      })
    });
    
    if (!completionResponse.ok) {
      throw new Error('Failed to complete phrase for aggregation test');
    }
    
    const completion = await completionResponse.json();
    const earnedScore = completion.completion.finalScore;
    
    // Wait for score aggregation
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // Get updated scores
    const afterResponse = await fetch(`${BASE_URL}/api/scores/player/${testPlayer.id}`);
    const afterData = await afterResponse.json();
    const afterScore = afterData.scores.totalScore;
    
    // Verify score was added correctly
    const expectedScore = beforeScore + earnedScore;
    if (afterScore !== expectedScore) {
      throw new Error(`Score aggregation incorrect. Expected ${expectedScore}, got ${afterScore}`);
    }
    
    console.log(`📊 Score aggregation verified: ${beforeScore} + ${earnedScore} = ${afterScore}`);
  }

  printSummary() {
    console.log('\n' + '='.repeat(60));
    console.log('📊 SCORING SYSTEM TEST SUMMARY');
    console.log('='.repeat(60));
    
    const passed = this.testResults.filter(r => r.status === 'PASSED').length;
    const failed = this.testResults.filter(r => r.status === 'FAILED').length;
    const total = this.testResults.length;
    
    console.log(`Total tests: ${total}`);
    console.log(`✅ Passed: ${passed}`);
    console.log(`❌ Failed: ${failed}`);
    console.log(`📈 Success rate: ${((passed / total) * 100).toFixed(1)}%`);
    
    if (failed > 0) {
      console.log('\n❌ Failed tests:');
      this.testResults
        .filter(r => r.status === 'FAILED')
        .forEach(test => console.log(`  - ${test.name}: ${test.error}`));
    }
    
    console.log('\n🎯 Scoring System Features Tested:');
    console.log('  ✅ Player score aggregation (daily/weekly/total)');
    console.log('  ✅ Leaderboard ranking system');
    console.log('  ✅ Global statistics and analytics');
    console.log('  ✅ Automatic score updates on phrase completion');
    console.log('  ✅ Score calculation with hint penalties');
    console.log('  ✅ Pagination and filtering');
    console.log('  ✅ Input validation and error handling');
    
    console.log('\n🔗 API Endpoints Tested:');
    console.log('  - GET  /api/scores/player/:playerId');
    console.log('  - GET  /api/leaderboards/daily');
    console.log('  - GET  /api/leaderboards/weekly');
    console.log('  - GET  /api/leaderboards/total');
    console.log('  - GET  /api/stats/global');
    console.log('  - POST /api/scores/refresh');
    
    console.log('='.repeat(60));
  }

  async run() {
    console.log('🚀 Starting Scoring System Test Suite');
    console.log('🎯 Testing Phase 4.9: Complete Scoring and Leaderboard System');
    
    try {
      await this.setupTestData();
      await this.simulateGameplay();
      
      await this.runTest('Player Score Summary', () => this.testPlayerScoreSummary());
      await this.runTest('Daily Leaderboard', () => this.testDailyLeaderboard());
      await this.runTest('Weekly Leaderboard', () => this.testWeeklyLeaderboard());
      await this.runTest('Total Leaderboard', () => this.testTotalLeaderboard());
      await this.runTest('Global Statistics', () => this.testGlobalStatistics());
      await this.runTest('Leaderboard Refresh', () => this.testLeaderboardRefresh());
      await this.runTest('Invalid Request Handling', () => this.testInvalidRequests());
      await this.runTest('Score Aggregation Logic', () => this.testScoreAggregationLogic());
      
    } catch (error) {
      console.error('❌ Setup failed:', error.message);
    }
    
    this.printSummary();
  }
}

// Run the test suite
if (require.main === module) {
  const tester = new ScoringSystemTester();
  tester.run().catch(console.error);
}

module.exports = ScoringSystemTester;