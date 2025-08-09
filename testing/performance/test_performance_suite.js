#!/usr/bin/env node

/**
 * Performance and Load Testing Suite
 * Tests API response times, concurrent user loads, and resource usage
 */

const http = require('http');
const cluster = require('cluster');
const os = require('os');

const API_URL = process.env.API_URL || 'http://192.168.1.188:3000';
const [HOST, PORT] = API_URL.replace('http://', '').split(':');

console.log(`🚀 Performance Testing Suite`);
console.log(`📡 Target Server: ${API_URL}`);

class PerformanceTest {
  constructor() {
    this.results = {
      responseTime: {},
      throughput: {},
      concurrency: {},
      stability: {}
    };
  }

  log(category, message, details = '') {
    const timestamp = new Date().toISOString().substring(11, 23);
    console.log(`⚡ [${timestamp}] ${category}: ${message} ${details}`);
  }

  async makeRequest(method, path, data = null, timeout = 10000) {
    const startTime = Date.now();
    
    return new Promise((resolve) => {
      const options = {
        hostname: HOST,
        port: PORT || 80,
        path: path,
        method: method,
        headers: { 'Content-Type': 'application/json' },
        timeout: timeout
      };

      const req = http.request(options, (res) => {
        let body = '';
        res.on('data', chunk => body += chunk);
        res.on('end', () => {
          const endTime = Date.now();
          try {
            const parsed = body ? JSON.parse(body) : {};
            resolve({
              status: res.statusCode,
              data: parsed,
              responseTime: endTime - startTime,
              success: res.statusCode >= 200 && res.statusCode < 300
            });
          } catch (e) {
            resolve({
              status: res.statusCode,
              data: body,
              responseTime: endTime - startTime,
              success: false,
              error: 'Invalid JSON'
            });
          }
        });
      });

      req.on('error', err => resolve({ 
        success: false, 
        error: err.message, 
        responseTime: Date.now() - startTime 
      }));
      
      req.on('timeout', () => resolve({ 
        success: false, 
        error: 'Timeout', 
        responseTime: timeout 
      }));

      if (data) req.write(JSON.stringify(data));
      req.end();
    });
  }

  async testResponseTimes() {
    console.log('\n📊 Testing API Response Times');
    
    const endpoints = [
      { name: 'Health Check', method: 'GET', path: '/api/status', target: 50 },
      { name: 'Global Stats', method: 'GET', path: '/api/stats', target: 200 },
      { name: 'Leaderboard', method: 'GET', path: '/api/leaderboard/total', target: 300 },
      { name: 'Legends List', method: 'GET', path: '/api/players/legends', target: 400 },
      { name: 'Skill Levels', method: 'GET', path: '/api/config/levels', target: 100 }
    ];

    for (const endpoint of endpoints) {
      const results = [];
      
      // Test each endpoint 5 times
      for (let i = 0; i < 5; i++) {
        const result = await this.makeRequest(endpoint.method, endpoint.path);
        if (result.success) {
          results.push(result.responseTime);
        }
      }
      
      if (results.length > 0) {
        const avgTime = Math.round(results.reduce((a, b) => a + b) / results.length);
        const minTime = Math.min(...results);
        const maxTime = Math.max(...results);
        
        const status = avgTime <= endpoint.target ? '✅' : '⚠️';
        this.log('RESPONSE', `${endpoint.name}`, `Avg: ${avgTime}ms (${minTime}-${maxTime}ms) Target: ${endpoint.target}ms ${status}`);
        
        this.results.responseTime[endpoint.name] = {
          average: avgTime,
          min: minTime,
          max: maxTime,
          target: endpoint.target,
          passed: avgTime <= endpoint.target
        };
      } else {
        this.log('RESPONSE', `${endpoint.name}`, '❌ All requests failed');
        this.results.responseTime[endpoint.name] = { passed: false };
      }
    }
  }

  async testConcurrentUsers() {
    console.log('\n👥 Testing Concurrent User Load');
    
    const concurrencyLevels = [5, 10, 20, 50];
    
    for (const level of concurrencyLevels) {
      console.log(`\n🔄 Testing ${level} concurrent users...`);
      
      const promises = [];
      const startTime = Date.now();
      
      // Create concurrent requests
      for (let i = 0; i < level; i++) {
        promises.push(this.makeRequest('GET', '/api/status'));
      }
      
      try {
        const results = await Promise.all(promises);
        const totalTime = Date.now() - startTime;
        
        const successful = results.filter(r => r.success).length;
        const failed = results.length - successful;
        const avgResponseTime = successful > 0 ? 
          Math.round(results.filter(r => r.success).reduce((sum, r) => sum + r.responseTime, 0) / successful) : 0;
        
        const throughput = Math.round((successful * 1000) / totalTime); // requests per second
        
        this.log('CONCURRENCY', `${level} users`, `Success: ${successful}/${level}, Avg: ${avgResponseTime}ms, Throughput: ${throughput} req/s`);
        
        this.results.concurrency[level] = {
          successful,
          failed,
          avgResponseTime,
          throughput,
          totalTime
        };
        
      } catch (error) {
        this.log('CONCURRENCY', `${level} users`, `❌ Error: ${error.message}`);
        this.results.concurrency[level] = { error: error.message };
      }
      
      // Wait between tests to avoid overwhelming server
      await new Promise(resolve => setTimeout(resolve, 2000));
    }
  }

  async testThroughput() {
    console.log('\n🏎️ Testing API Throughput');
    
    const testDuration = 10000; // 10 seconds
    const startTime = Date.now();
    let requestCount = 0;
    let successCount = 0;
    let totalResponseTime = 0;
    
    console.log(`Running throughput test for ${testDuration / 1000} seconds...`);
    
    while (Date.now() - startTime < testDuration) {
      const result = await this.makeRequest('GET', '/api/status');
      requestCount++;
      
      if (result.success) {
        successCount++;
        totalResponseTime += result.responseTime;
      }
      
      // Brief pause to avoid overwhelming server
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    
    const actualDuration = Date.now() - startTime;
    const requestsPerSecond = Math.round((requestCount * 1000) / actualDuration);
    const successRate = Math.round((successCount / requestCount) * 100);
    const avgResponseTime = successCount > 0 ? Math.round(totalResponseTime / successCount) : 0;
    
    this.log('THROUGHPUT', 'Health Check Endpoint', `${requestsPerSecond} req/s, ${successRate}% success, ${avgResponseTime}ms avg response`);
    
    this.results.throughput = {
      requestsPerSecond,
      successRate,
      avgResponseTime,
      totalRequests: requestCount,
      duration: actualDuration
    };
  }

  async testStabilityUnderLoad() {
    console.log('\n🎯 Testing Stability Under Load');
    
    const testDuration = 30000; // 30 seconds
    const concurrentUsers = 10;
    
    console.log(`Running stability test: ${concurrentUsers} users for ${testDuration / 1000} seconds...`);
    
    const workers = [];
    const results = { success: 0, failed: 0, errors: [] };
    
    const workerTask = async () => {
      const startTime = Date.now();
      let userRequests = 0;
      let userErrors = 0;
      
      while (Date.now() - startTime < testDuration) {
        try {
          const result = await this.makeRequest('GET', '/api/status');
          userRequests++;
          
          if (!result.success) {
            userErrors++;
          }
        } catch (error) {
          userErrors++;
          if (results.errors.length < 5) { // Limit error logging
            results.errors.push(error.message);
          }
        }
        
        // Random delay between requests (50-200ms)
        await new Promise(resolve => setTimeout(resolve, 50 + Math.random() * 150));
      }
      
      return { requests: userRequests, errors: userErrors };
    };
    
    // Start concurrent workers
    for (let i = 0; i < concurrentUsers; i++) {
      workers.push(workerTask());
    }
    
    try {
      const workerResults = await Promise.all(workers);
      
      const totalRequests = workerResults.reduce((sum, r) => sum + r.requests, 0);
      const totalErrors = workerResults.reduce((sum, r) => sum + r.errors, 0);
      const successRate = Math.round(((totalRequests - totalErrors) / totalRequests) * 100);
      
      this.log('STABILITY', 'Load Test Complete', `${totalRequests} total requests, ${successRate}% success rate`);
      
      this.results.stability = {
        totalRequests,
        totalErrors,
        successRate,
        duration: testDuration,
        concurrentUsers
      };
      
    } catch (error) {
      this.log('STABILITY', 'Test Failed', `❌ ${error.message}`);
      this.results.stability = { error: error.message };
    }
  }

  async testDatabasePerformance() {
    console.log('\n🗄️ Testing Database-Heavy Operations');
    
    // Create a test player first
    const playerResult = await this.makeRequest('POST', '/api/players/register', {
      name: `PerfTest${Date.now()}`,
      language: 'en',
      deviceId: `perf-test-${Date.now()}-${Math.random()}`
    });
    
    if (!playerResult.success) {
      this.log('DATABASE', 'Setup Failed', '❌ Could not create test player');
      return;
    }
    
    const playerId = playerResult.data.player.id;
    
    const dbTests = [
      {
        name: 'Get Player Phrases',
        method: 'GET',
        path: `/api/phrases/for/${playerId}`,
        target: 500
      },
      {
        name: 'Create Phrase',
        method: 'POST',
        path: '/api/phrases/create',
        data: {
          content: 'performance test phrase',
          language: 'en',
          senderId: playerId,
          hint: 'performance testing'
        },
        target: 300
      },
      {
        name: 'Analyze Difficulty',
        method: 'POST',
        path: '/api/phrases/analyze-difficulty',
        data: {
          phrase: 'complex performance testing phrase',
          language: 'en'
        },
        target: 200
      }
    ];
    
    for (const test of dbTests) {
      const results = [];
      
      // Run each test 3 times
      for (let i = 0; i < 3; i++) {
        const result = await this.makeRequest(test.method, test.path, test.data);
        if (result.success) {
          results.push(result.responseTime);
        }
        await new Promise(resolve => setTimeout(resolve, 100)); // Brief pause
      }
      
      if (results.length > 0) {
        const avgTime = Math.round(results.reduce((a, b) => a + b) / results.length);
        const status = avgTime <= test.target ? '✅' : '⚠️';
        
        this.log('DATABASE', test.name, `Avg: ${avgTime}ms Target: ${test.target}ms ${status}`);
      } else {
        this.log('DATABASE', test.name, '❌ All requests failed');
      }
    }
  }

  generateReport() {
    console.log('\n📋 PERFORMANCE TEST REPORT');
    console.log('='.repeat(60));
    
    // Response Times Summary
    console.log('\n📊 Response Time Results:');
    Object.entries(this.results.responseTime).forEach(([name, result]) => {
      if (result.passed !== undefined) {
        const status = result.passed ? '✅' : '⚠️';
        console.log(`  ${status} ${name}: ${result.average || 'N/A'}ms (target: ${result.target}ms)`);
      }
    });
    
    // Concurrency Results
    console.log('\n👥 Concurrency Results:');
    Object.entries(this.results.concurrency).forEach(([level, result]) => {
      if (result.throughput) {
        console.log(`  • ${level} users: ${result.throughput} req/s (${result.successful}/${level} success)`);
      }
    });
    
    // Throughput Results
    if (this.results.throughput.requestsPerSecond) {
      console.log(`\n🏎️ Throughput: ${this.results.throughput.requestsPerSecond} req/s (${this.results.throughput.successRate}% success)`);
    }
    
    // Stability Results
    if (this.results.stability.successRate) {
      console.log(`\n🎯 Stability: ${this.results.stability.successRate}% success rate over ${this.results.stability.duration/1000}s`);
    }
    
    console.log(`\n🕒 Test completed: ${new Date().toISOString()}`);
    
    // Overall Performance Assessment
    const responseTimePassed = Object.values(this.results.responseTime).filter(r => r.passed).length;
    const responseTimeTotal = Object.keys(this.results.responseTime).length;
    const stabilityGood = this.results.stability.successRate >= 95;
    
    console.log('\n🎖️ OVERALL ASSESSMENT:');
    if (responseTimePassed === responseTimeTotal && stabilityGood) {
      console.log('✅ EXCELLENT - All performance targets met');
    } else if (responseTimePassed >= responseTimeTotal * 0.8 && this.results.stability.successRate >= 90) {
      console.log('⚠️ GOOD - Most targets met, minor optimizations needed');
    } else {
      console.log('❌ NEEDS ATTENTION - Performance issues detected');
    }
  }

  async runAllTests() {
    console.log('🚀 Starting Performance Test Suite');
    console.log(`📅 ${new Date().toISOString()}\n`);

    try {
      await this.testResponseTimes();
      await this.testConcurrentUsers();
      await this.testThroughput();
      await this.testStabilityUnderLoad();
      await this.testDatabasePerformance();
    } catch (error) {
      console.error('❌ Test suite error:', error.message);
    }

    this.generateReport();
  }
}

// Run tests
if (require.main === module) {
  const tester = new PerformanceTest();
  tester.runAllTests().catch(error => {
    console.error('💥 Performance test suite crashed:', error);
    process.exit(1);
  });
}

module.exports = PerformanceTest;