const express = require('express');
const router = express.Router();

// Contribution routes - external phrase contribution system

module.exports = (dependencies) => {
  const { 
    getDatabaseStatus, 
    DatabasePhrase, 
    broadcastActivity 
  } = dependencies;

  // Request contribution link
  router.post('/api/contribution/request', async (req, res) => {
    try {
      if (!getDatabaseStatus()) {
        return res.status(503).json({
          error: 'Database connection required for contribution requests'
        });
      }

      const { playerName, requestType, details, language = 'en' } = req.body;

      // Validate required fields
      if (!playerName) {
        return res.status(400).json({
          error: 'Player name is required'
        });
      }

      if (!requestType || !['phrase', 'improvement', 'bug'].includes(requestType)) {
        return res.status(400).json({
          error: 'Request type must be phrase, improvement, or bug'
        });
      }

      const linkGenerator = require('../../web-dashboard/server/link-generator');
      
      const contributionRequest = {
        playerName,
        requestType,
        details: details || '',
        language,
        createdAt: new Date()
      };

      const token = await linkGenerator.createContributionLink(contributionRequest);

      res.json({
        success: true,
        token,
        message: 'Contribution link generated successfully'
      });

    } catch (error) {
      console.error('❌ Error creating contribution request:', error);
      res.status(500).json({
        error: 'Failed to create contribution request'
      });
    }
  });

  // Get contribution data by token
  router.get('/api/contribution/:token', async (req, res) => {
    try {
      const { token } = req.params;
      const linkGenerator = require('../../web-dashboard/server/link-generator');
      
      const contributionData = await linkGenerator.getContributionData(token);
      
      if (!contributionData) {
        return res.status(404).json({
          error: 'Contribution link not found or expired'
        });
      }

      res.json({
        success: true,
        contribution: contributionData
      });

    } catch (error) {
      console.error('❌ Error getting contribution data:', error);
      res.status(500).json({
        error: 'Failed to get contribution data'
      });
    }
  });

  // Submit contribution
  router.post('/api/contribution/:token/submit', async (req, res) => {
    try {
      if (!getDatabaseStatus()) {
        return res.status(503).json({
          error: 'Database connection required for phrase submission'
        });
      }

      const { token } = req.params;
      const { phrase, hint, difficulty = 1 } = req.body;

      // Validate phrase submission
      if (!phrase || !hint) {
        return res.status(400).json({
          error: 'Phrase and hint are required'
        });
      }

      const linkGenerator = require('../../web-dashboard/server/link-generator');
      
      // Get contribution data
      const contributionData = await linkGenerator.getContributionData(token);
      
      if (!contributionData) {
        return res.status(404).json({
          error: 'Contribution link not found or expired'
        });
      }

      // Create the phrase in database
      const phraseData = await DatabasePhrase.createPhrase({
        content: phrase,
        hint: hint,
        senderId: null, // No specific sender for contributed phrases
        targetId: null, // Global phrase
        language: contributionData.language || 'en',
        isGlobal: true,
        phraseType: 'community',
        difficultyLevel: difficulty,
        isApproved: false // Requires approval
      });

      // Mark contribution as used
      await linkGenerator.markContributionUsed(token, phraseData.id);

      // Broadcast activity
      broadcastActivity('contribution', `New community phrase submitted: "${phrase.substring(0, 50)}${phrase.length > 50 ? '...' : ''}"`, {
        phraseId: phraseData.id,
        contributor: contributionData.playerName,
        language: contributionData.language
      });

      res.json({
        success: true,
        message: 'Phrase submitted successfully and is pending approval',
        phraseId: phraseData.id
      });

    } catch (error) {
      console.error('❌ Error submitting contribution:', error);
      
      if (error.message.includes('Phrase validation failed') || 
          error.message.includes('too short') ||
          error.message.includes('too long')) {
        return res.status(400).json({
          error: error.message
        });
      }
      
      res.status(500).json({
        error: 'Failed to submit contribution'
      });
    }
  });

  return router;
};