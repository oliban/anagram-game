import XCTest
@testable import Anagram_Game

final class PhraseCacheTests: XCTestCase {
    
    var phraseCache: PhraseCache!
    let testUserDefaultsKey = "TestPhraseCache"
    
    override func setUp() {
        super.setUp()
        // Use a test-specific UserDefaults key to avoid conflicts
        phraseCache = PhraseCache(userDefaultsKey: testUserDefaultsKey)
        // Clear any existing test data
        phraseCache.clearCache()
    }
    
    override func tearDown() {
        // Clean up test data
        phraseCache.clearCache()
        phraseCache = nil
        super.tearDown()
    }
    
    // MARK: - Cache Initialization Tests
    
    func testCacheInitialization() {
        XCTAssertNotNil(phraseCache, "PhraseCache should initialize successfully")
        XCTAssertEqual(phraseCache.getCachedPhrasesCount(), 0, "New cache should be empty")
        XCTAssertEqual(phraseCache.getUnplayedPhrasesCount(), 0, "New cache should have no unplayed phrases")
    }
    
    func testEmptyCacheState() {
        XCTAssertTrue(phraseCache.isEmpty(), "Empty cache should return true for isEmpty")
        XCTAssertFalse(phraseCache.hasUnplayedPhrases(), "Empty cache should have no unplayed phrases")
        XCTAssertNil(phraseCache.getRandomUnplayedPhrase(), "Empty cache should return nil for random phrase")
    }
    
    // MARK: - Adding Phrases Tests
    
    func testAddSinglePhrase() {
        let testPhrase = createTestCachedPhrase(id: "test1", content: "hello world", difficulty: 50)
        
        phraseCache.addPhrase(testPhrase)
        
        XCTAssertEqual(phraseCache.getCachedPhrasesCount(), 1, "Cache should contain one phrase")
        XCTAssertEqual(phraseCache.getUnplayedPhrasesCount(), 1, "Cache should have one unplayed phrase")
        XCTAssertFalse(phraseCache.isEmpty(), "Cache should not be empty after adding phrase")
    }
    
    func testAddMultiplePhrases() {
        let phrases = [
            createTestCachedPhrase(id: "test1", content: "hello world", difficulty: 50),
            createTestCachedPhrase(id: "test2", content: "time flies", difficulty: 75),
            createTestCachedPhrase(id: "test3", content: "lost keys", difficulty: 42)
        ]
        
        phraseCache.addPhrases(phrases)
        
        XCTAssertEqual(phraseCache.getCachedPhrasesCount(), 3, "Cache should contain three phrases")
        XCTAssertEqual(phraseCache.getUnplayedPhrasesCount(), 3, "Cache should have three unplayed phrases")
    }
    
    func testAddDuplicatePhrases() {
        let phrase1 = createTestCachedPhrase(id: "test1", content: "hello world", difficulty: 50)
        let phrase2 = createTestCachedPhrase(id: "test1", content: "hello world", difficulty: 50) // Same ID
        
        phraseCache.addPhrase(phrase1)
        phraseCache.addPhrase(phrase2)
        
        XCTAssertEqual(phraseCache.getCachedPhrasesCount(), 1, "Duplicate phrases should not be added")
        XCTAssertEqual(phraseCache.getUnplayedPhrasesCount(), 1, "Should have only one unplayed phrase")
    }
    
    // MARK: - Phrase Tracking Tests
    
    func testMarkPhraseAsPlayed() {
        let testPhrase = createTestCachedPhrase(id: "test1", content: "hello world", difficulty: 50)
        phraseCache.addPhrase(testPhrase)
        
        XCTAssertEqual(phraseCache.getUnplayedPhrasesCount(), 1, "Should have one unplayed phrase initially")
        
        phraseCache.markPhraseAsPlayed("test1")
        
        XCTAssertEqual(phraseCache.getUnplayedPhrasesCount(), 0, "Should have no unplayed phrases after marking as played")
        XCTAssertEqual(phraseCache.getCachedPhrasesCount(), 1, "Total phrase count should remain the same")
        XCTAssertTrue(phraseCache.isPhraseAlreadyPlayed("test1"), "Phrase should be marked as played")
    }
    
    func testAvoidRepeats() {
        let phrases = [
            createTestCachedPhrase(id: "test1", content: "hello world", difficulty: 50),
            createTestCachedPhrase(id: "test2", content: "time flies", difficulty: 75),
            createTestCachedPhrase(id: "test3", content: "lost keys", difficulty: 42)
        ]
        phraseCache.addPhrases(phrases)
        
        // Mark first two as played
        phraseCache.markPhraseAsPlayed("test1")
        phraseCache.markPhraseAsPlayed("test2")
        
        XCTAssertEqual(phraseCache.getUnplayedPhrasesCount(), 1, "Should have one unplayed phrase")
        
        // Get random unplayed phrase multiple times - should always be test3
        for _ in 0..<10 {
            let randomPhrase = phraseCache.getRandomUnplayedPhrase()
            XCTAssertNotNil(randomPhrase, "Should return a phrase")
            XCTAssertEqual(randomPhrase?.id, "test3", "Should only return the unplayed phrase")
        }
    }
    
    func testGetUnplayedPhrasesCount() {
        let phrases = [
            createTestCachedPhrase(id: "test1", content: "hello world", difficulty: 50),
            createTestCachedPhrase(id: "test2", content: "time flies", difficulty: 75),
            createTestCachedPhrase(id: "test3", content: "lost keys", difficulty: 42)
        ]
        phraseCache.addPhrases(phrases)
        
        XCTAssertEqual(phraseCache.getUnplayedPhrasesCount(), 3, "Initially all phrases should be unplayed")
        
        phraseCache.markPhraseAsPlayed("test1")
        XCTAssertEqual(phraseCache.getUnplayedPhrasesCount(), 2, "Should have 2 unplayed after marking one")
        
        phraseCache.markPhraseAsPlayed("test2")
        XCTAssertEqual(phraseCache.getUnplayedPhrasesCount(), 1, "Should have 1 unplayed after marking two")
        
        phraseCache.markPhraseAsPlayed("test3")
        XCTAssertEqual(phraseCache.getUnplayedPhrasesCount(), 0, "Should have 0 unplayed after marking all")
    }
    
    // MARK: - Cache Persistence Tests
    
    func testSaveAndLoadCache() {
        let testPhrases = [
            createTestCachedPhrase(id: "test1", content: "hello world", difficulty: 50),
            createTestCachedPhrase(id: "test2", content: "time flies", difficulty: 75)
        ]
        
        phraseCache.addPhrases(testPhrases)
        phraseCache.markPhraseAsPlayed("test1")
        
        // Save to UserDefaults
        let saveSuccess = phraseCache.saveCache()
        XCTAssertTrue(saveSuccess, "Cache save should succeed")
        
        // Create new cache instance and load
        let newCache = PhraseCache(userDefaultsKey: testUserDefaultsKey)
        let loadSuccess = newCache.loadCache()
        
        XCTAssertTrue(loadSuccess, "Cache load should succeed")
        XCTAssertEqual(newCache.getCachedPhrasesCount(), 2, "Loaded cache should have same phrase count")
        XCTAssertEqual(newCache.getUnplayedPhrasesCount(), 1, "Loaded cache should maintain played state")
        XCTAssertTrue(newCache.isPhraseAlreadyPlayed("test1"), "Played state should persist")
        XCTAssertFalse(newCache.isPhraseAlreadyPlayed("test2"), "Unplayed state should persist")
    }
    
    func testLoadFromEmptyUserDefaults() {
        let loadSuccess = phraseCache.loadCache()
        XCTAssertFalse(loadSuccess, "Loading from empty UserDefaults should return false")
        XCTAssertEqual(phraseCache.getCachedPhrasesCount(), 0, "Cache should remain empty after failed load")
    }
    
    // MARK: - Cache Size Management Tests
    
    func testCacheSizeLimit() {
        let maxCacheSize = 30
        var testPhrases: [CachedPhrase] = []
        
        // Create 35 test phrases (more than the 30 limit)
        for i in 1...35 {
            testPhrases.append(createTestCachedPhrase(id: "test\(i)", content: "phrase \(i)", difficulty: 50))
        }
        
        phraseCache.addPhrases(testPhrases)
        
        XCTAssertEqual(phraseCache.getCachedPhrasesCount(), maxCacheSize, "Cache should not exceed maximum size")
    }
    
    func testOldestPhrasesRemovedWhenFull() {
        let maxCacheSize = 30
        var initialPhrases: [CachedPhrase] = []
        
        // Fill cache to capacity
        for i in 1...maxCacheSize {
            initialPhrases.append(createTestCachedPhrase(id: "initial\(i)", content: "initial phrase \(i)", difficulty: 50))
        }
        phraseCache.addPhrases(initialPhrases)
        
        // Add new phrases that should trigger removal of oldest
        let newPhrases = [
            createTestCachedPhrase(id: "new1", content: "new phrase 1", difficulty: 75),
            createTestCachedPhrase(id: "new2", content: "new phrase 2", difficulty: 100)
        ]
        phraseCache.addPhrases(newPhrases)
        
        XCTAssertEqual(phraseCache.getCachedPhrasesCount(), maxCacheSize, "Cache should maintain maximum size")
        
        // Verify new phrases are present
        let cachedPhrases = phraseCache.getAllCachedPhrases()
        let phraseIds = cachedPhrases.map { $0.id }
        XCTAssertTrue(phraseIds.contains("new1"), "New phrase 1 should be in cache")
        XCTAssertTrue(phraseIds.contains("new2"), "New phrase 2 should be in cache")
        
        // Verify oldest phrases are removed
        XCTAssertFalse(phraseIds.contains("initial1"), "Oldest phrase should be removed")
        XCTAssertFalse(phraseIds.contains("initial2"), "Second oldest phrase should be removed")
    }
    
    // MARK: - Difficulty Filtering Tests
    
    func testDifficultyFilteringOnAdd() {
        let phrases = [
            createTestCachedPhrase(id: "easy", content: "hello", difficulty: 25),
            createTestCachedPhrase(id: "medium", content: "hello world", difficulty: 50),
            createTestCachedPhrase(id: "hard", content: "complex phrase structure", difficulty: 150)
        ]
        
        // Set difficulty range filter (30-100)
        phraseCache.setDifficultyRange(min: 30, max: 100)
        phraseCache.addPhrases(phrases)
        
        XCTAssertEqual(phraseCache.getCachedPhrasesCount(), 1, "Only phrases within difficulty range should be cached")
        
        let cachedPhrases = phraseCache.getAllCachedPhrases()
        XCTAssertEqual(cachedPhrases.first?.id, "medium", "Only medium difficulty phrase should be cached")
    }
    
    func testGetPhrasesInDifficultyRange() {
        let phrases = [
            createTestCachedPhrase(id: "easy", content: "hello", difficulty: 25),
            createTestCachedPhrase(id: "medium1", content: "hello world", difficulty: 50),
            createTestCachedPhrase(id: "medium2", content: "time flies", difficulty: 75),
            createTestCachedPhrase(id: "hard", content: "complex phrase structure", difficulty: 150)
        ]
        
        phraseCache.addPhrases(phrases)
        
        let mediumPhrases = phraseCache.getPhrasesInDifficultyRange(min: 40, max: 80)
        XCTAssertEqual(mediumPhrases.count, 2, "Should return 2 phrases in medium difficulty range")
        
        let phraseIds = mediumPhrases.map { $0.id }
        XCTAssertTrue(phraseIds.contains("medium1"), "Should include medium1")
        XCTAssertTrue(phraseIds.contains("medium2"), "Should include medium2")
        XCTAssertFalse(phraseIds.contains("easy"), "Should not include easy phrase")
        XCTAssertFalse(phraseIds.contains("hard"), "Should not include hard phrase")
    }
    
    // MARK: - Clear Cache Tests
    
    func testClearCache() {
        let testPhrases = [
            createTestCachedPhrase(id: "test1", content: "hello world", difficulty: 50),
            createTestCachedPhrase(id: "test2", content: "time flies", difficulty: 75)
        ]
        
        phraseCache.addPhrases(testPhrases)
        phraseCache.markPhraseAsPlayed("test1")
        
        XCTAssertEqual(phraseCache.getCachedPhrasesCount(), 2, "Cache should have phrases before clear")
        
        phraseCache.clearCache()
        
        XCTAssertEqual(phraseCache.getCachedPhrasesCount(), 0, "Cache should be empty after clear")
        XCTAssertEqual(phraseCache.getUnplayedPhrasesCount(), 0, "No unplayed phrases after clear")
        XCTAssertTrue(phraseCache.isEmpty(), "Cache should be empty after clear")
    }
    
    // MARK: - Helper Methods
    
    private func createTestCachedPhrase(id: String, content: String, difficulty: Int, language: String = "en") -> CachedPhrase {
        let customPhrase = CustomPhrase(
            id: id,
            content: content,
            senderId: "test-sender",
            targetId: "test-target",
            createdAt: Date(),
            isConsumed: false,
            senderName: "Test Sender",
            language: language
        )
        
        return CachedPhrase(
            customPhrase: customPhrase,
            difficultyScore: difficulty,
            cachedAt: Date()
        )
    }
}