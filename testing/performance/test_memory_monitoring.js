#!/usr/bin/env node

/**
 * Memory and Resource Monitoring Test
 * Monitors server resource usage during various operations
 */

const http = require('http');

const API_URL = process.env.API_URL || 'http://192.168.1.188:3000';
const [HOST, PORT] = API_URL.replace('http://', '').split(':');

console.log(`🧠 Memory Monitoring Test Suite`);
console.log(`📡 Target Server: ${API_URL}`);

class MemoryMonitoringTest {
  constructor() {
    this.baseline = null;
    this.measurements = [];
  }

  log(message, details = '') {
    const timestamp = new Date().toISOString().substring(11, 23);
    console.log(`🧠 [${timestamp}] ${message} ${details}`);
  }

  async makeRequest(method, path, data = null) {
    return new Promise((resolve) => {
      const options = {
        hostname: HOST,
        port: PORT || 80,
        path: path,
        method: method,
        headers: { 'Content-Type': 'application/json' },
        timeout: 10000
      };

      const req = http.request(options, (res) => {
        let body = '';
        res.on('data', chunk => body += chunk);
        res.on('end', () => {
          try {
            const parsed = body ? JSON.parse(body) : {};
            resolve({
              status: res.statusCode,
              data: parsed,
              success: res.statusCode >= 200 && res.statusCode < 300
            });
          } catch (e) {
            resolve({
              status: res.statusCode,
              data: body,
              success: false
            });
          }
        });
      });

      req.on('error', err => resolve({ success: false, error: err.message }));
      req.on('timeout', () => resolve({ success: false, error: 'Timeout' }));

      if (data) req.write(JSON.stringify(data));
      req.end();
    });
  }

  async getMemoryStats() {
    // Try to get server memory stats if available
    const result = await this.makeRequest('GET', '/api/monitoring/memory');
    
    if (result.success && result.data.memory) {
      return result.data.memory;
    }
    
    // Fallback: get basic system info
    const statsResult = await this.makeRequest('GET', '/api/stats');
    return {
      timestamp: new Date().toISOString(),
      serverResponding: statsResult.success,
      note: 'Memory endpoint not available - monitoring via response times'
    };
  }

  async establishBaseline() {
    console.log('\n📊 Establishing Memory Baseline');
    
    // Make a few warm-up requests
    for (let i = 0; i < 3; i++) {
      await this.makeRequest('GET', '/api/status');
      await new Promise(resolve => setTimeout(resolve, 200));
    }
    
    this.baseline = await this.getMemoryStats();
    this.log('Baseline established', `Server responding: ${this.baseline.serverResponding}`);
    
    if (this.baseline.heapUsed) {
      this.log('Baseline memory', `Heap: ${Math.round(this.baseline.heapUsed / 1024 / 1024)}MB`);
    }
  }

  async monitorDuringLoad(testName, operation) {
    console.log(`\n🔍 Monitoring: ${testName}`);
    
    const measurements = [];
    const startTime = Date.now();
    
    // Start monitoring
    const monitoringInterval = setInterval(async () => {
      const stats = await this.getMemoryStats();
      measurements.push({
        timestamp: Date.now() - startTime,
        ...stats
      });
    }, 1000); // Sample every second
    
    try {
      // Run the operation
      await operation();
      
      // Continue monitoring for a bit after operation
      await new Promise(resolve => setTimeout(resolve, 3000));
      
    } finally {
      clearInterval(monitoringInterval);
    }
    
    // Analyze measurements
    if (measurements.length > 0) {
      const responsiveMeasurements = measurements.filter(m => m.serverResponding);
      const responseRate = Math.round((responsiveMeasurements.length / measurements.length) * 100);
      
      this.log(`${testName} complete`, `${measurements.length} samples, ${responseRate}% server response rate`);
      
      if (measurements.some(m => m.heapUsed)) {
        const memoryUsages = measurements.filter(m => m.heapUsed).map(m => m.heapUsed);
        const maxMemory = Math.max(...memoryUsages);
        const avgMemory = memoryUsages.reduce((a, b) => a + b, 0) / memoryUsages.length;
        
        this.log(`Memory usage`, `Max: ${Math.round(maxMemory / 1024 / 1024)}MB, Avg: ${Math.round(avgMemory / 1024 / 1024)}MB`);
      }
      
      this.measurements.push({
        testName,
        measurements,
        responseRate,
        duration: Date.now() - startTime
      });
    }
  }

  async testHighVolumeRequests() {
    await this.monitorDuringLoad('High Volume Requests', async () => {
      this.log('Starting high volume test', '100 requests in 10 seconds');
      
      const promises = [];
      for (let i = 0; i < 100; i++) {
        promises.push(this.makeRequest('GET', '/api/status'));
        
        // Stagger requests slightly
        if (i % 10 === 0) {
          await new Promise(resolve => setTimeout(resolve, 100));
        }
      }
      
      const results = await Promise.all(promises);
      const successful = results.filter(r => r.success).length;
      
      this.log('High volume complete', `${successful}/100 requests successful`);
    });
  }

  async testDatabaseOperations() {
    await this.monitorDuringLoad('Database Operations', async () => {
      this.log('Starting database stress test', 'Multiple complex queries');
      
      // Create test player
      const playerResult = await this.makeRequest('POST', '/api/players/register', {
        name: `MemTest${Date.now()}`,
        language: 'en',
        deviceId: `mem-test-${Date.now()}`
      });
      
      if (!playerResult.success) {
        this.log('Database test skipped', 'Could not create test player');
        return;
      }
      
      const playerId = playerResult.data.player.id;
      
      // Perform various database operations
      const operations = [
        () => this.makeRequest('GET', `/api/phrases/for/${playerId}`),
        () => this.makeRequest('GET', '/api/leaderboard/total'),
        () => this.makeRequest('GET', '/api/players/legends'),
        () => this.makeRequest('POST', '/api/phrases/create', {
          content: 'memory test phrase',
          language: 'en',
          senderId: playerId,
          hint: 'testing memory usage'
        }),
        () => this.makeRequest('POST', '/api/phrases/analyze-difficulty', {
          phrase: 'complex memory testing phrase with many words',
          language: 'en'
        })
      ];
      
      // Run operations multiple times
      for (let i = 0; i < 5; i++) {
        for (const operation of operations) {
          await operation();
          await new Promise(resolve => setTimeout(resolve, 200));
        }
      }
      
      this.log('Database operations complete', `${operations.length * 5} operations executed`);
    });
  }

  async testConcurrentUsers() {
    await this.monitorDuringLoad('Concurrent Users', async () => {
      this.log('Starting concurrent user test', '20 users for 15 seconds');
      
      const userTasks = [];
      
      // Simulate 20 concurrent users
      for (let i = 0; i < 20; i++) {
        const userTask = async () => {
          const startTime = Date.now();
          let requestCount = 0;
          
          // Each user makes requests for 15 seconds
          while (Date.now() - startTime < 15000) {
            await this.makeRequest('GET', '/api/status');
            requestCount++;
            
            // Random delay between user requests (100-500ms)
            await new Promise(resolve => setTimeout(resolve, 100 + Math.random() * 400));
          }
          
          return requestCount;
        };
        
        userTasks.push(userTask());
      }
      
      const userRequestCounts = await Promise.all(userTasks);
      const totalRequests = userRequestCounts.reduce((a, b) => a + b, 0);
      
      this.log('Concurrent users complete', `${totalRequests} total requests from 20 users`);
    });
  }

  async testMemoryLeaks() {
    console.log('\n🔍 Memory Leak Detection');
    
    // Establish initial memory state
    const initialStats = await this.getMemoryStats();
    
    // Perform repeated operations that might cause leaks
    for (let cycle = 0; cycle < 5; cycle++) {
      this.log(`Memory cycle ${cycle + 1}`, 'Performing repeated operations');
      
      // Create and cleanup test data
      for (let i = 0; i < 10; i++) {
        const playerResult = await this.makeRequest('POST', '/api/players/register', {
          name: `LeakTest${Date.now()}-${i}`,
          language: 'en',
          deviceId: `leak-test-${Date.now()}-${i}`
        });
        
        if (playerResult.success) {
          // Perform operations with this player
          await this.makeRequest('GET', `/api/phrases/for/${playerResult.data.player.id}`);
          await this.makeRequest('POST', '/api/phrases/create', {
            content: `leak test ${i}`,
            language: 'en',
            senderId: playerResult.data.player.id,
            hint: 'leak testing'
          });
        }
        
        // Brief pause
        await new Promise(resolve => setTimeout(resolve, 100));
      }
      
      // Check memory after each cycle
      const cycleStats = await this.getMemoryStats();
      
      if (initialStats.heapUsed && cycleStats.heapUsed) {
        const memoryIncrease = cycleStats.heapUsed - initialStats.heapUsed;
        const increaseMB = Math.round(memoryIncrease / 1024 / 1024);
        
        this.log(`Cycle ${cycle + 1} memory`, `+${increaseMB}MB from baseline`);
        
        if (increaseMB > 50) { // Alert if memory increased by more than 50MB
          this.log('Memory concern', `⚠️ Significant memory increase detected`);
        }
      }
      
      // Wait between cycles for potential garbage collection
      await new Promise(resolve => setTimeout(resolve, 2000));
    }
  }

  generateReport() {
    console.log('\n📋 MEMORY MONITORING REPORT');
    console.log('='.repeat(50));
    
    this.measurements.forEach(test => {
      console.log(`\n🔍 ${test.testName}:`);
      console.log(`  Duration: ${Math.round(test.duration / 1000)}s`);
      console.log(`  Samples: ${test.measurements.length}`);
      console.log(`  Server Response Rate: ${test.responseRate}%`);
      
      if (test.responseRate < 95) {
        console.log(`  ⚠️ Server responsiveness below 95%`);
      } else {
        console.log(`  ✅ Good server responsiveness`);
      }
    });
    
    console.log('\n💡 Memory Optimization Tips:');
    console.log('  • Monitor heap usage trends during high load');
    console.log('  • Check for memory leaks with repeated operations');
    console.log('  • Ensure garbage collection is working effectively');
    console.log('  • Consider connection pooling for database operations');
    
    console.log(`\n🕒 Monitoring completed: ${new Date().toISOString()}`);
  }

  async runAllTests() {
    console.log('🚀 Starting Memory Monitoring Suite');
    console.log(`📅 ${new Date().toISOString()}\n`);

    try {
      await this.establishBaseline();
      await this.testHighVolumeRequests();
      await this.testDatabaseOperations();
      await this.testConcurrentUsers();
      await this.testMemoryLeaks();
    } catch (error) {
      console.error('❌ Memory monitoring error:', error.message);
    }

    this.generateReport();
  }
}

// Run tests
if (require.main === module) {
  const monitor = new MemoryMonitoringTest();
  monitor.runAllTests().catch(error => {
    console.error('💥 Memory monitoring suite crashed:', error);
    process.exit(1);
  });
}

module.exports = MemoryMonitoringTest;