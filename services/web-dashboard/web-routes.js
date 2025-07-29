const express = require('express');
const path = require('path');
// Link generator is now a separate service - use HTTP calls instead
const { pool } = require('./shared/database/connection');
const DatabasePlayer = require('./shared/database/models/DatabasePlayer');
const DatabasePhrase = require('./shared/database/models/DatabasePhrase');
const { HintSystem } = require('./shared/services/hintSystem');
const { detectLanguage } = require('./shared/services/difficultyScorer');

const router = express.Router();
// Link generator is now a separate service - TODO: Use HTTP calls to link-generator service

// Serve static files for the web dashboard
router.use(express.static(path.join(__dirname, '../public')));

// MONITORING DASHBOARD ROUTES

// Serve monitoring dashboard
router.get('/monitoring', (req, res) => {
    res.sendFile(path.join(__dirname, '../public/monitoring/index.html'));
});

// Get monitoring stats
router.get('/api/monitoring/stats', async (req, res) => {
    try {
        const stats = await getMonitoringStats();
        res.json(stats);
    } catch (error) {
        console.error('Error fetching monitoring stats:', error);
        res.status(500).json({ error: 'Failed to fetch monitoring stats' });
    }
});

// CONTRIBUTION SYSTEM ROUTES

// Generate contribution link
router.post('/api/contribution/request', async (req, res) => {
    try {
        const { playerId, expirationHours = 48, maxUses = 3, customMessage } = req.body;
        
        if (!playerId) {
            return res.status(400).json({ error: 'Player ID is required' });
        }

        // Verify player exists
        const player = await DatabasePlayer.findById(playerId);
        if (!player) {
            return res.status(404).json({ error: 'Player not found' });
        }

        // TODO: Replace with HTTP call to link-generator service
        // const link = await linkGenerator.createContributionLink(playerId, {
        const link = { error: 'Link generator service not connected yet' }; // {
            expirationHours,
            maxUses,
            customMessage
        });

        res.status(201).json({
            success: true,
            link: link
        });
    } catch (error) {
        console.error('Error creating contribution link:', error);
        res.status(500).json({ error: 'Failed to create contribution link' });
    }
});

// Get contribution link details
router.get('/api/contribution/:token', async (req, res) => {
    try {
        const { token } = req.params;
        
        const validation = await linkGenerator.validateToken(token);
        
        if (!validation.valid) {
            return res.status(400).json({ error: validation.reason });
        }

        res.json({
            success: true,
            link: validation.link
        });
    } catch (error) {
        console.error('Error validating contribution token:', error);
        res.status(500).json({ error: 'Failed to validate contribution link' });
    }
});

// Submit phrase via contribution link
router.post('/api/contribution/:token/submit', async (req, res) => {
    try {
        const { token } = req.params;
        const { phrase, clue, language = 'en', contributorName } = req.body;
        
        // Validate token
        const validation = await linkGenerator.validateToken(token);
        if (!validation.valid) {
            return res.status(400).json({ error: validation.reason });
        }

        // Validate phrase
        if (!phrase || typeof phrase !== 'string') {
            return res.status(400).json({ error: 'Phrase is required' });
        }

        const trimmedPhrase = phrase.trim();
        if (trimmedPhrase.length < 3) {
            return res.status(400).json({ error: 'Phrase must be at least 3 characters long' });
        }

        if (trimmedPhrase.length > 200) {
            return res.status(400).json({ error: 'Phrase must be less than 200 characters' });
        }

        // Validate clue if provided
        if (clue && typeof clue === 'string' && clue.trim().length > 500) {
            return res.status(400).json({ error: 'Clue must be less than 500 characters' });
        }

        // Validate language
        if (!['en', 'sv'].includes(language)) {
            return res.status(400).json({ error: 'Invalid language' });
        }

        // Create the phrase using the same logic as the app
        const finalClue = clue && clue.trim() ? clue.trim() : 'No clue provided';
        const detectedLanguage = detectLanguage(trimmedPhrase) || language;
        
        // Create phrase in database
        const phraseData = {
            content: trimmedPhrase,
            hint: finalClue,
            language: detectedLanguage,
            createdByPlayerId: null, // External contribution
            targetPlayerId: validation.link.requestingPlayerId,
            source: 'external',
            contributionLinkId: validation.link.id
        };

        const createdPhrase = await DatabasePhrase.create(phraseData);
        
        if (!createdPhrase) {
            return res.status(500).json({ error: 'Failed to create phrase' });
        }

        // Record the contribution
        const contributorInfo = {
            name: contributorName || null,
            ip: req.ip || req.connection.remoteAddress
        };

        const recordResult = await linkGenerator.recordContribution(token, contributorInfo);

        res.status(201).json({
            success: true,
            phrase: {
                id: createdPhrase.id,
                content: createdPhrase.content,
                hint: createdPhrase.hint,
                language: createdPhrase.language
            },
            remainingUses: recordResult.remainingUses,
            message: 'Phrase submitted successfully!'
        });

    } catch (error) {
        console.error('Error submitting contribution:', error);
        res.status(500).json({ error: 'Failed to submit phrase' });
    }
});

// Serve contribution form
router.get('/contribute/:token', (req, res) => {
    res.sendFile(path.join(__dirname, '../public/contribute/index.html'));
});

// Get player's contribution links
router.get('/api/contribution/links/:playerId', async (req, res) => {
    try {
        const { playerId } = req.params;
        const { activeOnly = true } = req.query;
        
        const links = await linkGenerator.getPlayerContributionLinks(playerId, activeOnly === 'true');
        
        res.json({
            success: true,
            links: links
        });
    } catch (error) {
        console.error('Error fetching player contribution links:', error);
        res.status(500).json({ error: 'Failed to fetch contribution links' });
    }
});

// Deactivate contribution link
router.delete('/api/contribution/links/:linkId', async (req, res) => {
    try {
        const { linkId } = req.params;
        const { playerId } = req.body;
        
        if (!playerId) {
            return res.status(400).json({ error: 'Player ID is required' });
        }

        const result = await linkGenerator.deactivateLink(linkId, playerId);
        
        res.json({
            success: true,
            message: 'Link deactivated successfully'
        });
    } catch (error) {
        console.error('Error deactivating contribution link:', error);
        res.status(500).json({ error: 'Failed to deactivate contribution link' });
    }
});

// Get contribution stats
router.get('/api/contribution/stats', async (req, res) => {
    try {
        const stats = await linkGenerator.getContributionStats();
        res.json(stats);
    } catch (error) {
        console.error('Error fetching contribution stats:', error);
        res.status(500).json({ error: 'Failed to fetch contribution stats' });
    }
});

// HELPER FUNCTIONS

async function getMonitoringStats() {
    try {
        const [playersResult, phrasesResult, todayPhrasesResult] = await Promise.all([
            pool.query('SELECT COUNT(*) as count FROM players WHERE is_active = true AND last_seen > NOW() - INTERVAL \'5 minutes\''),
            pool.query('SELECT COUNT(*) as count FROM phrases WHERE created_at > NOW() - INTERVAL \'24 hours\''),
            pool.query('SELECT COUNT(*) as count FROM phrases WHERE created_at > CURRENT_DATE')
        ]);

        const completedResult = await pool.query(`
            SELECT 
                COUNT(*) as completed,
                COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM phrases WHERE created_at > NOW() - INTERVAL '24 hours'), 0) as completion_rate
            FROM completed_phrases cp
            JOIN phrases p ON cp.phrase_id = p.id
            WHERE cp.completed_at > NOW() - INTERVAL '24 hours'
        `);

        return {
            onlinePlayers: parseInt(playersResult.rows[0].count),
            activePhrases: parseInt(phrasesResult.rows[0].count),
            phrasesToday: parseInt(todayPhrasesResult.rows[0].count),
            completionRate: Math.round(parseFloat(completedResult.rows[0].completion_rate || 0))
        };
    } catch (error) {
        console.error('Error calculating monitoring stats:', error);
        return {
            onlinePlayers: 0,
            activePhrases: 0,
            phrasesToday: 0,
            completionRate: 0
        };
    }
}

module.exports = router;