const express = require('express');
const router = express.Router();

// Debug routes - client logging and performance monitoring

module.exports = (dependencies) => {
  const { configService } = dependencies;

  // Client debug logging
  router.post('/api/debug/log', (req, res) => {
    // Check if performance monitoring is enabled
    if (!configService.isPerformanceMonitoringEnabled()) {
      return res.status(403).json({
        error: 'Performance monitoring is disabled'
      });
    }
    
    console.log('📊 CLIENT DEBUG:', req.body);
    res.json({ success: true });
  });

  // Client performance monitoring
  router.post('/api/debug/performance', (req, res) => {
    // Check if performance monitoring is enabled
    if (!configService.isPerformanceMonitoringEnabled()) {
      return res.status(403).json({
        error: 'Performance monitoring is disabled'
      });
    }
    
    console.log('🎯 CLIENT PERFORMANCE:', req.body);
    res.json({ success: true });
  });

  return router;
};