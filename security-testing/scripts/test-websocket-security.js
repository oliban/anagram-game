#!/usr/bin/env node
/**
 * WebSocket Security Testing Script
 * Tests both authenticated and unauthenticated connections to different namespaces
 */

const { io } = require('socket.io-client');

const SERVER_URL = 'http://localhost:3000';
const ADMIN_API_KEY = 'test-admin-key-123';

console.log('🧪 Testing WebSocket Security Implementation');
console.log('='.repeat(50));

async function testGameNamespace() {
  console.log('\n📱 Testing Game Namespace (should always work)...');
  
  const gameSocket = io(SERVER_URL, {
    transports: ['websocket'],
    timeout: 5000
  });

  return new Promise((resolve) => {
    const timeout = setTimeout(() => {
      console.log('❌ Game namespace connection timeout');
      gameSocket.close();
      resolve(false);
    }, 5000);

    gameSocket.on('connect', () => {
      console.log('✅ Game namespace connected successfully');
      console.log(`   Socket ID: ${gameSocket.id}`);
      clearTimeout(timeout);
      gameSocket.close();
      resolve(true);
    });

    gameSocket.on('connect_error', (error) => {
      console.log('❌ Game namespace connection failed:', error.message);
      clearTimeout(timeout);
      resolve(false);
    });
  });
}

async function testMonitoringNamespaceNoAuth() {
  console.log('\n📊 Testing Monitoring Namespace WITHOUT API key...');
  
  const monitoringSocket = io(`${SERVER_URL}/monitoring`, {
    transports: ['websocket'],
    timeout: 5000
  });

  return new Promise((resolve) => {
    const timeout = setTimeout(() => {
      console.log('❌ Monitoring namespace connection timeout (expected in production)');
      monitoringSocket.close();
      resolve('timeout');
    }, 5000);

    monitoringSocket.on('connect', () => {
      console.log('✅ Monitoring namespace connected without auth (development mode)');
      console.log(`   Socket ID: ${monitoringSocket.id}`);
      clearTimeout(timeout);
      monitoringSocket.close();
      resolve('success');
    });

    monitoringSocket.on('connect_error', (error) => {
      console.log('🛡️ Monitoring namespace rejected (security working):', error.message);
      clearTimeout(timeout);
      resolve('rejected');
    });
  });
}

async function testMonitoringNamespaceWithAuth() {
  console.log('\n🔑 Testing Monitoring Namespace WITH API key...');
  
  const monitoringSocket = io(`${SERVER_URL}/monitoring`, {
    transports: ['websocket'],
    timeout: 5000,
    auth: {
      apiKey: ADMIN_API_KEY
    }
  });

  return new Promise((resolve) => {
    const timeout = setTimeout(() => {
      console.log('❌ Monitoring namespace with auth timeout');
      monitoringSocket.close();
      resolve(false);
    }, 5000);

    monitoringSocket.on('connect', () => {
      console.log('✅ Monitoring namespace connected with API key');
      console.log(`   Socket ID: ${monitoringSocket.id}`);
      clearTimeout(timeout);
      monitoringSocket.close();
      resolve(true);
    });

    monitoringSocket.on('connect_error', (error) => {
      console.log('❌ Monitoring namespace auth failed:', error.message);
      clearTimeout(timeout);
      resolve(false);
    });
  });
}

async function testMonitoringNamespaceWrongAuth() {
  console.log('\n🚫 Testing Monitoring Namespace with WRONG API key...');
  
  const monitoringSocket = io(`${SERVER_URL}/monitoring`, {
    transports: ['websocket'],
    timeout: 5000,
    auth: {
      apiKey: 'wrong-key-123'
    }
  });

  return new Promise((resolve) => {
    const timeout = setTimeout(() => {
      console.log('❌ Wrong auth timeout');
      monitoringSocket.close();
      resolve('timeout');
    }, 5000);

    monitoringSocket.on('connect', () => {
      console.log('⚠️ Monitoring namespace accepted wrong key (development mode)');
      console.log(`   Socket ID: ${monitoringSocket.id}`);
      clearTimeout(timeout);
      monitoringSocket.close();
      resolve('accepted');
    });

    monitoringSocket.on('connect_error', (error) => {
      console.log('✅ Wrong API key correctly rejected:', error.message);
      clearTimeout(timeout);
      resolve('rejected');
    });
  });
}

async function runTests() {
  try {
    const results = {
      gameNamespace: await testGameNamespace(),
      monitoringNoAuth: await testMonitoringNamespaceNoAuth(),
      monitoringWithAuth: await testMonitoringNamespaceWithAuth(),
      monitoringWrongAuth: await testMonitoringNamespaceWrongAuth()
    };

    console.log('\n' + '='.repeat(50));
    console.log('📋 TEST RESULTS SUMMARY');
    console.log('='.repeat(50));
    
    console.log(`Game Namespace (open):           ${results.gameNamespace ? '✅ PASS' : '❌ FAIL'}`);
    console.log(`Monitoring No Auth:              ${results.monitoringNoAuth === 'success' ? '✅ PASS (dev)' : results.monitoringNoAuth === 'rejected' ? '🛡️ SECURE (prod)' : '❌ FAIL'}`);
    console.log(`Monitoring With Valid Auth:      ${results.monitoringWithAuth ? '✅ PASS' : '❌ FAIL'}`);
    console.log(`Monitoring Wrong Auth:           ${results.monitoringWrongAuth === 'rejected' ? '🛡️ SECURE' : results.monitoringWrongAuth === 'accepted' ? '⚠️ DEV MODE' : '❌ FAIL'}`);

    console.log('\n💡 Expected behavior:');
    console.log('  - Development (SECURITY_RELAXED=true): All connections succeed');
    console.log('  - Production (SECURITY_RELAXED=false): Only valid auth succeeds');
    
  } catch (error) {
    console.error('❌ Test failed:', error);
  }
  
  process.exit(0);
}

if (require.main === module) {
  runTests();
}

module.exports = { testGameNamespace, testMonitoringNamespaceNoAuth, testMonitoringNamespaceWithAuth };