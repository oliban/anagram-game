const express = require('express');
const path = require('path');
const router = express.Router();

// Helper function to get weighted random emojis with proper rarity distribution
async function getRandomEmojisForPhrase(client, numberOfDrops = Math.floor(Math.random() * 2) + 1) {
    // Get all active emojis with their drop rates
    const emojisResult = await client.query(`
        SELECT * FROM emoji_catalog 
        WHERE is_active = true 
        ORDER BY id
    `);
    
    const allEmojis = emojisResult.rows;
    const droppedEmojis = [];
    
    // Calculate total weight for proper weighted random selection
    const totalWeight = allEmojis.reduce((sum, emoji) => sum + parseFloat(emoji.drop_rate_percentage), 0);
    
    // Create a Set to track already selected emojis (avoid duplicates in same drop)
    const selectedEmojiIds = new Set();
    
    for (let i = 0; i < numberOfDrops; i++) {
        let attempts = 0;
        let selectedEmoji = null;
        let lastRandomValue = 0;
        
        // Try up to 10 times to get a unique emoji (avoid duplicates)
        while (attempts < 10) {
            // Generate random number between 0 and totalWeight
            const randomValue = Math.random() * totalWeight;
            lastRandomValue = randomValue;
            
            // Find the emoji using proper weighted selection
            let cumulativeWeight = 0;
            
            for (const emoji of allEmojis) {
                cumulativeWeight += parseFloat(emoji.drop_rate_percentage);
                if (randomValue <= cumulativeWeight) {
                    // Check if we already selected this emoji
                    if (numberOfDrops > 1 && selectedEmojiIds.has(emoji.id)) {
                        attempts++;
                        break; // Try again
                    }
                    selectedEmoji = emoji;
                    selectedEmojiIds.add(emoji.id);
                    break;
                }
            }
            
            if (selectedEmoji) break;
        }
        
        // Fallback to first unselected emoji if no selection made
        if (!selectedEmoji) {
            selectedEmoji = allEmojis.find(e => !selectedEmojiIds.has(e.id)) || allEmojis[0];
            console.warn('⚠️ EMOJI: Fallback selection used after 10 attempts');
        }
        
        droppedEmojis.push(selectedEmoji);
        
        console.log(`🎲 EMOJI SELECTION: Random ${lastRandomValue.toFixed(3)} / ${totalWeight.toFixed(3)} -> ${selectedEmoji.emoji_character} (${selectedEmoji.rarity_tier}, ${selectedEmoji.drop_rate_percentage}%)`);
    }
    
    return droppedEmojis;
}

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

  // Helper function to fetch skipped phrases as fallback
  async function getSkippedPhrasesForPlayer(playerId, maxDifficulty = null) {
    const difficultyFilter = maxDifficulty ? 'AND p.difficulty_level <= $2' : '';
    const queryParams = maxDifficulty ? [playerId, maxDifficulty] : [playerId];
    
    const skippedPhrasesQuery = `
      SELECT DISTINCT p.* 
      FROM phrases p
      INNER JOIN skipped_phrases sp ON p.id = sp.phrase_id
      WHERE sp.player_id = $1
        AND p.is_global = true 
        AND p.is_approved = true
        AND p.created_by_player_id != $1
        ${difficultyFilter}
      ORDER BY sp.skipped_at ASC
      LIMIT 25
    `;
    
    const result = await query(skippedPhrasesQuery, queryParams);
    return result.rows.map(row => new DatabasePhrase(row));
  }

  // Helper function to clear skipped status for phrases we're serving again
  async function clearSkippedPhrasesForPlayer(playerId, phraseIds) {
    if (phraseIds.length === 0) return;
    
    const placeholders = phraseIds.map((_, index) => `$${index + 2}`).join(',');
    const clearSkipQuery = `
      DELETE FROM skipped_phrases 
      WHERE player_id = $1 AND phrase_id IN (${placeholders})
    `;
    
    await query(clearSkipQuery, [playerId, ...phraseIds]);
    console.log(`🔄 SKIP CLEAR: Cleared skip status for ${phraseIds.length} phrases for player ${playerId}`);
  }

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

      // Handle external contributions (null senderId)
      let sender = null;
      if (senderId) {
        sender = await DatabasePlayer.getPlayerById(senderId);
        if (!sender) {
          return res.status(404).json({
            error: 'Sender player not found'
          });
        }
      } else {
        // External contribution - create a virtual sender
        sender = {
          id: null,
          name: req.body.contributorName || 'Anonymous Contributor'
        };
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
          if (senderId && target.id === senderId) {
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
          
          console.log(`🔧 WEBSOCKET FIX: Set targetId = ${phraseData.targetId}, senderName = ${phraseData.senderName}`);
          
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
      
      // If no phrases available, try skipped phrases as fallback
      if (phrases.length === 0) {
        console.log(`🌍 PHRASE: No fresh phrases available for player ${playerId}, trying skipped phrases as fallback...`);
        
        try {
          // Fetch skipped phrases as fallback - remove the exclusion filter
          const skippedPhrases = await getSkippedPhrasesForPlayer(playerId, maxDifficulty);
          
          if (skippedPhrases.length > 0) {
            phrases = skippedPhrases;
            
            // Remove these phrases from skipped_phrases table since we're serving them again
            const phraseIds = phrases.map(p => p.getPublicInfo().id);
            await clearSkippedPhrasesForPlayer(playerId, phraseIds);
            
            console.log(`♻️ PHRASE: Found ${phrases.length} skipped phrases as fallback for player ${playerId}, cleared skip status`);
          } else {
            console.log(`🌍 PHRASE: No phrases available at all for player ${playerId} (including skipped)`);
            return res.status(404).json({
              error: 'No phrases available for player'
            });
          }
        } catch (fallbackError) {
          console.error('❌ PHRASE FALLBACK: Error fetching skipped phrases:', fallbackError);
          return res.status(404).json({
            error: 'No phrases available for player'
          });
        }
      }
      
      // Import difficulty scoring algorithm for client-side hint system
      const { calculateScore } = require('../shared/services/difficultyScorer');
      
      // Convert ALL phrases to CustomPhrase format that iOS NetworkManager expects
      // Use Promise.all to generate emojis for each phrase in parallel
      const client = await pool.connect();
      let customPhrasesFormat;
      try {
        customPhrasesFormat = await Promise.all(phrases.map(async phrase => {
          const phraseInfo = phrase.getPublicInfo();
          
          // Calculate base score for each phrase
          const baseScore = calculateScore({ 
            phrase: phraseInfo.content, 
            language: phraseInfo.language || 'en' 
          });
          
          // Generate 1-2 random emojis for this phrase
          const phraseEmojis = await getRandomEmojisForPhrase(client);
          
          console.log(`🔍 CLUE DEBUG: Phrase "${phraseInfo.content}" - hint from DB: "${phraseInfo.hint}", mapped to clue: "${phraseInfo.hint || ''}", theme: "${phraseInfo.theme || 'null'}"`);
          console.log(`🎲 EMOJI: Generated ${phraseEmojis.length} emojis for phrase "${phraseInfo.content}": ${phraseEmojis.map(e => e.emoji_character).join(', ')}`);
          
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
            difficultyLevel: phraseInfo.difficultyLevel || baseScore,
            // Add emoji data for each phrase
            celebrationEmojis: phraseEmojis.map(emoji => ({
              id: emoji.id,
              emoji_character: emoji.emoji_character,
              name: emoji.name,
              rarity_tier: emoji.rarity_tier,
              drop_rate_percentage: parseFloat(emoji.drop_rate_percentage),
              points_reward: emoji.points_reward,
              unicode_version: emoji.unicode_version,
              is_active: emoji.is_active,
              created_at: emoji.created_at
            }))
          };
        }));
      } finally {
        client.release();
      }
      
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
      const { playerId, hintsUsed, completionTime, celebrationEmojis } = req.body;
      
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
      
      // Process celebration emoji collection
      let emojiCollectionResult = {
        collectedEmojis: [],
        newDiscoveries: [],
        pointsEarned: 0,
        triggeredGlobalDrop: false,
        globalDropMessage: null
      };
      
      if (celebrationEmojis && Array.isArray(celebrationEmojis) && celebrationEmojis.length > 0) {
        console.log(`🎲 EMOJI: Processing ${celebrationEmojis.length} celebration emojis for phrase completion`);
        
        const client = await pool.connect();
        try {
          await client.query('BEGIN');
          
          // Process each celebration emoji for collection
          for (const emojiData of celebrationEmojis) {
            // Check if player already has this emoji
            const existingCollection = await client.query(
              'SELECT id FROM player_emoji_collections WHERE player_id = $1 AND emoji_id = $2',
              [playerId, emojiData.id]
            );
            
            emojiCollectionResult.collectedEmojis.push(emojiData);
            
            // If it's a new discovery for this player
            if (existingCollection.rows.length === 0) {
              // Check if this is the first global discovery
              const globalDiscovery = await client.query(
                'SELECT id FROM emoji_global_discoveries WHERE emoji_id = $1',
                [emojiData.id]
              );
              
              const isFirstGlobalDiscovery = globalDiscovery.rows.length === 0;
              
              // Add to player's collection
              await client.query(
                'INSERT INTO player_emoji_collections (player_id, emoji_id, is_first_global_discovery) VALUES ($1, $2, $3)',
                [playerId, emojiData.id, isFirstGlobalDiscovery]
              );
              
              // If first global discovery, add to global discoveries
              if (isFirstGlobalDiscovery) {
                await client.query(
                  'INSERT INTO emoji_global_discoveries (emoji_id, first_discoverer_id) VALUES ($1, $2)',
                  [emojiData.id, playerId]
                );
                
                // Check if this triggers global drops (Epic or rarer: <= 5%)
                if (emojiData.drop_rate_percentage <= 5.0) {
                  emojiCollectionResult.triggeredGlobalDrop = true;
                  emojiCollectionResult.globalDropMessage = `🌟 ${player.name} discovered ${emojiData.emoji_character} (${emojiData.rarity_tier})! Everyone gets bonus drops!`;
                }
              }
              
              // Add points for the discovery
              emojiCollectionResult.pointsEarned += emojiData.points_reward;
              emojiCollectionResult.newDiscoveries.push(emojiData);
              
              console.log(`🆕 NEW DISCOVERY: ${emojiData.emoji_character} (${emojiData.rarity_tier}) for player ${playerId}`);
            }
          }
          
          // Update player's total emoji points if any points were earned
          if (emojiCollectionResult.pointsEarned > 0) {
            await client.query(
              'UPDATE players SET total_emoji_points = COALESCE(total_emoji_points, 0) + $1 WHERE id = $2',
              [emojiCollectionResult.pointsEarned, playerId]
            );
          }
          
          await client.query('COMMIT');
          console.log(`✨ Emoji collection complete - ${emojiCollectionResult.pointsEarned} points earned, ${emojiCollectionResult.newDiscoveries.length} new discoveries`);
          
        } catch (emojiError) {
          await client.query('ROLLBACK');
          console.error('❌ Error processing emoji collection:', emojiError);
          // Don't fail the phrase completion if emoji collection fails
        } finally {
          client.release();
        }
      }
      
      const completionResult = {
        success: true,
        completion: {
          finalScore: finalScore,
          hintsUsed: hintsUsed,
          completionTime: completionTime
        },
        emojiCollection: emojiCollectionResult,
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