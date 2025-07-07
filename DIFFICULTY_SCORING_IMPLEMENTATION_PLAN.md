# Anagram Game - Difficulty Scoring Implementation Plan (Server-Side)

This document outlines the plan to implement a science-based, statistical difficulty scoring algorithm for anagram phrases **on the server**. The system will be self-contained, efficient, and support both English and Swedish from the start.

## Guiding Principles

1.  **Server-Side Logic:** The scoring will be handled exclusively by the server to ensure consistency and central management.
2.  **Statistical, Not Semantic:** The algorithm will not rely on word meanings, but on the statistical properties of the letters and their structure. This is computationally fast and language-agnostic.
3.  **Self-Contained:** All required data (letter frequencies) will be embedded directly in the server-side code to avoid dependencies on external files.
4.  **Extensible:** The design will make it simple to add support for new languages in the future by just adding a new letter frequency table.

## Core Algorithm

The final score will be a weighted combination of two factors:

**`Difficulty Score = (Letter Rarity Score * 0.7) + (Structural Complexity Score * 0.3)`**

The result will be normalized to a user-friendly scale (e.g., 1-100) and stored in the database.

---

## Implementation Steps

### 1. Create a New Server Module: `difficultyScorer.js`

A new JavaScript module will be created to encapsulate all the logic related to difficulty scoring.

-   **File Path:** `server/services/difficultyScorer.js`

### 2. Define Language and Frequency Data

Inside `difficultyScorer.js`, we will define the necessary data structures.

-   **Export Language Constants:**
    ```javascript
    const LANGUAGES = {
        ENGLISH: 'en',
        SWEDISH: 'sv',
    };
    ```
-   **Embed Letter Frequency Tables:**
    -   Create two `const` objects, one for English and one for Swedish, mapping each character to its frequency.

### 3. Implement the Main Scorer Module

-   **Create `DifficultyScorer` class or object:** This will be the main interface for the system.
-   **Define the main function:**
    ```javascript
    function calculateScore({ phrase, language })
    ```
    This function will take a phrase and its language, and return an integer score from 1 to 100.

### 4. Implement Helper Functions

The main `calculateScore` function will use several private helper functions.

-   **`normalize(phrase, language)`**
    -   This function will take a raw phrase, convert it to lowercase, and strip out all characters that are not letters of the specified language's alphabet.

-   **`calculateLetterRarity(text, frequencies)`**
    -   This function will calculate the average "rarity" of the letters in the text.
    -   Rarity for each letter will be calculated as `1.0 / frequency`.

-   **`calculateStructuralComplexity(text)`**
    -   This function will analyze the letter-pair (bigram) structure of the text.
    -   It will calculate complexity as `(number of unique bigrams) / (total number of bigrams)`.

### 5. Database Schema Update

-   The `phrases` table in the database will be updated to include a new column:
    -   `difficulty_score INTEGER`

### 6. Integrate Scoring into Phrase Creation

-   The existing `POST /api/phrases` endpoint (used for creating new phrases) will be modified.
-   After a new phrase is created, it will immediately call the `DifficultyScorer` module to calculate its score.
-   The calculated score will be saved to the new `difficulty_score` column for that phrase in the database.

### 7. (Optional) Create a Standalone Analysis Endpoint

-   For testing and potential future use, a dedicated endpoint can be created.
-   **Endpoint:** `POST /api/phrases/analyze-difficulty`
-   **Request Body:** `{ "phrase": "some text", "language": "sv" }`
-   **Response:** `{ "score": 78 }`
-   This allows for on-the-fly difficulty analysis without creating a new phrase. 