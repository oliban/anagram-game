const express = require('express');
const path = require('path');
const router = express.Router();

// Phrase routes - CRUD operations, approval, consumption, and analysis

module.exports = (dependencies) => {
  const { 
    getDatabaseStatus, 
    DatabasePlayer, 
    DatabasePhrase, 
    broadcastActivity, 
    io, 
    query,
    pool 
  } = dependencies;

  // Enhanced phrase creation endpoint
  router.post('/api/phrases/create', async (req, res) => {
    try {
      if (!getDatabaseStatus()) {
        return res.status(503).json({
          error: 'Database connection required for phrase creation'
        });
      }

      const {
        content,
        hint = '', // Make hint optional for iOS compatibility
        senderId,
        targetId, // Single target for iOS compatibility
        targetIds = [], // Multiple targets (legacy support)
        isGlobal = false,
        difficultyLevel = 1,
        phraseType = 'custom',
        language = 'en',
        theme = null // Add theme support for phrase creation
      } = req.body;

      console.log(`🔍 DEBUG /api/phrases/create - Full request body:`, JSON.stringify(req.body, null, 2));

      // Validate required fields
      if (!content) {
        return res.status(400).json({
          error: 'Content is required'
        });
      }

      if (!senderId) {
        return res.status(400).json({
          error: 'Sender ID is required'
        });
      }

      // Validate sender exists
      const sender = await DatabasePlayer.getPlayerById(senderId);
      if (!sender) {
        return res.status(404).json({
          error: 'Sender player not found'
        });
      }

      // Handle both single targetId and multiple targetIds
      const allTargetIds = [];
      if (targetId) allTargetIds.push(targetId);
      if (targetIds.length > 0) allTargetIds.push(...targetIds);

      // Validate target players if provided
      const validTargets = [];
      if (allTargetIds.length > 0) {
        for (const tid of allTargetIds) {
          const target = await DatabasePlayer.getPlayerById(tid);
          if (!target) {
            return res.status(404).json({
              error: `Target player ${tid} not found`
            });
          }
          if (target.id === senderId) {
            return res.status(400).json({
              error: 'Cannot target yourself'
            });
          }
          validTargets.push(target);
        }
      }

      console.log(`🔍 DEBUG - Using language: "${language}", content="${content}"`);

      // Create enhanced phrase
      const result = await DatabasePhrase.createEnhancedPhrase({
        content,
        hint,
        senderId,
        targetIds: allTargetIds,
        isGlobal,
        phraseType,
        language: language,
        theme: theme // Pass theme to database layer
      });

      const { phrase, targetCount, isGlobal: phraseIsGlobal } = result;

      console.log(`📝 Enhanced phrase created: "${content}" from ${sender.name}${phraseIsGlobal ? ' (global)' : ` to ${targetCount} players`}`);

      // Send real-time notifications to target players
      const notifications = [];
      for (const target of validTargets) {
        if (target.socketId) {
          const phraseData = phrase.getPublicInfo();
          // Ensure targetId and senderName are included for iOS client compatibility
          phraseData.targetId = target.id;
          phraseData.senderName = sender.name;
          
          io.to(target.socketId).emit('new-phrase', {
            phrase: phraseData,
            senderName: sender.name,
            timestamp: new Date().toISOString()
          });
          notifications.push(target.name);
          console.log(`📨 Sent enhanced phrase notification to ${target.name} (${target.socketId})`);
        }
      }

      // Enhanced response format
      res.status(201).json({
        success: true,
        phrase: {
          ...phrase.getPublicInfo(),
          senderInfo: {
            id: sender.id,
            name: sender.name
          }
        },
        targeting: {
          isGlobal: phraseIsGlobal,
          targetCount,
          notificationsSent: notifications.length
        },
        message: 'Enhanced phrase created successfully'
      });

    } catch (error) {
      console.error('Error creating enhanced phrase:', error);

      // Handle validation errors as 400 (client errors)
      if (error.message.includes('Validation failed') ||
          error.message.includes('Difficulty level must be') ||
          error.message.includes('Invalid phrase type')) {
        return res.status(400).json({
          error: error.message
        });
      }

      // Default to 500 for unexpected errors
      res.status(500).json({
        error: 'Failed to create phrase',
        details: process.env.NODE_ENV === 'development' ? error.message : undefined
      });
    }
  });

  // REMOVED: /api/phrases - Legacy phrase creation endpoint (Legacy cleanup)

  // REMOVED: /api/phrases/global - Not used by iOS app (Phase 3 cleanup)

  // REMOVED: /api/phrases/:phraseId/approve - Admin-only feature, no consumers (Phase 3 cleanup)

  // Get phrases for specific player - UPDATED to match iOS PhrasePreview structure
  router.get('/api/phrases/for/:playerId', async (req, res) => {
    try {
      if (!getDatabaseStatus()) {
        return res.status(503).json({
          error: 'Database connection required for phrase data'
        });
      }
      
      const { playerId } = req.params;
      const { level } = req.query; // Get player level from query parameters
      
      // Validate that player exists in database
      const player = await DatabasePlayer.getPlayerById(playerId);
      if (!player) {
        return res.status(404).json({ 
          error: 'Player not found' 
        });
      }
      
      // Determine max difficulty based on player level
      let maxDifficulty = null;
      if (level) {
        try {
          const fs = require('fs').promises;
          const configPath = path.join(__dirname, '../shared/config', 'level-config.json');
          const configData = await fs.readFile(configPath, 'utf8');
          const levelConfig = JSON.parse(configData);
          
          const playerLevel = parseInt(level);
          if (playerLevel > 0) {
            // Find the skill level that matches the player's level
            const skillLevel = levelConfig.skillLevels?.find(sl => sl.id === playerLevel);
            if (skillLevel) {
              maxDifficulty = skillLevel.maxDifficulty;
              console.log(`🎯 LEVEL FILTER: Player skill level ${playerLevel} (${skillLevel.title}), max difficulty: ${maxDifficulty}`);
            } else {
              // Fallback to legacy calculation if skill level not found
              maxDifficulty = playerLevel * (levelConfig.baseDifficultyPerLevel || 50);
              console.log(`🎯 LEVEL FILTER: Legacy calculation for level ${playerLevel}, max difficulty: ${maxDifficulty}`);
            }
          }
        } catch (configError) {
          console.error('❌ LEVEL CONFIG: Error loading level config, using no filtering:', configError.message);
        }
      }
      
      // Get phrases for player from database (both targeted and global)
      let phrases = await DatabasePhrase.getPhrasesForPlayer(playerId, maxDifficulty);
      
      // If no phrases available (getPhrasesForPlayer already checked targeted AND global phrases)
      if (phrases.length === 0) {
        console.log(`🌍 PHRASE: No phrases available for player ${playerId} (all filtered out: skipped, completed, or self-created)`);
        return res.status(404).json({
          error: 'No phrases available for player'
        });
      }
      
      // Import difficulty scoring algorithm for client-side hint system
      const { calculateScore } = require('../shared/services/difficultyScorer');
      
      // Convert ALL phrases to CustomPhrase format that iOS NetworkManager expects
      const customPhrasesFormat = phrases.map(phrase => {
        const phraseInfo = phrase.getPublicInfo();
        
        // Calculate base score for each phrase
        const baseScore = calculateScore({ 
          phrase: phraseInfo.content, 
          language: phraseInfo.language || 'en' 
        });
        
        console.log(`🔍 CLUE DEBUG: Phrase "${phraseInfo.content}" - hint from DB: "${phraseInfo.hint}", mapped to clue: "${phraseInfo.hint || ''}", theme: "${phraseInfo.theme || 'null'}"`);
        
        return {
          id: phraseInfo.id,
          content: phraseInfo.content,
          senderId: phraseInfo.senderId || '',
          targetId: phraseInfo.targetId || null,
          createdAt: new Date().toISOString(),
          isConsumed: false,
          senderName: phraseInfo.senderName || 'Server',
          language: phraseInfo.language || 'en',
          clue: phraseInfo.hint || '', // Map hint to clue field
          theme: phraseInfo.theme || null, // Add theme support for iOS app
          difficultyLevel: phraseInfo.difficultyLevel || baseScore
        };
      });
      
      console.log(`🚀 ROUTE: First formatted phrase theme:`, customPhrasesFormat[0]?.theme);
      
      // Return in the format iOS NetworkManager expects (array with phrases field)
      const response = {
        phrases: customPhrasesFormat, // iOS expects array of CustomPhrase
        count: customPhrasesFormat.length,
        timestamp: new Date().toISOString()
      };
      
      console.log(`✅ PHRASE: Sent ${customPhrasesFormat.length} phrases to iOS client`);
      console.log(`🔍 SERVER: First phrase: "${customPhrasesFormat[0].content}", Language: ${customPhrasesFormat[0].language}, Total: ${customPhrasesFormat.length}`);
      
      res.json(response);
      
    } catch (error) {
      console.error('❌ Error getting phrases for player:', error);
      
      // Handle UUID format errors as client errors (400)
      if (error.message && error.message.includes('invalid input syntax for type uuid')) {
        return res.status(400).json({
          error: 'Invalid player ID format'
        });
      }
      
      res.status(500).json({ 
        error: 'Failed to get phrases' 
      });
    }
  });

  // Complete phrase - NEW endpoint for iOS phrase completion
  router.post('/api/phrases/:phraseId/complete', async (req, res) => {
    try {
      if (!getDatabaseStatus()) {
        return res.status(503).json({
          error: 'Database connection required for phrase completion'
        });
      }
      
      const { phraseId } = req.params;
      const { playerId, hintsUsed, completionTime } = req.body;
      
      // Validate required fields
      if (!playerId) {
        return res.status(400).json({
          error: 'playerId is required'
        });
      }
      
      if (typeof hintsUsed !== 'number' || hintsUsed < 0) {
        return res.status(400).json({
          error: 'hintsUsed must be a non-negative number'
        });
      }
      
      if (typeof completionTime !== 'number' || completionTime < 0) {
        return res.status(400).json({
          error: 'completionTime must be a non-negative number'
        });
      }
      
      // Validate that player exists
      const player = await DatabasePlayer.getPlayerById(playerId);
      if (!player) {
        return res.status(404).json({
          error: 'Player not found'
        });
      }
      
      // Get the phrase to validate it exists and calculate score
      const phrase = await DatabasePhrase.getPhraseById(phraseId);
      if (!phrase) {
        return res.status(404).json({
          error: 'Phrase not found'
        });
      }
      
      // Calculate final score based on hints used
      const { calculateScore } = require('../shared/services/difficultyScorer');
      const baseScore = calculateScore({ 
        phrase: phrase.content, 
        language: phrase.language || 'en' 
      });
      
      // Apply hint penalties: Level 1 = 20%, Level 2 = 40%, Level 3 = 60%
      let finalScore = baseScore;
      if (hintsUsed >= 1) finalScore = Math.round(finalScore * 0.8); // Level 1 hint
      if (hintsUsed >= 2) finalScore = Math.round(finalScore * 0.75); // Level 2 hint (0.8 * 0.75 = 0.6)
      if (hintsUsed >= 3) finalScore = Math.round(finalScore * 0.67); // Level 3 hint (0.6 * 0.67 = 0.4)
      
      // Ensure minimum score
      finalScore = Math.max(1, finalScore);
      
      // Mark phrase as completed/consumed
      const consumeSuccess = await DatabasePhrase.consumePhrase(phraseId);
      if (!consumeSuccess) {
        console.warn(`⚠️ COMPLETE: Could not mark phrase ${phraseId} as consumed`);
      }
      
      // Record completion in scoring system
      try {
        const ScoringSystem = require('../shared/services/scoringSystem');
        await ScoringSystem.recordPhraseCompletion(playerId, phraseId, finalScore, hintsUsed, completionTime);
      } catch (statsError) {
        console.warn(`⚠️ COMPLETE: Could not record completion stats: ${statsError.message}`);
        // Don't fail the request if stats recording fails
      }
      
      const completionResult = {
        success: true,
        completion: {
          finalScore: finalScore,
          hintsUsed: hintsUsed,
          completionTime: completionTime
        },
        timestamp: new Date().toISOString()
      };
      
      console.log(`🎉 COMPLETE: Player ${player.name} completed phrase "${phrase.content}" with score ${finalScore} (${hintsUsed} hints, ${completionTime}ms)`);
      
      // Broadcast completion notification to other players via WebSocket
      if (io) {
        io.emit('phrase-completed', {
          playerName: player.name,
          phrase: phrase.content,
          score: finalScore,
          hintsUsed: hintsUsed,
          completionTime: completionTime,
          timestamp: new Date().toISOString()
        });
      }
      
      res.status(200).json(completionResult);
      
    } catch (error) {
      console.error('❌ Error completing phrase:', error);
      
      // Handle UUID format errors as client errors (400)
      if (error.message && error.message.includes('invalid input syntax for type uuid')) {
        return res.status(400).json({
          error: 'Invalid phrase ID or player ID format'
        });
      }
      
      res.status(500).json({
        error: 'Failed to complete phrase'
      });
    }
  });

  // REMOVED: /api/phrases/download/:playerId - Offline feature not implemented in iOS (Phase 3 cleanup)

  // Consume phrase
  router.post('/api/phrases/:phraseId/consume', async (req, res) => {
    try {
      const { phraseId } = req.params;
      
      const success = await DatabasePhrase.consumePhrase(phraseId);
      
      if (success) {
        console.log(`✅ Phrase consumed: ${phraseId}`);
        res.json({
          success: true,
          message: 'Phrase marked as consumed'
        });
      } else {
        res.status(404).json({ 
          error: 'Phrase not found or already consumed' 
        });
      }
      
    } catch (error) {
      console.error('Error consuming phrase:', error);
      res.status(500).json({ 
        error: 'Failed to consume phrase' 
      });
    }
  });

  // Skip phrase
  router.post('/api/phrases/:phraseId/skip', async (req, res) => {
    try {
      if (!getDatabaseStatus()) {
        return res.status(503).json({
          error: 'Database connection required for phrase operations'
        });
      }
      
      const { phraseId } = req.params;
      const { playerId } = req.body;
      
      // Validate player exists
      const player = await DatabasePlayer.getPlayerById(playerId);
      if (!player) {
        return res.status(404).json({ 
          error: 'Player not found' 
        });
      }
      
      // Skip the phrase in database
      const success = await DatabasePhrase.skipPhrase(playerId, phraseId);
      
      if (!success) {
        return res.status(404).json({ 
          error: 'Phrase not found or already processed' 
        });
      }
      
      console.log(`⏭️ Phrase skipped: ${phraseId} by player ${player.name} (${playerId})`);
      
      res.json({
        success: true,
        message: 'Phrase skipped successfully'
      });
      
    } catch (error) {
      console.error('Error skipping phrase:', error);
      res.status(500).json({ 
        error: 'Failed to skip phrase' 
      });
    }
  });

  // Analyze phrase difficulty
  router.post('/api/phrases/analyze-difficulty', async (req, res) => {
    try {
      const { phrase, language = 'en' } = req.body;
      
      // Validate input
      if (!phrase || typeof phrase !== 'string') {
        return res.status(400).json({
          error: 'Phrase is required and must be a string'
        });
      }
      
      if (phrase.trim().length === 0) {
        return res.status(400).json({
          error: 'Phrase cannot be empty'
        });
      }
      
      // Validate language
      const { LANGUAGES, calculateScore, getDifficultyLabel } = require('../shared/services/difficultyScorer');
      const validLanguages = Object.values(LANGUAGES);
      
      if (!validLanguages.includes(language)) {
        return res.status(400).json({
          error: `Language must be one of: ${validLanguages.join(', ')}`
        });
      }
      
      // Calculate difficulty score
      const score = calculateScore({ phrase: phrase.trim(), language });
      const difficultyLabel = getDifficultyLabel(score);
      
      console.log(`📊 ANALYSIS: "${phrase}" (${language}) -> Score: ${score} (${difficultyLabel})`);
      
      res.json({
        phrase: phrase.trim(),
        language: language,
        score: score,
        difficulty: difficultyLabel,
        timestamp: new Date().toISOString()
      });
      
    } catch (error) {
      console.error('❌ ANALYSIS: Error analyzing phrase:', error.message);
      res.status(500).json({
        error: 'Failed to analyze phrase difficulty',
        timestamp: new Date().toISOString()
      });
    }
  });

  return router;
};