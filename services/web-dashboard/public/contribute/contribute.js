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
        const clueInput = document.getElementById('clue-input');
        const languageSelect = document.getElementById('language-select');
        const contributorName = document.getElementById('contributor-name');
        const previewBtn = document.getElementById('preview-btn');
        const submitBtn = document.getElementById('submit-btn');

        form.addEventListener('submit', (e) => this.handleSubmit(e));
        
        phraseInput.addEventListener('input', (e) => this.handlePhraseInput(e));
        clueInput.addEventListener('input', (e) => this.handleClueInput(e));
        languageSelect.addEventListener('change', (e) => this.handleLanguageChange(e));
        contributorName.addEventListener('input', (e) => this.handleContributorNameInput(e));
        
        previewBtn.addEventListener('click', () => this.previewDifficulty());
        
        // Real-time validation
        phraseInput.addEventListener('blur', () => this.validatePhrase());
        clueInput.addEventListener('blur', () => this.validateClue());
        contributorName.addEventListener('blur', () => this.validateContributorName());
    }

    async loadContributionData() {
        try {
            const response = await apiClient.get(`/contribution/${this.token}`);
            this.linkData = response.link;
            this.displayContributionInfo();
            this.showForm();
        } catch (error) {
            console.error('Error loading contribution data:', error);
            this.showError(error.message || 'Failed to load contribution link');
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

        infoElement.innerHTML = `
            <div class="player-info">
                <div class="player-avatar">
                    ${this.linkData.requestingPlayerName.charAt(0).toUpperCase()}
                </div>
                <div class="player-details">
                    <h3>${this.linkData.requestingPlayerName}</h3>
                    <p>Requested a phrase contribution</p>
                </div>
            </div>
            <div class="link-info">
                <div class="link-status">
                    <span class="status-indicator status-online">Active</span>
                    <span>${this.linkData.remainingUses} of ${this.linkData.maxUses} uses remaining</span>
                </div>
                <div class="link-expiry">
                    <span>Expires in ${expirationText}</span>
                </div>
            </div>
            ${this.linkData.customMessage ? `
                <div class="custom-message">
                    <p><strong>Message:</strong> ${this.linkData.customMessage}</p>
                </div>
            ` : ''}
        `;
        
        // Show expiration warning if less than 2 hours
        if (timeUntilExpiry < 2 * 60 * 60 * 1000) {
            const warning = document.createElement('div');
            warning.className = 'expiration-warning';
            warning.innerHTML = `
                <strong>⏰ This link expires soon!</strong> 
                Please submit your phrase within the next ${expirationText}.
            `;
            infoElement.appendChild(warning);
        }
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
        
        this.hideDifficultyPreview();
    }

    handleClueInput(e) {
        if (e.target.value.length > 500) {
            e.target.value = e.target.value.substring(0, 500);
        }
    }

    handleLanguageChange(e) {
        this.hideDifficultyPreview();
    }

    handleContributorNameInput(e) {
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
        const language = document.getElementById('language-select').value;
        const errors = ValidationHelpers.validateLanguage(language);
        ValidationHelpers.showFieldError('language-select', errors);
        return errors.length === 0;
    }

    validateForm() {
        const phraseValid = this.validatePhrase();
        const clueValid = this.validateClue();
        const nameValid = this.validateContributorName();
        const languageValid = this.validateLanguage();
        
        return phraseValid && clueValid && nameValid && languageValid;
    }

    previewDifficulty() {
        const phrase = document.getElementById('phrase-input').value.trim();
        
        if (!phrase) {
            ValidationHelpers.showFieldError('phrase-input', ['Please enter a phrase first']);
            return;
        }

        if (!this.validatePhrase()) {
            return;
        }

        const difficulty = ValidationHelpers.calculateDifficulty(phrase);
        const difficultyLabel = ValidationHelpers.getDifficultyLabel(difficulty);
        const difficultyColor = ValidationHelpers.getDifficultyColor(difficulty);
        
        const previewElement = document.getElementById('difficulty-preview');
        const indicatorElement = document.getElementById('difficulty-indicator');
        const detailsElement = document.getElementById('difficulty-details');
        
        indicatorElement.style.backgroundColor = difficultyColor + '20';
        indicatorElement.style.color = difficultyColor;
        indicatorElement.querySelector('.difficulty-level').textContent = difficultyLabel;
        
        const words = phrase.split(/\s+/).filter(word => word.length > 0);
        const totalLetters = phrase.replace(/\s/g, '').length;
        const avgWordLength = Math.round(totalLetters / words.length * 10) / 10;
        
        detailsElement.innerHTML = `
            <p><strong>Analysis:</strong></p>
            <ul>
                <li>${words.length} words, ${totalLetters} letters total</li>
                <li>Average word length: ${avgWordLength} letters</li>
                <li>Difficulty rating: ${difficulty.toFixed(1)}/5.0</li>
            </ul>
            <p><em>This gives players a ${difficultyLabel.toLowerCase()} challenge level.</em></p>
        `;
        
        previewElement.style.display = 'block';
        previewElement.scrollIntoView({ behavior: 'smooth' });
    }

    hideDifficultyPreview() {
        document.getElementById('difficulty-preview').style.display = 'none';
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
                clue: document.getElementById('clue-input').value.trim() || null,
                language: document.getElementById('language-select').value,
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