const express = require('express');
const router = express.Router();

// Admin routes - administrative operations and batch operations

module.exports = (dependencies) => {
  const { 
    getDatabaseStatus, 
    DatabasePhrase, 
    broadcastActivity, 
    io
  } = dependencies;

  // Batch phrase import endpoint for admins
  router.post('/api/admin/phrases/batch-import', async (req, res) => {
    try {
      if (!getDatabaseStatus()) {
        return res.status(503).json({
          error: 'Database connection required for batch phrase import'
        });
      }

      const { phrases, adminId = 'system' } = req.body; // adminId is optional, defaults to 'system' for logging

      // Validate required fields
      if (!phrases || !Array.isArray(phrases)) {
        return res.status(400).json({
          error: 'Phrases array is required'
        });
      }

      if (phrases.length === 0) {
        return res.status(400).json({
          error: 'Phrases array cannot be empty'
        });
      }

      if (phrases.length > 100) {
        return res.status(400).json({
          error: 'Maximum 100 phrases allowed per batch'
        });
      }

      // adminId is optional - if not provided, phrases will be created as system-generated

      console.log(`🔧 ADMIN: Batch import request - ${phrases.length} phrases from admin ${adminId}`);

      // Validate each phrase in the batch
      const validationErrors = [];
      for (let i = 0; i < phrases.length; i++) {
        const phrase = phrases[i];
        const index = i + 1;

        // Required fields for each phrase
        if (!phrase.content || typeof phrase.content !== 'string') {
          validationErrors.push(`Phrase ${index}: content is required and must be a string`);
          continue;
        }

        // Optional fields with defaults
        const {
          content,
          hint = '',
          targetIds = [],
          isGlobal = true, // Default to global for admin imports
          phraseType = 'community', // Default to community for admin imports  
          language = 'en'
        } = phrase;

        // Validate content length
        if (content.trim().length === 0) {
          validationErrors.push(`Phrase ${index}: content cannot be empty`);
        }

        if (content.length > 500) {
          validationErrors.push(`Phrase ${index}: content too long (max 500 characters)`);
        }

        // Validate hint length
        if (hint && hint.length > 300) {
          validationErrors.push(`Phrase ${index}: hint too long (max 300 characters)`);
        }

        // Validate language
        const validLanguages = ['en', 'sv', 'es', 'fr', 'de', 'it', 'pt', 'ru', 'zh', 'ja', 'ko', 'ar', 'hi', 'nl', 'no', 'da', 'fi', 'pl', 'tr', 'hu', 'cs', 'sk', 'hr', 'sr', 'bg', 'ro', 'el', 'he', 'th', 'vi', 'id', 'ms', 'uk', 'lt', 'lv', 'et', 'sl', 'mt', 'is'];
        if (!validLanguages.includes(language)) {
          validationErrors.push(`Phrase ${index}: invalid language '${language}'`);
        }

        // Validate phrase type
        const validTypes = ['custom', 'global', 'community', 'challenge'];
        if (!validTypes.includes(phraseType)) {
          validationErrors.push(`Phrase ${index}: invalid phrase type '${phraseType}'`);
        }

        // Validate targetIds if provided
        if (targetIds && (!Array.isArray(targetIds) || targetIds.some(id => typeof id !== 'string'))) {
          validationErrors.push(`Phrase ${index}: targetIds must be an array of strings`);
        }
      }

      // Return validation errors if any
      if (validationErrors.length > 0) {
        return res.status(400).json({
          error: 'Validation failed',
          validationErrors: validationErrors.slice(0, 10), // Limit to first 10 errors
          totalErrors: validationErrors.length
        });
      }

      // Process batch import
      const results = {
        successful: [],
        failed: [],
        totalProcessed: 0,
        totalSuccessful: 0,
        totalFailed: 0
      };

      console.log(`🔧 ADMIN: Starting batch processing of ${phrases.length} phrases...`);

      for (let i = 0; i < phrases.length; i++) {
        const phraseData = phrases[i];
        const index = i + 1;
        
        try {
          const {
            content,
            hint = '',
            targetIds = [],
            isGlobal = true,
            phraseType = 'community',
            language = 'en'
          } = phraseData;

          // Create enhanced phrase using existing logic
          // Use null senderId for admin batch imports (system-generated phrases)
          const result = await DatabasePhrase.createEnhancedPhrase({
            content: content.trim(),
            hint: hint.trim(),
            senderId: null, // System-generated phrases have no specific sender
            targetIds: targetIds,
            isGlobal,
            phraseType,
            language
          });

          const { phrase, targetCount, isGlobal: phraseIsGlobal } = result;

          results.successful.push({
            index,
            id: phrase.id,
            content: content.trim(),
            language,
            isGlobal: phraseIsGlobal,
            targetCount,
            difficulty: phrase.difficultyLevel
          });

          results.totalSuccessful++;

          console.log(`✅ ADMIN: Phrase ${index}/${phrases.length} created - "${content.trim()}" (${language})`);

        } catch (error) {
          console.error(`❌ ADMIN: Phrase ${index}/${phrases.length} failed:`, error.message);
          
          results.failed.push({
            index,
            content: phraseData.content?.substring(0, 50) || 'Unknown',
            error: error.message
          });

          results.totalFailed++;
        }

        results.totalProcessed++;
      }

      // Broadcast admin activity
      if (results.totalSuccessful > 0) {
        broadcastActivity('admin', `Admin batch import: ${results.totalSuccessful} phrases imported`, {
          adminId,
          totalPhrases: results.totalSuccessful,
          languages: [...new Set(results.successful.map(p => p.language))],
          timestamp: new Date().toISOString()
        });
      }

      // Determine response status
      const statusCode = results.totalFailed === 0 ? 201 : (results.totalSuccessful === 0 ? 400 : 207); // 207 = Multi-Status

      console.log(`🔧 ADMIN: Batch import complete - ${results.totalSuccessful} successful, ${results.totalFailed} failed`);

      res.status(statusCode).json({
        success: results.totalSuccessful > 0,
        message: `Batch import completed: ${results.totalSuccessful} successful, ${results.totalFailed} failed`,
        results: {
          summary: {
            totalProcessed: results.totalProcessed,
            totalSuccessful: results.totalSuccessful,
            totalFailed: results.totalFailed,
            successRate: Math.round((results.totalSuccessful / results.totalProcessed) * 100)
          },
          successful: results.successful,
          failed: results.failed.length > 0 ? results.failed : undefined
        },
        timestamp: new Date().toISOString()
      });

    } catch (error) {
      console.error('❌ ADMIN: Error in batch phrase import:', error);
      res.status(500).json({
        error: 'Failed to process batch import',
        details: process.env.NODE_ENV === 'development' ? error.message : undefined
      });
    }
  });

  return router;
};