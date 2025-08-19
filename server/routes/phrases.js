const express = require('express');
const path = require('path');
const router = express.Router();

// Helper function to get weighted random emojis with proper rarity distribution
async function getRandomEmojisForPhrase(client, numberOfDrops = Math.floor(Math.random() * 2) + 1) {
    try {
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
        
    } catch (error) {
        // If emoji_catalog table doesn't exist, return empty array
        if (error.code === '42P01') {
            console.log('📊 EMOJI: emoji_catalog table not found, skipping emoji generation');
            return [];
        }
        throw error;
    }
}

// Phrase routes - CRUD operations, approval, consumption, and analysis

module.exports = (dependencies) => {
  const { 
    getDatabaseStatus, 
    DatabasePlayer, 
    DatabasePhrase, 
    ScoringSystem,
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
      SELECT DISTINCT p.*, sp.skipped_at 
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

  // Enhanced phrase creation endpoint with validation
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
        theme: theme, // Pass theme to database layer
        contributorName: req.body.contributorName // Pass contributor name for external contributions
      });

      const { phrase, targetCount, isGlobal: phraseIsGlobal } = result;

      console.log(`📝 Enhanced phrase created: "${content}" from ${sender.name}${phraseIsGlobal ? ' (global)' : ` to ${targetCount} players`}`);

      // Send real-time notifications to target players
      console.log(`🔍 DEBUG: validTargets count = ${validTargets.length}`);
      validTargets.forEach((t, i) => console.log(`🔍 DEBUG: target[${i}] = ${t.name}, socketId = ${t.socketId}`));
      const notifications = [];
      for (const target of validTargets) {
        if (target.socketId) {
          const phraseData = phrase.getPublicInfo();
          // Ensure targetId is set for iOS client priority queue
          phraseData.targetId = target.id;
          // Map hint to clue for iOS compatibility (iOS expects 'clue' field)
          phraseData.clue = phraseData.hint || '';
          // Override senderName with actual sender from player lookup
          console.log(`🔍 DEBUG: sender object =`, sender);
          console.log(`🔍 DEBUG: sender.name = "${sender?.name}", sender.id = "${sender?.id}"`);
          const actualSenderName = sender?.name || 'Unknown Player';
          
          console.log(`🔧 WEBSOCKET: Sending phrase to ${target.name} - targetId = ${phraseData.targetId}, senderName = ${actualSenderName}, clue = "${phraseData.clue}", contributorName = ${phrase.contributorName || 'null'}`);
          
          io.to(target.socketId).emit('new-phrase', {
            phrase: phraseData,
            senderName: actualSenderName, // Use actual sender name from player lookup
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
      const { calculateScore } = require('../../shared/difficulty-algorithm');
      
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
          
          // DEBUG: Show all phraseInfo keys for computing phrases
          if (['ny kod', 'stark cpu', 'sql fråga'].includes(phraseInfo.content)) {
            console.log(`🔍 PHRASEINFO KEYS: "${phraseInfo.content}" - keys: ${Object.keys(phraseInfo).join(', ')}`);
            console.log(`🔍 PHRASEINFO THEME: "${phraseInfo.content}" - theme value: "${phraseInfo.theme}" (type: ${typeof phraseInfo.theme})`);
          }
          
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
      // Use the difficulty algorithm from the main server shared location
      const { calculateScore } = require('../../shared/difficulty-algorithm');
      const baseScore = calculateScore({ 
        phrase: phrase.content, 
        language: phrase.language || 'en' 
      });
      
      // Apply hint penalties: Level 1 = 20%, Level 2 = 40%, Level 3 = 60%
      let finalScore = baseScore;
      if (hintsUsed >= 1) finalScore = Math.round(baseScore * 0.8); // 20% penalty → 80% remaining
      if (hintsUsed >= 2) finalScore = Math.round(baseScore * 0.6); // 40% penalty → 60% remaining  
      if (hintsUsed >= 3) finalScore = Math.round(baseScore * 0.4); // 60% penalty → 40% remaining
      
      // Ensure minimum score
      finalScore = Math.max(1, finalScore);
      
      // Use transaction to ensure atomicity of completion process
      let completionResult;
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        
        completionResult = await (async () => {
        // First check if this is a targeted phrase in player_phrases table
        const targetedResult = await client.query(`
          UPDATE player_phrases 
          SET is_delivered = true, delivered_at = CURRENT_TIMESTAMP
          WHERE phrase_id = $1 AND is_delivered = false
          RETURNING *
        `, [phraseId]);

        // If not a targeted phrase, check if it's a global phrase
        let consumeSuccess = targetedResult.rows.length > 0;
        
        if (!consumeSuccess) {
          // Check if it's a global phrase that exists and hasn't been completed by this player
          const globalCheck = await client.query(`
            SELECT p.id 
            FROM phrases p 
            WHERE p.id = $1 
            AND p.is_global = true 
            AND p.is_approved = true
            AND NOT EXISTS (SELECT 1 FROM completed_phrases WHERE player_id = $2 AND phrase_id = $1)
          `, [phraseId, playerId]);
          
          consumeSuccess = globalCheck.rows.length > 0;
          
          if (!consumeSuccess) {
            console.warn(`⚠️ COMPLETE: Could not mark phrase ${phraseId} as consumed (phrase not found, not global, or already completed by player)`);
            return { consumeSuccess: false };
          } else {
            console.log(`✅ DATABASE: Global phrase ${phraseId} ready for completion`);
          }
        } else {
          console.log(`✅ DATABASE: Targeted phrase ${phraseId} marked as consumed within transaction`);
        }
        
        console.log(`✅ DATABASE: Phrase ${phraseId} marked as consumed within transaction`);

        // Record completion in completed_phrases table within same transaction
        try {
          await client.query(`
            INSERT INTO completed_phrases (player_id, phrase_id, score, completion_time_ms)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (player_id, phrase_id) DO NOTHING
          `, [playerId, phraseId, finalScore, completionTime]);
          console.log(`✅ DATABASE: Completion recorded for phrase ${phraseId}`);
        } catch (completionError) {
          console.warn(`⚠️ COMPLETE: Could not record completion: ${completionError.message}`);
          // Don't fail transaction for completion recording issues
        }

        return { consumeSuccess: true };
        })();
        
        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }

      if (!completionResult.consumeSuccess) {
        return res.status(409).json({
          error: 'Phrase not available for completion (already completed or not assigned to player)'
        });
      }
      
      // Process celebration emoji collection AND update score aggregations in single transaction
      let emojiCollectionResult = {
        collectedEmojis: [],
        newDiscoveries: [],
        pointsEarned: 0,
        triggeredGlobalDrop: false,
        globalDropMessage: null
      };
      
      // Use single transaction for emoji collection + score aggregation update
      const emojiClient = await pool.connect();
      try {
        await emojiClient.query('BEGIN');
        
        // Process celebration emojis if any
        if (celebrationEmojis && Array.isArray(celebrationEmojis) && celebrationEmojis.length > 0) {
          console.log(`🎲 EMOJI: Processing ${celebrationEmojis.length} celebration emojis for phrase completion`);
          
          // Process each celebration emoji for collection
          for (const emojiData of celebrationEmojis) {
            // Check if player already has this emoji
            const existingCollection = await emojiClient.query(
              'SELECT id FROM player_emoji_collections WHERE player_id = $1 AND emoji_id = $2',
              [playerId, emojiData.id]
            );
            
            emojiCollectionResult.collectedEmojis.push(emojiData);
            
            // If it's a new discovery for this player
            if (existingCollection.rows.length === 0) {
              // Check if this is the first global discovery
              const globalDiscovery = await emojiClient.query(
                'SELECT id FROM emoji_global_discoveries WHERE emoji_id = $1',
                [emojiData.id]
              );
              
              const isFirstGlobalDiscovery = globalDiscovery.rows.length === 0;
              
              // Add to player's collection
              await emojiClient.query(
                'INSERT INTO player_emoji_collections (player_id, emoji_id, is_first_global_discovery) VALUES ($1, $2, $3)',
                [playerId, emojiData.id, isFirstGlobalDiscovery]
              );
              
              // If first global discovery, add to global discoveries
              if (isFirstGlobalDiscovery) {
                await emojiClient.query(
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
            await emojiClient.query(
              'UPDATE players SET total_emoji_points = COALESCE(total_emoji_points, 0) + $1 WHERE id = $2',
              [emojiCollectionResult.pointsEarned, playerId]
            );
          }
          
          console.log(`✨ Emoji collection complete - ${emojiCollectionResult.pointsEarned} points earned, ${emojiCollectionResult.newDiscoveries.length} new discoveries`);
        }
        
        await emojiClient.query('COMMIT');
        console.log(`✨ Emoji collection transaction committed`);
        
      } catch (error) {
        await emojiClient.query('ROLLBACK');
        console.error('❌ Error processing emoji collection:', error);
        // Don't fail the phrase completion if emoji collection fails
      } finally {
        emojiClient.release();
      }
      
      // 🚨 CRITICAL: Update player score aggregations after completion
      try {
        console.log(`📊 SCORING: About to update score aggregations for player ${playerId}`);
        console.log(`📊 SCORING: ScoringSystem available:`, typeof ScoringSystem);
        console.log(`📊 SCORING: updatePlayerScores method:`, typeof ScoringSystem.updatePlayerScores);
        
        await ScoringSystem.updatePlayerScores(playerId);
        console.log(`📊 SCORING: Successfully updated score aggregations for player ${playerId} after phrase completion`);
      } catch (scoringError) {
        console.error('❌ SCORING: Error updating player score aggregations:', scoringError);
        console.error('❌ SCORING: Error stack:', scoringError.stack);
        // Don't fail the response if scoring update fails
      }
      
      const apiResponse = {
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
      
      res.status(200).json(apiResponse);
      
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
      
      // Validate phrase follows game rules (2-4 words, max 7 chars per word)
      const words = phrase.trim().split(/\s+/);
      
      if (words.length < 2) {
        return res.status(400).json({
          error: 'Phrase must contain at least 2 words'
        });
      }
      
      if (words.length > 4) {
        return res.status(400).json({
          error: 'Phrase cannot contain more than 4 words'
        });
      }
      
      // Check each word length (max 7 characters)
      for (let word of words) {
        if (word.length > 7) {
          return res.status(400).json({
            error: `Word "${word}" is too long (maximum 7 characters per word)`
          });
        }
      }
      
      // Validate language
      const { LANGUAGES, calculateScore, getDifficultyLabel } = require('../../shared/difficulty-algorithm');
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