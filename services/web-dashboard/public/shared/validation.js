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

    static validateClue(clue) {
        const errors = [];
        
        if (!clue || typeof clue !== 'string') {
            return errors; // Clue is optional
        }
        
        const trimmed = clue.trim();
        
        if (trimmed.length > 500) {
            errors.push('Clue must be less than 500 characters');
        }
        
        if (!/^[a-zA-ZåäöÅÄÖ\s\-',.!?0-9]+$/.test(trimmed)) {
            errors.push('Clue contains invalid characters');
        }
        
        return errors;
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