#!/usr/bin/env node

const RouteAnalytics = require('../services/shared/services/routeAnalytics');

function printRouteStats(serviceName, days = 1) {
  console.log(`\n📊 ${serviceName.toUpperCase()} ROUTE ANALYTICS (Last ${days} day${days > 1 ? 's' : ''})`);
  console.log('='.repeat(60));
  
  const analytics = new RouteAnalytics(serviceName);
  
  try {
    const stats = analytics.getRouteStats(days);
    const topRoutes = analytics.getTopRoutes(days, 20);
    
    if (topRoutes.length === 0) {
      console.log('No analytics data found. Make sure services are running and receiving requests.');
      return;
    }
    
    console.log('\n🏆 TOP ROUTES BY REQUEST COUNT:');
    console.log('Route'.padEnd(40), 'Requests'.padStart(10), 'Avg Time'.padStart(10), 'Error %'.padStart(8));
    console.log('-'.repeat(70));
    
    topRoutes.forEach(route => {
      console.log(
        route.route.padEnd(40),
        route.requests.toString().padStart(10),
        `${route.avgResponseTime}ms`.padStart(10),
        `${route.errorRate}%`.padStart(8)
      );
    });
    
    // Summary stats
    const totalRequests = topRoutes.reduce((sum, route) => sum + route.requests, 0);
    const avgResponseTime = Math.round(
      topRoutes.reduce((sum, route) => sum + (route.avgResponseTime * route.requests), 0) / totalRequests
    );
    const totalErrors = topRoutes.reduce((sum, route) => sum + route.errors, 0);
    const overallErrorRate = ((totalErrors / totalRequests) * 100).toFixed(2);
    
    console.log('\n📈 SUMMARY:');
    console.log(`Total Requests: ${totalRequests}`);
    console.log(`Average Response Time: ${avgResponseTime}ms`);
    console.log(`Overall Error Rate: ${overallErrorRate}%`);
    console.log(`Unique Routes: ${topRoutes.length}`);
    
  } catch (error) {
    console.error(`Error reading analytics for ${serviceName}:`, error.message);
  }
}

function printAllServiceStats(days = 1) {
  const services = ['game-server', 'web-dashboard', 'link-generator', 'admin-service'];
  
  console.log(`🔍 MICROSERVICES ROUTE ANALYTICS REPORT`);
  console.log(`Generated: ${new Date().toISOString()}`);
  
  services.forEach(service => {
    printRouteStats(service, days);
  });
  
  console.log('\n' + '='.repeat(60));
  console.log('💡 TIP: Run this script after using the app to see route usage patterns');
  console.log('📁 Log files are stored in: services/logs/analytics/');
}

// Parse command line arguments
const args = process.argv.slice(2);
const days = args.includes('--days') ? parseInt(args[args.indexOf('--days') + 1]) || 1 : 1;
const service = args.find(arg => !arg.startsWith('--') && isNaN(parseInt(arg)));

// Display usage if help requested
if (args.includes('--help') || args.includes('-h')) {
  console.log(`
🔍 Route Analytics Viewer

Usage:
  node scripts/view-analytics.js [service] [--days N]

Arguments:
  service     Optional service name: game-server, web-dashboard, link-generator, admin-service
  --days N    Number of days to analyze (default: 1)

Examples:
  node scripts/view-analytics.js                    # All services, last 24 hours  
  node scripts/view-analytics.js game-server        # Just game server, last 24 hours
  node scripts/view-analytics.js --days 7           # All services, last 7 days
  node scripts/view-analytics.js game-server --days 3   # Game server, last 3 days
`);
  process.exit(0);
}

// Run analytics
if (service) {
  printRouteStats(service, days);
} else {
  printAllServiceStats(days);
}