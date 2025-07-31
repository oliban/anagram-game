const express = require('express');
const router = express.Router();

// Debug routes - client logging and performance monitoring

module.exports = (dependencies) => {
  const { configService } = dependencies;

  // Client debug logging
  router.post('/api/debug/log', async (req, res) => {
    try {
      // Performance monitoring is always enabled for debugging
      console.log('📊 CLIENT DEBUG:', req.body);
      res.json({ success: true });
    } catch (error) {
      console.error('❌ DEBUG LOG: Error processing debug log:', error);
      res.status(500).json({ error: 'Failed to process debug log' });
    }
  });

  // Client performance monitoring
  router.post('/api/debug/performance', async (req, res) => {
    try {
      // Performance monitoring is always enabled for debugging
      console.log('🎯 CLIENT PERFORMANCE:', req.body);
      res.json({ success: true });
    } catch (error) {
      console.error('❌ DEBUG PERFORMANCE: Error processing performance data:', error);
      res.status(500).json({ error: 'Failed to process performance data' });
    }
  });

  return router;
};