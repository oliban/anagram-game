class ContributionForm {
    constructor() {
        this.token = null;
        this.linkData = null;
        this.isSubmitting = false;
        
        this.init();
    }

    init() {
        this.token = this.getTokenFromUrl();
        if (!this.token) {
            this.showError('Invalid contribution link');
            return;
        }

        this.setupEventListeners();
        this.loadContributionData();
    }

    getTokenFromUrl() {
        const pathParts = window.location.pathname.split('/');
        return pathParts[pathParts.length - 1];
    }

    setupEventListeners() {
        const form = document.getElementById('contribution-form');
        const phraseInput = document.getElementById('phrase-input');
        const themeInput = document.getElementById('theme-input');
        const clueInput = document.getElementById('clue-input');
        const languageSelect = document.getElementById('language-select-top');
        const contributorName = document.getElementById('contributor-name');
        const previewBtn = document.getElementById('preview-btn');
        const submitBtn = document.getElementById('submit-btn');

        form.addEventListener('submit', (e) => this.handleSubmit(e));
        
        phraseInput.addEventListener('input', (e) => this.handlePhraseInput(e));
        themeInput.addEventListener('input', (e) => this.handleThemeInput(e));
        clueInput.addEventListener('input', (e) => this.handleClueInput(e));
        languageSelect.addEventListener('change', (e) => this.handleLanguageChange(e));
        contributorName.addEventListener('input', (e) => this.handleContributorNameInput(e));
        
        previewBtn.addEventListener('click', () => this.previewScrambled());
        
        // Real-time validation
        phraseInput.addEventListener('blur', () => this.validatePhrase());
        themeInput.addEventListener('blur', () => this.validateTheme());
        clueInput.addEventListener('blur', () => this.validateClue());
        contributorName.addEventListener('blur', () => this.validateContributorName());
        
        // Live scramble preview when typing
        phraseInput.addEventListener('input', () => this.updateScramblePreview());
    }

    async loadContributionData() {
        console.log('Loading contribution data...');
        try {
            const response = await apiClient.get(`/contribution/${this.token}`);
            
            if (response.success) {
                this.linkData = {
                    requestingPlayerName: response.link.requestingPlayerName,
                    maxUses: response.link.maxUses,
                    remainingUses: response.link.remainingUses || (response.link.maxUses - response.link.currentUses),
                    expiresAt: response.link.expiresAt,
                    
                    // Enhanced player info
                    playerLevel: response.link.playerLevel,
                    playerLevelId: response.link.playerLevelId,
                    playerScore: response.link.playerScore,
                    progression: response.link.progression,
                    
                    // Smart difficulty guidance
                    optimalDifficulty: response.link.optimalDifficulty,
                    levelConfig: response.link.levelConfig
                };
                
                console.log('Enhanced player data loaded:', this.linkData);
                this.displayContributionInfo();
                this.showForm();
                
                // Initialize the scrambling preview with "Hello World"
                this.updateScramblePreview();
            } else {
                throw new Error('Invalid response format');
            }
        } catch (error) {
            console.error('Error loading contribution data:', error);
            this.showError(`Failed to load contribution data: ${error.message}`);
            return;
        }
    }

    displayContributionInfo() {
        const infoElement = document.getElementById('contribution-info');
        const headerSubtitle = document.getElementById('header-subtitle');
        
        const expiresAt = new Date(this.linkData.expiresAt);
        const now = new Date();
        const timeUntilExpiry = expiresAt - now;
        const hoursUntilExpiry = Math.floor(timeUntilExpiry / (1000 * 60 * 60));
        const minutesUntilExpiry = Math.floor((timeUntilExpiry % (1000 * 60 * 60)) / (1000 * 60));
        
        let expirationText = '';
        if (hoursUntilExpiry > 0) {
            expirationText = `${hoursUntilExpiry}h ${minutesUntilExpiry}m`;
        } else if (minutesUntilExpiry > 0) {
            expirationText = `${minutesUntilExpiry} minutes`;
        } else {
            expirationText = 'Soon';
        }

        headerSubtitle.textContent = `Create a phrase for ${this.linkData.requestingPlayerName}`;

        // Check if token is expired
        const isExpired = now > expiresAt;
        
        if (isExpired) {
            // Show expiration warning only if expired
            const timeExpired = now - expiresAt;
            const hoursExpired = Math.floor(timeExpired / (1000 * 60 * 60));
            
            headerSubtitle.textContent = `This contribution link has expired`;
            infoElement.innerHTML = `
                <div class="expiration-warning">
                    <strong>⚠️ This link has expired!</strong> 
                    This link expired ${hoursExpired > 0 ? hoursExpired + ' hours' : 'recently'} ago and can no longer be used.
                </div>
            `;
            return;
        }

        const pointsToLegend = this.linkData.legendThreshold - this.linkData.playerScore;
        const isNearLegend = pointsToLegend <= 500;
        
        infoElement.innerHTML = `
            <div class="player-info">
                <div class="player-avatar">
                    ${this.linkData.requestingPlayerName.charAt(0).toUpperCase()}
                </div>
                <div class="player-details">
                    <h3>${this.linkData.requestingPlayerName}</h3>
                    <p><strong>Level:</strong> ${this.linkData.playerLevel} (${this.linkData.playerScore} points)</p>
                    ${isNearLegend ? 
                        `<p class="legend-progress">🏆 Only ${pointsToLegend} points away from <strong>Legend</strong> status!</p>` :
                        `<p class="legend-info">🏆 Needs ${pointsToLegend} more points to become a <strong>Legend</strong></p>`
                    }
                </div>
            </div>
            <div class="level-matching-tip">
                <h4>💡 Perfect Difficulty Tip</h4>
                <p>Create a <strong>${this.linkData.playerLevel}-level</strong> phrase to match ${this.linkData.requestingPlayerName}'s skill level. This gives them the best challenge and maximum points!</p>
            </div>
        `;
        // Removed expiration warning - only show if actually expired
    }

    showForm() {
        document.getElementById('contribution-form').style.display = 'block';
    }

    handlePhraseInput(e) {
        const charCount = e.target.value.length;
        document.getElementById('char-count').textContent = charCount;
        
        if (charCount > 200) {
            e.target.value = e.target.value.substring(0, 200);
            document.getElementById('char-count').textContent = 200;
        }
        
        // Update quality indicator in real-time
        this.updatePhraseQualityIndicator(e.target.value);
    }

    handleClueInput(e) {
        if (e.target.value.length > 500) {
            e.target.value = e.target.value.substring(0, 500);
        }
    }

    handleLanguageChange(e) {
        // Remove old difficulty preview functionality
    }

    handleContributorNameInput(e) {
        if (e.target.value.length > 50) {
            e.target.value = e.target.value.substring(0, 50);
        }
    }

    handleThemeInput(e) {
        if (e.target.value.length > 50) {
            e.target.value = e.target.value.substring(0, 50);
        }
    }

    validatePhrase() {
        const phrase = document.getElementById('phrase-input').value.trim();
        const errors = ValidationHelpers.validatePhrase(phrase);
        ValidationHelpers.showFieldError('phrase-input', errors);
        return errors.length === 0;
    }

    validateClue() {
        const clue = document.getElementById('clue-input').value.trim();
        const errors = ValidationHelpers.validateClue(clue);
        ValidationHelpers.showFieldError('clue-input', errors);
        return errors.length === 0;
    }

    validateContributorName() {
        const name = document.getElementById('contributor-name').value.trim();
        const errors = ValidationHelpers.validateContributorName(name);
        ValidationHelpers.showFieldError('contributor-name', errors);
        return errors.length === 0;
    }

    validateLanguage() {
        const language = document.getElementById('language-select-top').value;
        const errors = ValidationHelpers.validateLanguage(language);
        ValidationHelpers.showFieldError('language-select-top', errors);
        return errors.length === 0;
    }

    validateTheme() {
        const theme = document.getElementById('theme-input').value.trim();
        const errors = ValidationHelpers.validateTheme(theme);
        ValidationHelpers.showFieldError('theme-input', errors);
        return errors.length === 0;
    }

    validateForm() {
        const phraseValid = this.validatePhrase();
        const themeValid = this.validateTheme();
        const clueValid = this.validateClue();
        const nameValid = this.validateContributorName();
        const languageValid = this.validateLanguage();
        
        return phraseValid && themeValid && clueValid && nameValid && languageValid;
    }

    previewScrambled() {
        const phrase = document.getElementById('phrase-input').value.trim();
        
        if (!phrase) {
            ValidationHelpers.showFieldError('phrase-input', ['Please enter a phrase first']);
            return;
        }

        if (!this.validatePhrase()) {
            return;
        }

        this.showScramblePreview(phrase);
    }

    updateScramblePreview() {
        const phrase = document.getElementById('phrase-input').value.trim();
        const previewElement = document.getElementById('scramble-preview');
        
        if (phrase.length >= 3) {
            // Use user's phrase once they start typing
            this.showScramblePreview(phrase);
        } else {
            // Show default "Hello World" example
            this.showScramblePreview("Hello World");
        }
    }

    showScramblePreview(phrase) {
        const previewElement = document.getElementById('scramble-preview');
        const scrambledTextElement = document.getElementById('scrambled-text');
        
        // Simple scrambling algorithm
        const scrambled = this.scrambleText(phrase);
        
        scrambledTextElement.textContent = scrambled;
        scrambledTextElement.classList.add('scrambling');
        
        // Remove animation class after animation completes
        setTimeout(() => {
            scrambledTextElement.classList.remove('scrambling');
        }, 2000);
        
        previewElement.style.display = 'block';
    }

    scrambleText(text) {
        // Convert to array of characters, preserving spaces and punctuation
        const chars = text.split('');
        const letters = [];
        const positions = [];
        
        // Extract letters and remember their positions
        chars.forEach((char, index) => {
            if (/[a-zA-ZåäöÅÄÖ]/.test(char)) {
                letters.push(char);
                positions.push(index);
            }
        });
        
        // Shuffle the letters using Fisher-Yates algorithm
        for (let i = letters.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [letters[i], letters[j]] = [letters[j], letters[i]];
        }
        
        // Put scrambled letters back in their positions
        let letterIndex = 0;
        const result = chars.map((char, index) => {
            if (positions.includes(index)) {
                return letters[letterIndex++];
            }
            return char;
        });
        
        return result.join('');
    }

    // Phrase quality analysis using shared difficulty algorithm
    analyzePhraseQuality(phrase) {
        if (!phrase || phrase.length < 3) {
            return { 
                quality: 'poor', 
                score: 0, 
                difficulty: 'Very Easy',
                feedback: 'Too short - need at least 3 characters'
            };
        }

        // Get selected language
        const language = document.getElementById('language-select-top')?.value || 'en';
        
        // Use the real difficulty algorithm
        const difficultyScore = this.calculateDifficultyScore(phrase, language);
        const difficultyLabel = this.getDifficultyLabel(difficultyScore);
        
        // Map difficulty score to quality color
        let quality;
        if (difficultyScore >= 80) {
            quality = 'excellent';  // Very Hard phrases
        } else if (difficultyScore >= 60) {
            quality = 'good';       // Hard phrases  
        } else if (difficultyScore >= 40) {
            quality = 'okay';       // Medium phrases
        } else if (difficultyScore >= 20) {
            quality = 'good';       // Easy phrases (good for beginners)
        } else {
            quality = 'poor';       // Very Easy phrases (too simple)
        }
        
        // Generate feedback based on difficulty
        let feedback = `${difficultyLabel} difficulty`;
        if (difficultyScore < 20) {
            feedback += ' - try adding more words or complexity';
        } else if (difficultyScore > 80) {
            feedback += ' - very challenging!';
        }
        
        return {
            quality,
            score: difficultyScore,
            difficulty: difficultyLabel,
            feedback: feedback
        };
    }
    
    // Simplified version of the shared difficulty algorithm for client-side use
    calculateDifficultyScore(phrase, language) {
        const words = phrase.trim().split(/\s+/);
        const wordCount = words.length;
        
        // Normalize text (remove non-letters, convert to lowercase)
        const normalizedText = this.normalize(phrase, language);
        const letterCount = normalizedText.length;
        
        if (letterCount === 0) return 1;
        
        // Simplified scoring based on the shared algorithm
        const wordCountFactor = Math.pow(Math.max(0, wordCount - 1), 1.5) * 10.0;
        const letterCountFactor = Math.pow(letterCount, 1.2) * 1.5;
        
        // Simple commonality factor (approximation)
        const commonalityFactor = letterCount * 2.5;
        
        // Letter repetition factor
        const uniqueLetters = new Set(normalizedText).size;
        const repetitionRatio = (letterCount - uniqueLetters) / letterCount;
        const repetitionFactor = repetitionRatio * 15.0;
        
        const rawScore = wordCountFactor + letterCountFactor + commonalityFactor + repetitionFactor;
        return Math.round(Math.max(1, rawScore));
    }
    
    normalize(phrase, language) {
        if (!phrase) return '';
        const text = phrase.toLowerCase();
        
        // Keep only letters based on language
        if (language === 'sv') {
            return text.replace(/[^a-zåäö]/g, '');
        } else {
            return text.replace(/[^a-z]/g, '');
        }
    }
    
    getDifficultyLabel(score) {
        if (score <= 20) return 'Very Easy';
        if (score <= 40) return 'Easy';
        if (score <= 60) return 'Medium';
        if (score <= 80) return 'Hard';
        return 'Very Hard';
    }
    
    updatePhraseQualityIndicator(phrase) {
        const analysis = this.analyzePhraseQuality(phrase);
        const phraseInput = document.getElementById('phrase-input');
        const qualityIndicator = document.getElementById('quality-indicator');
        
        // Remove existing quality classes
        phraseInput.classList.remove('quality-excellent', 'quality-good', 'quality-okay', 'quality-poor');
        
        // Add new quality class
        phraseInput.classList.add(`quality-${analysis.quality}`);
        
        // Update quality indicator text
        if (qualityIndicator) {
            const targetLevel = this.linkData?.playerLevel || 'Beginner';
            const phraseDifficulty = analysis.difficulty;
            
            // Check if phrase difficulty matches player level approximately
            const isGoodMatch = this.isDifficultyMatch(targetLevel, phraseDifficulty);
            
            qualityIndicator.innerHTML = `
                <div class="quality-badge quality-${analysis.quality}">
                    ${this.getQualityIcon(analysis.quality)} ${analysis.quality.toUpperCase()}
                </div>
                <div class="quality-details">
                    <div class="quality-feedback">${analysis.feedback} (Score: ${analysis.score})</div>
                    <div class="target-match ${isGoodMatch ? 'match' : 'no-match'}">
                        Player level: ${targetLevel} | Phrase: ${phraseDifficulty}
                        ${isGoodMatch ? ' ✓ Good match!' : ' - Consider adjusting difficulty'}
                    </div>
                </div>
            `;
        }
    }
    
    isDifficultyMatch(playerLevel, phraseDifficulty) {
        // Map player levels to phrase difficulties for good matches
        const levelMatches = {
            'Beginner': ['Very Easy', 'Easy'],
            'Intermediate': ['Easy', 'Medium'],
            'Advanced': ['Medium', 'Hard'],
            'Expert': ['Hard', 'Very Hard'],
            'Master': ['Hard', 'Very Hard']
        };
        
        return levelMatches[playerLevel]?.includes(phraseDifficulty) || false;
    }
    
    getQualityIcon(quality) {
        switch (quality) {
            case 'excellent': return '🌟';
            case 'good': return '✅';
            case 'okay': return '⚠️';
            case 'poor': return '❌';
            default: return '❓';
        }
    }

    async handleSubmit(e) {
        e.preventDefault();
        
        if (this.isSubmitting) return;
        
        if (!this.validateForm()) {
            return;
        }

        this.isSubmitting = true;
        this.setSubmitButtonLoading(true);

        try {
            const formData = {
                phrase: document.getElementById('phrase-input').value.trim(),
                theme: document.getElementById('theme-input').value.trim() || null,
                clue: document.getElementById('clue-input').value.trim(), // Required field - no null fallback
                language: document.getElementById('language-select-top').value,
                contributorName: document.getElementById('contributor-name').value.trim() || null
            };

            const response = await apiClient.post(`/contribution/${this.token}/submit`, formData);
            
            this.showSuccess(response);
        } catch (error) {
            console.error('Error submitting contribution:', error);
            this.showError(error.message || 'Failed to submit phrase');
        } finally {
            this.isSubmitting = false;
            this.setSubmitButtonLoading(false);
        }
    }

    setSubmitButtonLoading(isLoading) {
        const submitBtn = document.getElementById('submit-btn');
        const btnText = submitBtn.querySelector('.btn-text');
        const btnSpinner = submitBtn.querySelector('.btn-spinner');
        
        submitBtn.disabled = isLoading;
        btnText.style.opacity = isLoading ? '0' : '1';
        btnSpinner.style.display = isLoading ? 'block' : 'none';
    }

    showSuccess(response) {
        const form = document.getElementById('contribution-form');
        const result = document.getElementById('contribution-result');
        const playerName = document.getElementById('result-player-name');
        const summary = document.getElementById('contribution-summary');
        
        form.style.display = 'none';
        result.style.display = 'block';
        
        playerName.textContent = this.linkData.requestingPlayerName;
        
        const remainingUses = response.remainingUses || 0;
        let summaryText = 'Your phrase has been added to their game queue!';
        
        if (remainingUses > 0) {
            summaryText += ` This link can be used ${remainingUses} more time${remainingUses !== 1 ? 's' : ''}.`;
        } else {
            summaryText += ' This link has now been used up.';
        }
        
        summary.textContent = summaryText;
        
        // Scroll to result
        result.scrollIntoView({ behavior: 'smooth' });
    }

    showError(message) {
        const form = document.getElementById('contribution-form');
        const info = document.getElementById('contribution-info');
        const error = document.getElementById('contribution-error');
        const errorMessage = document.getElementById('error-message');
        
        form.style.display = 'none';
        info.style.display = 'none';
        error.style.display = 'block';
        
        errorMessage.textContent = message;
        
        // Scroll to error
        error.scrollIntoView({ behavior: 'smooth' });
    }
}

// Initialize the contribution form when the page loads
document.addEventListener('DOMContentLoaded', () => {
    new ContributionForm();
});