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
        language = 'en'
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
        language: language
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

  // Legacy phrase creation endpoint (for compatibility)
  router.post('/api/phrases', async (req, res) => {
    try {
      const { content, senderId, targetId, language } = req.body;
      
      // Validate required fields
      if (!content || !senderId || !targetId) {
        return res.status(400).json({ 
          error: 'Content, senderId, and targetId are required' 
        });
      }
      
      // Validate that sender and target are different
      if (senderId === targetId) {
        return res.status(400).json({ 
          error: 'Cannot send phrase to yourself' 
        });
      }
      
      // Validate that both sender and target exist
      const sender = await DatabasePlayer.getPlayerById(senderId);
      const target = await DatabasePlayer.getPlayerById(targetId);
      
      if (!sender) {
        return res.status(404).json({ 
          error: 'Sender player not found' 
        });
      }
      
      if (!target) {
        return res.status(404).json({ 
          error: 'Target player not found' 
        });
      }
      
      // Create phrase in database
      const phrase = await DatabasePhrase.createPhrase({
        content,
        senderId,
        targetId,
        hint: req.body.hint || null, // Optional hint support
        language: language
      });
      
      console.log(`📝 Phrase created: "${content}" from ${sender.name} to ${target.name}`);
      
      // Broadcast activity to monitoring dashboard
      broadcastActivity('phrase', `New phrase created: "${content.substring(0, 50)}${content.length > 50 ? '...' : ''}"`, {
        phraseId: phrase.id,
        content: content,
        senderName: sender.name,
        targetName: target.name,
        difficulty: phrase.difficulty,
        language: phrase.language
      });
      
      // Send real-time notification to target player
      if (target.socketId) {
        const phraseData = phrase.getPublicInfo();
        // Ensure targetId and senderName are included for iOS client compatibility
        phraseData.targetId = targetId;
        phraseData.senderName = sender.name;
        
        io.to(target.socketId).emit('new-phrase', {
          phrase: phraseData,
          senderName: sender.name,
          timestamp: new Date().toISOString()
        });
        console.log(`📨 Sent new-phrase notification to ${target.name} (${target.socketId})`);
      } else {
        console.log(`📨 Target player ${target.name} not connected - phrase queued`);
      }
      
      res.status(201).json({
        success: true,
        phrase: phrase.getPublicInfo(),
        message: 'Phrase created successfully'
      });
      
    } catch (error) {
      console.error('Error creating phrase:', error);
      
      // Handle phrase validation errors as 400 (client errors)
      if (error.message.includes('cannot contain more than') ||
          error.message.includes('too short') ||
          error.message.includes('too long') ||
          error.message.includes('invalid characters')) {
        return res.status(400).json({ 
          error: error.message 
        });
      }
      
      res.status(500).json({ 
        error: error.message || 'Failed to create phrase' 
      });
    }
  });

  // Get global phrases
  router.get('/api/phrases/global', async (req, res) => {
    try {
      if (!getDatabaseStatus()) {
        return res.status(503).json({
          error: 'Database connection required for phrase data'
        });
      }

      // Parse query parameters with defaults
      const rawLimit = parseInt(req.query.limit) || 50;
      const limit = Math.min(Math.max(rawLimit, 1), 100); // Ensure positive and max 100 phrases per request
      const offset = Math.max(parseInt(req.query.offset) || 0, 0); // Ensure non-negative
      
      // Legacy difficulty filter (1-5 range)
      const rawDifficulty = parseInt(req.query.difficulty);
      const difficulty = (rawDifficulty >= 1 && rawDifficulty <= 5) ? rawDifficulty : null;
      
      // New difficulty range filters (1+ range, no upper limit)
      const rawMinDifficulty = parseInt(req.query.minDifficulty);
      const minDifficulty = (rawMinDifficulty >= 1) ? rawMinDifficulty : null;
      const rawMaxDifficulty = parseInt(req.query.maxDifficulty);
      const maxDifficulty = (rawMaxDifficulty >= 1) ? rawMaxDifficulty : null;
      
      const approved = req.query.approved !== 'false'; // Default to approved only

      // Check for invalid difficulty values - if provided but invalid, return empty results
      const hasInvalidMinDifficulty = req.query.minDifficulty && (isNaN(rawMinDifficulty) || rawMinDifficulty < 1);
      const hasInvalidMaxDifficulty = req.query.maxDifficulty && (isNaN(rawMaxDifficulty) || rawMaxDifficulty < 1);
      
      console.log(`🌍 REQUEST: Global phrases - limit: ${limit}, offset: ${offset}, difficulty: ${difficulty || 'all'}, minDifficulty: ${minDifficulty || 'none'}, maxDifficulty: ${maxDifficulty || 'none'}, approved: ${approved}`);

      // If invalid difficulty values were provided, return empty results
      if (hasInvalidMinDifficulty || hasInvalidMaxDifficulty) {
        console.log(`⚠️ DATABASE: Invalid difficulty parameters provided, returning empty results`);
        res.json({
          success: true,
          phrases: [],
          pagination: {
            limit,
            offset,
            total: 0,
            count: 0,
            hasMore: false
          },
          filters: {
            difficulty: difficulty || 'all',
            minDifficulty: minDifficulty || 'none',
            maxDifficulty: maxDifficulty || 'none',
            approved
          },
          timestamp: new Date().toISOString()
        });
        return;
      }

      // Get global phrases with optional filtering
      const phrases = await DatabasePhrase.getGlobalPhrases(limit, offset, difficulty, approved, minDifficulty, maxDifficulty);
      
      // Get total count for pagination
      const totalCount = await DatabasePhrase.getGlobalPhrasesCount(difficulty, approved, minDifficulty, maxDifficulty);

      // Enhanced response with pagination metadata
      res.json({
        success: true,
        phrases: phrases.map(phrase => ({
          id: phrase.id,
          content: phrase.content,
          hint: phrase.hint,
          difficultyLevel: phrase.difficultyLevel,
          phraseType: phrase.phraseType,
          priority: phrase.priority,
          usageCount: phrase.usageCount,
          isApproved: phrase.isApproved,
          createdAt: phrase.createdAt,
          createdByName: phrase.createdByName || 'Anonymous'
        })),
        pagination: {
          limit,
          offset,
          total: totalCount,
          count: phrases.length,
          hasMore: offset + phrases.length < totalCount
        },
        filters: {
          difficulty: difficulty || 'all',
          minDifficulty: minDifficulty || 'none',
          maxDifficulty: maxDifficulty || 'none',
          approved
        },
        timestamp: new Date().toISOString()
      });

      console.log(`✅ DATABASE: Returned ${phrases.length} global phrases (${totalCount} total)`);

    } catch (error) {
      console.error('❌ Error getting global phrases:', error);
      res.status(500).json({
        error: 'Failed to retrieve global phrases'
      });
    }
  });

  // Approve phrase
  router.post('/api/phrases/:phraseId/approve', async (req, res) => {
    try {
      if (!getDatabaseStatus()) {
        return res.status(503).json({
          error: 'Database connection required for phrase approval'
        });
      }

      const { phraseId } = req.params;

      // Basic UUID validation for phraseId
      const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      if (!uuidRegex.test(phraseId)) {
        return res.status(400).json({
          error: 'Invalid phrase ID format'
        });
      }

      console.log(`✅ REQUEST: Approve phrase ${phraseId}`);

      // Approve the phrase (this method checks if phrase exists and is global)
      const approved = await DatabasePhrase.approvePhrase(phraseId);

      if (approved) {
        res.status(200).json({
          success: true,
          phraseId,
          approved: true,
          message: 'Phrase approved successfully',
          timestamp: new Date().toISOString()
        });

        console.log(`✅ APPROVAL: Phrase ${phraseId} approved for global use`);
      } else {
        res.status(404).json({
          error: 'Phrase not found or not eligible for approval'
        });
      }

    } catch (error) {
      console.error('❌ Error approving phrase:', error);
      
      // Handle UUID validation errors specifically
      if (error.message.includes('invalid input syntax for type uuid')) {
        return res.status(400).json({
          error: 'Invalid phrase ID format'
        });
      }

      res.status(500).json({
        error: 'Failed to approve phrase'
      });
    }
  });

  // Get phrases for specific player
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
      
      // Get phrases for player from database (with optional difficulty filtering)
      const phrases = await DatabasePhrase.getPhrasesForPlayer(playerId, maxDifficulty);
      
      const phrasesData = phrases.map(p => p.getPublicInfo());
      
      // CRITICAL DEBUG: Log the exact JSON being sent to iOS client
      if (phrasesData.length > 0 && phrasesData[0].targetId) {
        console.log('🔍 SERVER: Sending targeted phrase to iOS client:');
        console.log('🔍 SERVER: First phrase data:', JSON.stringify(phrasesData[0], null, 2));
      }
      
      res.json({
        phrases: phrasesData,
        count: phrases.length,
        timestamp: new Date().toISOString()
      });
      
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

  // Download phrases for offline play
  router.get('/api/phrases/download/:playerId', async (req, res) => {
    try {
      if (!getDatabaseStatus()) {
        return res.status(503).json({
          error: 'Database connection required for phrase download'
        });
      }
      
      const { playerId } = req.params;
      const countParam = req.query.count;
      const count = countParam !== undefined ? parseInt(countParam) : 15;
      
      // Validate UUID format
      const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      if (!uuidRegex.test(playerId)) {
        return res.status(400).json({
          error: 'Invalid player ID format'
        });
      }
      
      // Validate count parameter
      if (countParam !== undefined && (isNaN(count) || count < 1 || count > 50)) {
        return res.status(400).json({
          error: 'Count must be between 1 and 50'
        });
      }
      
      // Validate that player exists in database
      const player = await DatabasePlayer.getPlayerById(playerId);
      if (!player) {
        return res.status(404).json({ 
          error: 'Player not found' 
        });
      }
      
      // Get phrases for offline download
      const phrases = await DatabasePhrase.getOfflinePhrases(playerId, count);
      
      console.log(`📱 Phrases downloaded for offline play: ${phrases.length} phrases for player ${player.name}`);
      
      // Set appropriate message
      let message = `Downloaded ${phrases.length} phrases for offline play`;
      
      if (phrases.length === 0) {
        // Check if there are any global phrases available at all
        const totalGlobalResult = await query(`
          SELECT COUNT(*) as total
          FROM phrases p
          WHERE p.is_global = true 
            AND p.is_approved = true
            AND p.created_by_player_id != $1
        `, [playerId]);
        
        const totalAvailable = parseInt(totalGlobalResult.rows[0].total);
        
        if (totalAvailable === 0) {
          message = "No global phrases are currently available. Check back soon for new content!";
        } else {
          message = "No new phrases available for download at this time";
        }
      }
      
      res.json({
        success: true,
        phrases: phrases.map(p => p.getPublicInfo()),
        count: phrases.length,
        requestedCount: count,
        timestamp: new Date().toISOString(),
        message: message
      });
      
    } catch (error) {
      console.error('❌ Error downloading phrases:', error);
      
      // Handle UUID format errors as client errors (400)
      if (error.message && error.message.includes('invalid input syntax for type uuid')) {
        return res.status(400).json({
          error: 'Invalid player ID format'
        });
      }
      
      res.status(500).json({ 
        error: 'Failed to download phrases' 
      });
    }
  });

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