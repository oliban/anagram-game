class ValidationHelpers {
    static validatePhrase(phrase) {
        const errors = [];
        
        if (!phrase || typeof phrase !== 'string') {
            errors.push('Phrase is required');
            return errors;
        }
        
        const trimmed = phrase.trim();
        
        if (trimmed.length < 3) {
            errors.push('Phrase must be at least 3 characters long');
        }
        
        if (trimmed.length > 200) {
            errors.push('Phrase must be less than 200 characters');
        }
        
        if (!/^[a-zA-ZåäöÅÄÖ\s\-',.!?]+$/.test(trimmed)) {
            errors.push('Phrase contains invalid characters');
        }
        
        // Use same word count logic as PhraseCreationView.swift
        const wordCount = trimmed.split(/\s+/).filter(word => word.length > 0).length;
        if (wordCount < 2) {
            errors.push('Phrase must contain at least 2 words');
        }
        
        if (wordCount > 6) {
            errors.push('Phrase must contain no more than 6 words');
        }
        
        return errors;
    }

    static validateClue(clue, phrase = null) {
        const errors = [];
        
        if (!clue || typeof clue !== 'string') {
            errors.push('Clue is required');
            return errors;
        }
        
        const trimmed = clue.trim();
        
        if (trimmed.length === 0) {
            errors.push('Clue is required');
        }
        
        if (trimmed.length < 3) {
            errors.push('Clue must be at least 3 characters long');
        }
        
        if (trimmed.length > 500) {
            errors.push('Clue must be less than 500 characters');
        }
        
        if (!/^[a-zA-ZåäöÅÄÖ\s\-',.!?0-9]+$/.test(trimmed)) {
            errors.push('Clue contains invalid characters');
        }
        
        // Check if clue contains words that are also in the phrase
        if (phrase && typeof phrase === 'string') {
            const phraseWords = this.extractWords(phrase.toLowerCase());
            const clueWords = this.extractWords(trimmed.toLowerCase());
            
            for (const phraseWord of phraseWords) {
                if (phraseWord.length >= 3) { // Only check words that are 3+ characters
                    if (clueWords.includes(phraseWord)) {
                        errors.push(`Clue cannot contain "${phraseWord}" which appears in the phrase`);
                        break; // Only show first error to avoid cluttering
                    }
                }
            }
        }
        
        return errors;
    }
    
    static extractWords(text) {
        return text.toLowerCase()
                   .replace(/[^\w\såäö]/g, '') // Remove punctuation, keep letters and spaces
                   .split(/\s+/)
                   .filter(word => word.length > 0);
    }

    static validateLanguage(language) {
        const validLanguages = ['en', 'sv'];
        
        if (!language || !validLanguages.includes(language)) {
            return ['Please select a valid language'];
        }
        
        return [];
    }

    static validateContributorName(name) {
        const errors = [];
        
        if (!name || typeof name !== 'string') {
            return errors; // Name is optional
        }
        
        const trimmed = name.trim();
        
        if (trimmed.length > 50) {
            errors.push('Name must be less than 50 characters');
        }
        
        if (!/^[a-zA-ZåäöÅÄÖ\s\-']+$/.test(trimmed)) {
            errors.push('Name contains invalid characters');
        }
        
        return errors;
    }

    static validateTheme(theme) {
        const errors = [];
        
        if (!theme || typeof theme !== 'string') {
            return errors; // Theme is optional
        }
        
        const trimmed = theme.trim();
        
        if (trimmed.length > 50) {
            errors.push('Theme must be less than 50 characters');
        }
        
        if (!/^[a-zA-ZåäöÅÄÖ\s\-'&0-9]+$/.test(trimmed)) {
            errors.push('Theme contains invalid characters');
        }
        
        return errors;
    }

    static calculateDifficulty(phrase) {
        if (!phrase || typeof phrase !== 'string') {
            return 0;
        }
        
        const words = phrase.trim().split(/\s+/).filter(word => word.length > 0);
        const totalLength = phrase.replace(/\s/g, '').length;
        const avgWordLength = totalLength / words.length;
        
        let difficulty = 1;
        
        if (words.length > 3) difficulty += 0.5;
        if (words.length > 5) difficulty += 0.5;
        if (avgWordLength > 5) difficulty += 0.5;
        if (avgWordLength > 7) difficulty += 0.5;
        if (totalLength > 20) difficulty += 0.5;
        if (totalLength > 30) difficulty += 0.5;
        
        return Math.min(Math.max(difficulty, 1), 5);
    }

    static getDifficultyLabel(difficulty) {
        if (difficulty <= 1.5) return 'Very Easy';
        if (difficulty <= 2.5) return 'Easy';
        if (difficulty <= 3.5) return 'Medium';
        if (difficulty <= 4.5) return 'Hard';
        return 'Very Hard';
    }

    static getDifficultyColor(difficulty) {
        if (difficulty <= 1.5) return '#22c55e'; // green
        if (difficulty <= 2.5) return '#84cc16'; // lime
        if (difficulty <= 3.5) return '#f59e0b'; // amber
        if (difficulty <= 4.5) return '#ef4444'; // red
        return '#dc2626'; // dark red
    }

    static showFieldError(fieldId, errors) {
        const field = document.getElementById(fieldId);
        const errorElement = document.getElementById(fieldId + '-error');
        
        if (errors.length > 0) {
            field?.classList.add('error');
            if (errorElement) {
                errorElement.textContent = errors[0];
                errorElement.style.display = 'block';
            }
        } else {
            field?.classList.remove('error');
            if (errorElement) {
                errorElement.style.display = 'none';
            }
        }
    }

    static clearAllErrors(fieldIds) {
        fieldIds.forEach(fieldId => {
            this.showFieldError(fieldId, []);
        });
    }
}