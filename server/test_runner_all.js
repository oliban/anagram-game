#!/usr/bin/env node

/**
 * Complete Test Runner
 * 
 * Runs both basic API tests and comprehensive coverage tests
 * Provides detailed reporting and coverage analysis
 * 
 * Usage: node test_runner_all.js [--basic-only] [--comprehensive-only]
 */

const APITestSuite = require('./test_api_suite');
const ComprehensiveTestSuite = require('./test_comprehensive_suite');
const Phase4EnhancedCreationTests = require('./test_phase4_enhanced_creation');
const Phase4GlobalPhrasesTests = require('./test_phase4_global_phrases');

class TestRunner {
  constructor() {
    this.results = {
      basic: null,
      comprehensive: null,
      phase4Enhanced: null,
      phase4Global: null,
      combined: {
        passed: 0,
        failed: 0,
        skipped: 0,
        total: 0
      }
    };
  }

  log(message, level = 'info') {
    const timestamp = new Date().toISOString();
    const prefix = level === 'error' ? '❌' : level === 'success' ? '✅' : level === 'warn' ? '⚠️' : 'ℹ️';
    console.log(`[${timestamp}] ${prefix} ${message}`);
  }

  async checkServerHealth() {
    this.log('Checking server health before running tests...');
    
    try {
      const axios = require('axios');
      const response = await axios.get('http://localhost:3000/api/status', { timeout: 5000 });
      
      if (response.status === 200 && response.data.status === 'online') {
        this.log('✅ Server is healthy and ready for testing', 'success');
        return true;
      } else {
        this.log('❌ Server is not responding correctly', 'error');
        return false;
      }
    } catch (error) {
      this.log(`❌ Server health check failed: ${error.message}`, 'error');
      this.log('Make sure the server is running: node server.js');
      return false;
    }
  }

  async runBasicTests() {
    this.log('\n🧪 Running Basic API Test Suite...');
    this.log('================================================');
    
    const basicSuite = new APITestSuite();
    try {
      const success = await basicSuite.runAllTests();
      this.results.basic = {
        success,
        passed: basicSuite.results.passed,
        failed: basicSuite.results.failed,
        skipped: basicSuite.results.skipped,
        total: basicSuite.results.passed + basicSuite.results.failed + basicSuite.results.skipped
      };
      
      await basicSuite.cleanup();
      return success;
    } catch (error) {
      this.log(`❌ Basic test suite failed: ${error.message}`, 'error');
      this.results.basic = { success: false, passed: 0, failed: 1, skipped: 0, total: 1 };
      return false;
    }
  }

  async runComprehensiveTests() {
    this.log('\n🔬 Running Comprehensive Test Suite...');
    this.log('================================================');
    
    const comprehensiveSuite = new ComprehensiveTestSuite();
    try {
      const success = await comprehensiveSuite.runAllTests();
      this.results.comprehensive = {
        success,
        passed: comprehensiveSuite.results.passed,
        failed: comprehensiveSuite.results.failed,
        skipped: comprehensiveSuite.results.skipped,
        total: comprehensiveSuite.results.passed + comprehensiveSuite.results.failed + comprehensiveSuite.results.skipped
      };
      
      await comprehensiveSuite.cleanup();
      return success;
    } catch (error) {
      this.log(`❌ Comprehensive test suite failed: ${error.message}`, 'error');
      this.results.comprehensive = { success: false, passed: 0, failed: 1, skipped: 0, total: 1 };
      return false;
    }
  }

  async runPhase4EnhancedTests() {
    this.log('\n🎯 Running Phase 4.1 Enhanced Creation Tests...');
    this.log('================================================');
    
    const phase4Suite = new Phase4EnhancedCreationTests();
    try {
      const success = await phase4Suite.runAllTests();
      this.results.phase4Enhanced = {
        success,
        passed: phase4Suite.results.passed,
        failed: phase4Suite.results.failed,
        skipped: phase4Suite.results.skipped,
        total: phase4Suite.results.passed + phase4Suite.results.failed + phase4Suite.results.skipped
      };
      
      await phase4Suite.cleanup();
      return success;
    } catch (error) {
      this.log(`❌ Phase 4.1 enhanced creation tests failed: ${error.message}`, 'error');
      this.results.phase4Enhanced = { success: false, passed: 0, failed: 1, skipped: 0, total: 1 };
      return false;
    }
  }

  async runPhase4GlobalTests() {
    this.log('\n🌍 Running Phase 4.2 Global Phrase Bank Tests...');
    this.log('================================================');
    
    const globalSuite = new Phase4GlobalPhrasesTests();
    try {
      const success = await globalSuite.runAllTests();
      this.results.phase4Global = {
        success,
        passed: globalSuite.results.passed,
        failed: globalSuite.results.failed,
        skipped: globalSuite.results.skipped,
        total: globalSuite.results.passed + globalSuite.results.failed + globalSuite.results.skipped
      };
      
      await globalSuite.cleanup();
      return success;
    } catch (error) {
      this.log(`❌ Phase 4.2 global phrase tests failed: ${error.message}`, 'error');
      this.results.phase4Global = { success: false, passed: 0, failed: 1, skipped: 0, total: 1 };
      return false;
    }
  }

  generateReport() {
    this.log('\n📊 COMPLETE TEST REPORT');
    this.log('========================');
    
    // Calculate combined results
    if (this.results.basic) {
      this.results.combined.passed += this.results.basic.passed;
      this.results.combined.failed += this.results.basic.failed;
      this.results.combined.skipped += this.results.basic.skipped;
      this.results.combined.total += this.results.basic.total;
    }
    
    if (this.results.comprehensive) {
      this.results.combined.passed += this.results.comprehensive.passed;
      this.results.combined.failed += this.results.comprehensive.failed;
      this.results.combined.skipped += this.results.comprehensive.skipped;
      this.results.combined.total += this.results.comprehensive.total;
    }

    if (this.results.phase4Enhanced) {
      this.results.combined.passed += this.results.phase4Enhanced.passed;
      this.results.combined.failed += this.results.phase4Enhanced.failed;
      this.results.combined.skipped += this.results.phase4Enhanced.skipped;
      this.results.combined.total += this.results.phase4Enhanced.total;
    }

    if (this.results.phase4Global) {
      this.results.combined.passed += this.results.phase4Global.passed;
      this.results.combined.failed += this.results.phase4Global.failed;
      this.results.combined.skipped += this.results.phase4Global.skipped;
      this.results.combined.total += this.results.phase4Global.total;
    }

    // Test suite summaries
    if (this.results.basic) {
      this.log(`\n📋 Basic API Tests:`);
      this.log(`   ✅ Passed: ${this.results.basic.passed}`);
      this.log(`   ❌ Failed: ${this.results.basic.failed}`);
      this.log(`   ⏭️ Skipped: ${this.results.basic.skipped}`);
      this.log(`   🎯 Total: ${this.results.basic.total}`);
      this.log(`   📈 Success Rate: ${Math.round((this.results.basic.passed / this.results.basic.total) * 100)}%`);
    }

    if (this.results.comprehensive) {
      this.log(`\n🔬 Comprehensive Tests:`);
      this.log(`   ✅ Passed: ${this.results.comprehensive.passed}`);
      this.log(`   ❌ Failed: ${this.results.comprehensive.failed}`);
      this.log(`   ⏭️ Skipped: ${this.results.comprehensive.skipped}`);
      this.log(`   🎯 Total: ${this.results.comprehensive.total}`);
      this.log(`   📈 Success Rate: ${Math.round((this.results.comprehensive.passed / this.results.comprehensive.total) * 100)}%`);
    }

    if (this.results.phase4Enhanced) {
      this.log(`\n🎯 Phase 4.1 Enhanced Creation Tests:`);
      this.log(`   ✅ Passed: ${this.results.phase4Enhanced.passed}`);
      this.log(`   ❌ Failed: ${this.results.phase4Enhanced.failed}`);
      this.log(`   ⏭️ Skipped: ${this.results.phase4Enhanced.skipped}`);
      this.log(`   🎯 Total: ${this.results.phase4Enhanced.total}`);
      this.log(`   📈 Success Rate: ${Math.round((this.results.phase4Enhanced.passed / this.results.phase4Enhanced.total) * 100)}%`);
    }

    if (this.results.phase4Global) {
      this.log(`\n🌍 Phase 4.2 Global Phrase Bank Tests:`);
      this.log(`   ✅ Passed: ${this.results.phase4Global.passed}`);
      this.log(`   ❌ Failed: ${this.results.phase4Global.failed}`);
      this.log(`   ⏭️ Skipped: ${this.results.phase4Global.skipped}`);
      this.log(`   🎯 Total: ${this.results.phase4Global.total}`);
      this.log(`   📈 Success Rate: ${Math.round((this.results.phase4Global.passed / this.results.phase4Global.total) * 100)}%`);
    }

    // Combined summary
    this.log(`\n🎯 COMBINED RESULTS:`);
    this.log(`   ✅ Total Passed: ${this.results.combined.passed}`);
    this.log(`   ❌ Total Failed: ${this.results.combined.failed}`);
    this.log(`   ⏭️ Total Skipped: ${this.results.combined.skipped}`);
    this.log(`   🎯 Grand Total: ${this.results.combined.total}`);
    
    const overallSuccessRate = this.results.combined.total > 0 ? 
      Math.round((this.results.combined.passed / this.results.combined.total) * 100) : 0;
    this.log(`   📈 Overall Success Rate: ${overallSuccessRate}%`);

    // Coverage assessment
    this.log(`\n📈 COVERAGE ASSESSMENT:`);
    if (overallSuccessRate >= 90) {
      this.log('   🚀 EXCELLENT - Production ready!');
    } else if (overallSuccessRate >= 75) {
      this.log('   🎯 GOOD - Minor issues to address');
    } else if (overallSuccessRate >= 50) {
      this.log('   ⚠️ MODERATE - Significant gaps remain');
    } else {
      this.log('   🚨 POOR - Major implementation needed');
    }

    // Recommendations
    this.log(`\n💡 RECOMMENDATIONS:`);
    
    if (this.results.basic && this.results.basic.failed > 0) {
      this.log('   • Fix basic API functionality issues first');
    }
    
    if (this.results.comprehensive && this.results.comprehensive.failed > 0) {
      this.log('   • Address advanced features and edge cases');
    }
    
    if (overallSuccessRate < 80) {
      this.log('   • Focus on core functionality before Phase 3 migration');
    }
    
    if (this.results.comprehensive && this.results.comprehensive.failed > this.results.comprehensive.passed) {
      this.log('   • Many advanced features are missing - implement gradually');
    }

    // Phase 3 readiness
    const basicReady = this.results.basic ? this.results.basic.success : false;
    const phase3Ready = basicReady && overallSuccessRate >= 70;
    
    this.log(`\n🚀 PHASE 3 MIGRATION READINESS:`);
    if (phase3Ready) {
      this.log('   ✅ READY - Basic functionality is solid, proceed with migration');
    } else if (basicReady) {
      this.log('   ⚠️ CAUTIOUS - Basic tests pass but comprehensive gaps exist');
    } else {
      this.log('   ❌ NOT READY - Fix basic API issues before migration');
    }

    return {
      overallSuccess: this.results.combined.failed === 0,
      successRate: overallSuccessRate,
      phase3Ready,
      recommendations: this.generateRecommendations()
    };
  }

  generateRecommendations() {
    const recommendations = [];
    
    if (this.results.basic && this.results.basic.failed > 0) {
      recommendations.push('Fix basic API functionality');
    }
    
    if (this.results.comprehensive) {
      const failureRate = (this.results.comprehensive.failed / this.results.comprehensive.total) * 100;
      if (failureRate > 50) {
        recommendations.push('Implement missing advanced features gradually');
      }
    }
    
    const overallRate = (this.results.combined.passed / this.results.combined.total) * 100;
    if (overallRate < 80) {
      recommendations.push('Focus on core functionality before advanced features');
    }
    
    return recommendations;
  }

  async run() {
    const args = process.argv.slice(2);
    const basicOnly = args.includes('--basic-only');
    const comprehensiveOnly = args.includes('--comprehensive-only');
    
    this.log('🚀 Starting Complete Test Runner...');
    
    // Check server health
    const serverHealthy = await this.checkServerHealth();
    if (!serverHealthy) {
      process.exit(1);
    }

    let overallSuccess = true;

    // Run basic tests unless comprehensive-only
    if (!comprehensiveOnly) {
      const basicSuccess = await this.runBasicTests();
      overallSuccess = overallSuccess && basicSuccess;
    }

    // Run comprehensive tests unless basic-only  
    if (!basicOnly) {
      const comprehensiveSuccess = await this.runComprehensiveTests();
      overallSuccess = overallSuccess && comprehensiveSuccess;
    }

    // Run Phase 4 tests (always run unless basic-only)
    if (!basicOnly) {
      const phase4EnhancedSuccess = await this.runPhase4EnhancedTests();
      overallSuccess = overallSuccess && phase4EnhancedSuccess;
      
      const phase4GlobalSuccess = await this.runPhase4GlobalTests();
      overallSuccess = overallSuccess && phase4GlobalSuccess;
    }

    // Generate final report
    const report = this.generateReport();
    
    // Exit with appropriate code
    this.log(`\n🎉 Test Runner Complete: ${overallSuccess ? 'SUCCESS' : 'SOME FAILURES'}`);
    process.exit(overallSuccess ? 0 : 1);
  }
}

// Run if executed directly
if (require.main === module) {
  const runner = new TestRunner();
  runner.run().catch(error => {
    console.error('❌ Test runner failed:', error);
    process.exit(1);
  });
}

module.exports = TestRunner;