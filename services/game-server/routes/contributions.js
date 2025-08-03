const express = require('express');
const router = express.Router();

module.exports = (dependencies) => {
  const { DatabasePhrase, DatabasePlayer, io, query } = dependencies;

  // Submit phrase via contribution link - External contributions only
  router.post('/api/contribution/:token/submit', async (req, res) => {
    try {
      const { token } = req.params;
      const { phrase, clue, language = 'en', contributorName } = req.body;
      
      console.log(`📝 CONTRIB: Submitting external phrase for token: ${token}`);
      
      // Validate token by querying database directly
      const linkQuery = `
        SELECT 
          cl.id,
          cl.token,
          cl.requesting_player_id,
          cl.expires_at,
          cl.max_uses,
          cl.current_uses,
          cl.is_active,
          p.name as requesting_player_name
        FROM contribution_links cl
        JOIN players p ON cl.requesting_player_id = p.id
        WHERE cl.token = $1
      `;
      
      const linkResult = await query(linkQuery, [token]);
      
      if (linkResult.rows.length === 0) {
        console.log(`❌ CONTRIB: Token not found: ${token}`);
        return res.status(400).json({ 
          success: false, 
          error: 'Invalid contribution token' 
        });
      }

      const link = linkResult.rows[0];
      
      // Check if link is valid
      if (!link.is_active) {
        return res.status(400).json({ 
          success: false, 
          error: 'Link has been deactivated' 
        });
      }

      if (new Date() > new Date(link.expires_at)) {
        return res.status(400).json({ 
          success: false, 
          error: 'Link has expired' 
        });
      }

      if (link.current_uses >= link.max_uses) {
        return res.status(400).json({ 
          success: false, 
          error: 'Link usage limit reached' 
        });
      }

      console.log(`✅ CONTRIB: Valid token for player: ${link.requesting_player_name}`);

      // Validate phrase content - same rules as in-game but with external source
      if (!phrase || typeof phrase !== 'string') {
        return res.status(400).json({ 
          success: false, 
          error: 'Phrase is required' 
        });
      }

      const trimmedPhrase = phrase.trim();
      if (trimmedPhrase.length < 3) {
        return res.status(400).json({ 
          success: false, 
          error: 'Phrase must be at least 3 characters long' 
        });
      }

      if (trimmedPhrase.length > 200) {
        return res.status(400).json({ 
          success: false, 
          error: 'Phrase must be less than 200 characters' 
        });
      }

      // Count words (same logic as in-game phrases)
      const wordCount = trimmedPhrase.split(/\s+/).filter(word => word.length > 0).length;
      if (wordCount < 2) {
        return res.status(400).json({ 
          success: false, 
          error: 'Phrase must contain at least 2 words' 
        });
      }

      if (wordCount > 6) {
        return res.status(400).json({ 
          success: false, 
          error: 'Phrase must contain no more than 6 words' 
        });
      }

      // Validate clue
      const finalClue = clue && clue.trim() ? clue.trim() : 'No clue provided';
      if (finalClue.length > 500) {
        return res.status(400).json({ 
          success: false, 
          error: 'Clue must be less than 500 characters' 
        });
      }

      // Validate language
      if (!['en', 'sv'].includes(language)) {
        return res.status(400).json({ 
          success: false, 
          error: 'Invalid language' 
        });
      }

      // Validate contributor name (optional, but if provided must be reasonable)
      if (contributorName && contributorName.trim && contributorName.trim().length > 50) {
        return res.status(400).json({ 
          success: false, 
          error: 'Contributor name must be 50 characters or less' 
        });
      }

      // Create phrase using DatabasePhrase with external source
      const createdPhrase = await DatabasePhrase.createPhrase({
        content: trimmedPhrase,
        hint: finalClue,
        language: language,
        senderId: null, // External contribution
        targetId: link.requesting_player_id,
        contributionLinkId: link.id,
        source: 'external', // Mark as external contribution
        contributorName: contributorName || null // Store contributor name directly
      });
      
      if (!createdPhrase) {
        console.log(`❌ CONTRIB: Failed to create phrase "${trimmedPhrase}"`);
        return res.status(500).json({ 
          success: false, 
          error: 'Failed to create phrase' 
        });
      }

      // Record the contribution by updating link usage
      await query(`
        UPDATE contribution_links 
        SET current_uses = current_uses + 1,
            contributor_name = COALESCE(contributor_name, $2),
            contributor_ip = $3,
            used_at = CURRENT_TIMESTAMP
        WHERE token = $1
      `, [token, contributorName || null, req.ip || req.connection.remoteAddress]);

      const remainingUses = link.max_uses - link.current_uses - 1;

      // Send real-time notification to target player
      const target = await DatabasePlayer.getPlayerById(link.requesting_player_id);
      if (target && target.socketId) {
        const phraseData = createdPhrase.getPublicInfo();
        phraseData.targetId = link.requesting_player_id;
        phraseData.senderName = contributorName || 'Anonymous Contributor';
        
        io.to(target.socketId).emit('new-phrase', {
          phrase: phraseData,
          senderName: contributorName || 'Anonymous Contributor',
          timestamp: new Date().toISOString()
        });
        console.log(`📨 CONTRIB: Sent notification to ${target.name} for external contribution "${trimmedPhrase}"`);
      } else {
        console.log(`📨 CONTRIB: Target player not connected - phrase queued for later delivery`);
      }

      console.log(`✅ CONTRIB: External phrase created successfully - "${trimmedPhrase}" by ${contributorName || 'Anonymous'}`);

      res.status(201).json({
        success: true,
        phrase: {
          id: createdPhrase.id,
          content: createdPhrase.content,
          hint: createdPhrase.hint,
          language: createdPhrase.language,
          source: 'external'
        },
        remainingUses: remainingUses,
        message: 'Phrase submitted successfully!'
      });

    } catch (error) {
      console.error('❌ CONTRIB: Error submitting external contribution:', error);
      res.status(500).json({ 
        success: false, 
        error: 'Failed to submit phrase' 
      });
    }
  });

  return router;
};