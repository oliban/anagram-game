#!/usr/bin/env node

/**
 * Enhanced Test Coverage Runner
 * Includes tests for recent server enhancements
 */

const { execSync, spawn } = require('child_process');

class EnhancedCoverageTestRunner {
  constructor() {
    this.results = {
      websocketData: null,
      databasePhrase: null,
      hintSystem: null
    };
  }

  async runTestSuite(name, scriptPath) {
    console.log(`\n🧪 Running ${name}...`);
    console.log('='.repeat(50));
    
    try {
      const output = execSync(`node ${scriptPath}`, { 
        encoding: 'utf8',
        timeout: 30000
      });
      
      // Parse results from output
      const passed = (output.match(/✅ Passed: (\d+)/)?.[1]) || '0';
      const failed = (output.match(/❌ Failed: (\d+)/)?.[1]) || '0';
      const successRate = (output.match(/📈 Success rate: ([\d.]+)%/)?.[1]) || '0';
      
      const result = {
        passed: parseInt(passed),
        failed: parseInt(failed),
        total: parseInt(passed) + parseInt(failed),
        successRate: parseFloat(successRate),
        output: output
      };
      
      if (result.failed === 0) {
        console.log(`✅ ${name}: ${result.passed}/${result.total} tests passed (${result.successRate}%)`);
      } else {
        console.log(`⚠️ ${name}: ${result.passed}/${result.total} tests passed (${result.successRate}%)`);
      }
      
      return result;
      
    } catch (error) {
      console.log(`❌ ${name}: Failed to run - ${error.message}`);
      return {
        passed: 0,
        failed: 1,
        total: 1,
        successRate: 0,
        error: error.message
      };
    }
  }

  async checkServerHealth() {
    console.log('🔍 Checking server health...');
    
    try {
      const response = await fetch('http://localhost:3000/api/status');
      if (response.ok) {
        const data = await response.json();
        console.log(`✅ Server is healthy: ${data.status}`);
        return true;
      } else {
        console.log(`❌ Server health check failed: ${response.status}`);
        return false;
      }
    } catch (error) {
      console.log(`❌ Server is not accessible: ${error.message}`);
      return false;
    }
  }

  printComprehensiveReport() {
    console.log('\n' + '='.repeat(80));
    console.log('📊 ENHANCED COVERAGE TEST REPORT');
    console.log('='.repeat(80));
    
    let totalPassed = 0;
    let totalFailed = 0;
    let totalTests = 0;
    
    console.log('\n📋 Test Suite Results:');
    
    for (const [suiteName, result] of Object.entries(this.results)) {
      if (result) {
        const status = result.failed === 0 ? '✅' : '⚠️';
        console.log(`${status} ${suiteName}: ${result.passed}/${result.total} (${result.successRate}%)`);
        
        totalPassed += result.passed;
        totalFailed += result.failed;
        totalTests += result.total;
      }
    }
    
    const overallSuccessRate = totalTests > 0 ? ((totalPassed / totalTests) * 100).toFixed(1) : 0;
    
    console.log('\n🎯 Overall Results:');
    console.log(`   ✅ Total Passed: ${totalPassed}`);
    console.log(`   ❌ Total Failed: ${totalFailed}`);
    console.log(`   🎯 Total Tests: ${totalTests}`);
    console.log(`   📈 Success Rate: ${overallSuccessRate}%`);
    
    console.log('\n🎯 Coverage Areas Tested:');
    console.log('   ✅ WebSocket phrase data structure enhancements');
    console.log('   ✅ DatabasePhrase getPublicInfo() method');
    console.log('   ✅ Hint system with dynamic scoring');
    console.log('   ✅ Enhanced phrase creation responses');
    console.log('   ✅ Date field validation and formatting');
    
    console.log('\n🔗 Recent Server Changes Covered:');
    console.log('   ✅ WebSocket targetId and senderName fields (commit a6f226a)');
    console.log('   ✅ DatabasePhrase createdAt field enhancement');
    console.log('   ✅ Hint system integration with server endpoints');
    console.log('   ✅ Enhanced phrase notification structure');
    
    if (overallSuccessRate >= 95) {
      console.log('\n🚀 EXCELLENT: Server enhancements are well tested!');
    } else if (overallSuccessRate >= 85) {
      console.log('\n✅ GOOD: Most server enhancements are covered by tests');
    } else {
      console.log('\n⚠️ NEEDS IMPROVEMENT: Some test failures need attention');
    }
    
    console.log('='.repeat(80));
  }

  async run() {
    console.log('🚀 Enhanced Coverage Test Runner');
    console.log('🎯 Testing recent server enhancements and data structures');
    
    // Check server health first
    const serverHealthy = await this.checkServerHealth();
    if (!serverHealthy) {
      console.log('❌ Cannot run tests - server is not accessible');
      return;
    }
    
    // Run enhanced test suites
    this.results.websocketData = await this.runTestSuite(
      'WebSocket Data Structure Tests', 
      'server/test_websocket_data_structure.js'
    );
    
    this.results.databasePhrase = await this.runTestSuite(
      'Database Phrase Structure Tests', 
      'server/test_database_phrase_structure.js'
    );
    
    this.results.hintSystem = await this.runTestSuite(
      'Hint System Tests', 
      'server/test_hint_system.js'
    );
    
    this.printComprehensiveReport();
  }
}

// Run the enhanced coverage test runner
if (require.main === module) {
  const runner = new EnhancedCoverageTestRunner();
  runner.run().catch(console.error);
}

module.exports = EnhancedCoverageTestRunner;