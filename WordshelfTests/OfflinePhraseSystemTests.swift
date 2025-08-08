import XCTest
@testable import Anagram_Game

final class OfflinePhraseSystemTests: XCTestCase {
    
    var phraseSystem: OfflinePhraseSystem!
    var mockNetworkManager: MockNetworkManager!
    var mockPhraseCache: MockPhraseCache!
    var mockReachabilityManager: MockReachabilityManager!
    
    override func setUp() {
        super.setUp()
        mockNetworkManager = MockNetworkManager()
        mockPhraseCache = MockPhraseCache()
        mockReachabilityManager = MockReachabilityManager()
        
        phraseSystem = OfflinePhraseSystem(
            networkManager: mockNetworkManager,
            phraseCache: mockPhraseCache,
            reachabilityManager: mockReachabilityManager
        )
    }
    
    override func tearDown() {
        phraseSystem = nil
        mockNetworkManager = nil
        mockPhraseCache = nil
        mockReachabilityManager = nil
        super.tearDown()
    }
    
    // MARK: - Online Phrase Selection Tests
    
    func testOnlinePhraseSelection_CacheFirst() async {
        // Setup: Cache has phrases, we're online
        mockReachabilityManager.isOnline = true
        mockPhraseCache.mockUnplayedPhrases = [createTestPhrase(id: "cache1", content: "cached phrase")]
        
        let result = await phraseSystem.getNextPhrase()
        
        XCTAssertNotNil(result, "Should return a phrase")
        XCTAssertEqual(result?.id, "cache1", "Should return phrase from cache first")
        XCTAssertFalse(mockNetworkManager.fetchPhrasesCalled, "Should not fetch from server when cache has phrases")
        XCTAssertTrue(mockPhraseCache.getRandomUnplayedPhraseCalled, "Should check cache first")
    }
    
    func testOnlinePhraseSelection_ServerFallback() async {
        // Setup: Empty cache, we're online, server has phrases
        mockReachabilityManager.isOnline = true
        mockPhraseCache.mockUnplayedPhrases = []
        mockNetworkManager.mockServerPhrases = [createTestPhrase(id: "server1", content: "server phrase")]
        
        let result = await phraseSystem.getNextPhrase()
        
        XCTAssertNotNil(result, "Should return a phrase")
        XCTAssertEqual(result?.id, "server1", "Should return phrase from server")
        XCTAssertTrue(mockNetworkManager.fetchPhrasesCalled, "Should fetch from server when cache empty")
        XCTAssertTrue(mockPhraseCache.addPhrasesCalled, "Should cache server phrases")
    }
    
    func testOnlinePhraseSelection_BothEmpty() async {
        // Setup: Empty cache, we're online, empty server
        mockReachabilityManager.isOnline = true
        mockPhraseCache.mockUnplayedPhrases = []
        mockNetworkManager.mockServerPhrases = []
        
        let result = await phraseSystem.getNextPhrase()
        
        XCTAssertNil(result, "Should return nil when both cache and server are empty")
        XCTAssertTrue(mockNetworkManager.fetchPhrasesCalled, "Should attempt server fetch")
    }
    
    // MARK: - Offline Phrase Selection Tests
    
    func testOfflinePhraseSelection_CacheAvailable() async {
        // Setup: Cache has phrases, we're offline
        mockReachabilityManager.isOnline = false
        mockPhraseCache.mockUnplayedPhrases = [createTestPhrase(id: "offline1", content: "offline phrase")]
        
        let result = await phraseSystem.getNextPhrase()
        
        XCTAssertNotNil(result, "Should return cached phrase when offline")
        XCTAssertEqual(result?.id, "offline1", "Should return phrase from cache")
        XCTAssertFalse(mockNetworkManager.fetchPhrasesCalled, "Should not attempt server fetch when offline")
    }
    
    func testOfflinePhraseSelection_EmptyCache() async {
        // Setup: Empty cache, we're offline
        mockReachabilityManager.isOnline = false
        mockPhraseCache.mockUnplayedPhrases = []
        
        let result = await phraseSystem.getNextPhrase()
        
        XCTAssertNil(result, "Should return nil when offline with empty cache")
        XCTAssertFalse(mockNetworkManager.fetchPhrasesCalled, "Should not attempt server fetch when offline")
    }
    
    func testOfflinePhraseSelection_NoRepeats() async {
        // Setup: Multiple phrases in cache, some already played
        mockReachabilityManager.isOnline = false
        let phrase1 = createTestPhrase(id: "phrase1", content: "first phrase")
        let phrase2 = createTestPhrase(id: "phrase2", content: "second phrase")
        
        mockPhraseCache.mockUnplayedPhrases = [phrase1, phrase2]
        mockPhraseCache.mockPlayedPhraseIds = Set(["phrase3"]) // Some other phrase already played
        
        // Get first phrase
        let result1 = await phraseSystem.getNextPhrase()
        XCTAssertNotNil(result1, "Should get first phrase")
        
        // Mark it as played and update mock
        mockPhraseCache.mockPlayedPhraseIds.insert(result1!.id)
        mockPhraseCache.mockUnplayedPhrases = [phrase2] // Remove played phrase
        
        // Get second phrase
        let result2 = await phraseSystem.getNextPhrase()
        XCTAssertNotNil(result2, "Should get second phrase")
        XCTAssertNotEqual(result1?.id, result2?.id, "Should not repeat phrases")
    }
    
    // MARK: - Difficulty-Based Selection Tests
    
    func testDifficultyBasedSelection() async {
        // Setup: Mixed difficulty phrases in cache
        mockReachabilityManager.isOnline = true
        let easyPhrase = createTestPhrase(id: "easy", content: "easy", difficulty: 25)
        let mediumPhrase = createTestPhrase(id: "medium", content: "medium phrase", difficulty: 50)
        let hardPhrase = createTestPhrase(id: "hard", content: "very complex difficult phrase", difficulty: 150)
        
        mockPhraseCache.mockUnplayedPhrases = [easyPhrase, mediumPhrase, hardPhrase]
        
        // Test with difficulty range 40-100 (should get medium phrase)
        phraseSystem.setDifficultyRange(min: 40, max: 100)
        let result = await phraseSystem.getNextPhrase()
        
        XCTAssertNotNil(result, "Should return a phrase in difficulty range")
        XCTAssertEqual(result?.id, "medium", "Should return phrase within difficulty range")
        XCTAssertTrue(mockPhraseCache.getPhrasesInDifficultyRangeCalled, "Should filter by difficulty range")
    }
    
    func testDifficultyBasedSelection_NoMatchingDifficulty() async {
        // Setup: Only hard phrases in cache, but requesting easy range
        mockReachabilityManager.isOnline = false
        let hardPhrase = createTestPhrase(id: "hard", content: "very complex difficult phrase", difficulty: 150)
        mockPhraseCache.mockUnplayedPhrases = [hardPhrase]
        
        phraseSystem.setDifficultyRange(min: 10, max: 50) // Easy range
        let result = await phraseSystem.getNextPhrase()
        
        XCTAssertNil(result, "Should return nil when no phrases match difficulty range")
    }
    
    func testDifficultyRangeUpdate() {
        phraseSystem.setDifficultyRange(min: 30, max: 80)
        
        XCTAssertEqual(phraseSystem.currentDifficultyRange.min, 30, "Should update min difficulty")
        XCTAssertEqual(phraseSystem.currentDifficultyRange.max, 80, "Should update max difficulty")
    }
    
    // MARK: - Cache Management Tests
    
    func testCacheRefreshWhenLow() async {
        // Setup: Cache has few phrases (< 10), we're online
        mockReachabilityManager.isOnline = true
        mockPhraseCache.mockUnplayedCount = 5 // Below threshold
        mockNetworkManager.mockServerPhrases = [
            createTestPhrase(id: "new1", content: "new phrase 1"),
            createTestPhrase(id: "new2", content: "new phrase 2")
        ]
        
        let result = await phraseSystem.getNextPhrase()
        
        XCTAssertTrue(mockNetworkManager.fetchPhrasesCalled, "Should fetch more phrases when cache is low")
        XCTAssertTrue(mockPhraseCache.addPhrasesCalled, "Should add new phrases to cache")
    }
    
    func testCacheNoRefreshWhenSufficient() async {
        // Setup: Cache has sufficient phrases (>= 10), we're online
        mockReachabilityManager.isOnline = true
        mockPhraseCache.mockUnplayedCount = 15 // Above threshold
        mockPhraseCache.mockUnplayedPhrases = [createTestPhrase(id: "cache1", content: "cached phrase")]
        
        let result = await phraseSystem.getNextPhrase()
        
        XCTAssertNotNil(result, "Should return cached phrase")
        XCTAssertFalse(mockNetworkManager.fetchPhrasesCalled, "Should not fetch when cache is sufficient")
    }
    
    func testAppLaunchPhrasePreload() async {
        // Setup: Fresh app launch, we're online
        mockReachabilityManager.isOnline = true
        mockPhraseCache.mockUnplayedCount = 0 // Empty cache
        mockNetworkManager.mockServerPhrases = Array(1...30).map { i in
            createTestPhrase(id: "preload\(i)", content: "preload phrase \(i)")
        }
        
        await phraseSystem.preloadPhrasesForNewSession()
        
        XCTAssertTrue(mockNetworkManager.fetchPhrasesCalled, "Should fetch phrases on app launch")
        XCTAssertTrue(mockPhraseCache.addPhrasesCalled, "Should cache preloaded phrases")
        XCTAssertEqual(mockPhraseCache.lastAddedPhrases.count, 30, "Should preload 30 phrases")
    }
    
    // MARK: - Error Handling Tests
    
    func testNetworkErrorHandling() async {
        // Setup: Online but network request fails
        mockReachabilityManager.isOnline = true
        mockPhraseCache.mockUnplayedPhrases = []
        mockNetworkManager.shouldFailFetch = true
        
        let result = await phraseSystem.getNextPhrase()
        
        XCTAssertNil(result, "Should return nil when network request fails")
        XCTAssertTrue(mockNetworkManager.fetchPhrasesCalled, "Should attempt network request")
        XCTAssertFalse(mockPhraseCache.addPhrasesCalled, "Should not cache when fetch fails")
    }
    
    func testCacheErrorHandling() {
        // Setup: Cache operations fail
        mockPhraseCache.shouldFailOperations = true
        
        let expectation = XCTestExpectation(description: "Should handle cache errors gracefully")
        
        Task {
            let result = await phraseSystem.getNextPhrase()
            // Should not crash, even with cache failures
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Empty Cache State Tests
    
    func testEmptyCacheStateDetection() {
        XCTAssertTrue(phraseSystem.isCacheEmpty(), "Should detect empty cache initially")
        
        mockPhraseCache.mockUnplayedCount = 5
        XCTAssertFalse(phraseSystem.isCacheEmpty(), "Should detect non-empty cache")
    }
    
    func testNeedsCacheRefreshDetection() {
        mockPhraseCache.mockUnplayedCount = 15
        XCTAssertFalse(phraseSystem.needsCacheRefresh(), "Should not need refresh with sufficient phrases")
        
        mockPhraseCache.mockUnplayedCount = 5
        XCTAssertTrue(phraseSystem.needsCacheRefresh(), "Should need refresh with few phrases")
        
        mockPhraseCache.mockUnplayedCount = 0
        XCTAssertTrue(phraseSystem.needsCacheRefresh(), "Should need refresh with empty cache")
    }
    
    // MARK: - Phrase Depletion Scenarios
    
    func testOfflinePhrasesDepletedState() async {
        // Setup: Offline, no phrases available
        mockReachabilityManager.isOnline = false
        mockPhraseCache.mockUnplayedPhrases = []
        
        let result = await phraseSystem.getNextPhrase()
        let isEmpty = phraseSystem.isCacheEmpty()
        let isOnline = phraseSystem.isOnline()
        
        XCTAssertNil(result, "Should return nil when offline with depleted cache")
        XCTAssertTrue(isEmpty, "Cache should be empty")
        XCTAssertFalse(isOnline, "Should be offline")
        
        // This state should trigger "No more phrases available" message in UI
    }
    
    func testOnlineButServerEmpty() async {
        // Setup: Online, but both cache and server are empty
        mockReachabilityManager.isOnline = true
        mockPhraseCache.mockUnplayedPhrases = []
        mockNetworkManager.mockServerPhrases = []
        
        let result = await phraseSystem.getNextPhrase()
        
        XCTAssertNil(result, "Should return nil when both cache and server are empty")
        XCTAssertTrue(phraseSystem.isOnline(), "Should be online")
        XCTAssertTrue(phraseSystem.isCacheEmpty(), "Cache should be empty")
    }
    
    // MARK: - Helper Methods
    
    private func createTestPhrase(id: String, content: String, difficulty: Int = 50, language: String = "en") -> CustomPhrase {
        return CustomPhrase(
            id: id,
            content: content,
            senderId: "test-sender",
            targetId: "test-target",
            createdAt: Date(),
            isConsumed: false,
            senderName: "Test Sender",
            language: language
        )
    }
}

// MARK: - Mock Classes

class MockNetworkManager: NetworkManagerProtocol {
    var mockServerPhrases: [CustomPhrase] = []
    var shouldFailFetch = false
    private(set) var fetchPhrasesCalled = false
    
    func fetchPhrasesForCurrentPlayer(difficultyRange: DifficultyRange? = nil) async -> [CustomPhrase] {
        fetchPhrasesCalled = true
        
        if shouldFailFetch {
            return []
        }
        
        if let range = difficultyRange {
            // Filter phrases by difficulty (for this mock, assume all phrases have difficulty 50)
            return mockServerPhrases.filter { phrase in
                let difficulty = 50 // Simplified for mock
                return difficulty >= range.min && difficulty <= range.max
            }
        }
        
        return mockServerPhrases
    }
    
    func isOnline() -> Bool {
        return true // Simplified for mock
    }
}

class MockPhraseCache: PhraseCacheProtocol {
    var mockUnplayedPhrases: [CustomPhrase] = []
    var mockPlayedPhraseIds: Set<String> = []
    var mockUnplayedCount = 0
    var shouldFailOperations = false
    
    private(set) var getRandomUnplayedPhraseCalled = false
    private(set) var addPhrasesCalled = false
    private(set) var getPhrasesInDifficultyRangeCalled = false
    private(set) var lastAddedPhrases: [CustomPhrase] = []
    
    func getRandomUnplayedPhrase() -> CustomPhrase? {
        getRandomUnplayedPhraseCalled = true
        if shouldFailOperations { return nil }
        return mockUnplayedPhrases.first
    }
    
    func addPhrases(_ phrases: [CustomPhrase]) {
        addPhrasesCalled = true
        lastAddedPhrases = phrases
        if !shouldFailOperations {
            mockUnplayedPhrases.append(contentsOf: phrases)
        }
    }
    
    func getUnplayedPhrasesCount() -> Int {
        return shouldFailOperations ? 0 : mockUnplayedCount
    }
    
    func isEmpty() -> Bool {
        return mockUnplayedPhrases.isEmpty
    }
    
    func getPhrasesInDifficultyRange(min: Int, max: Int) -> [CustomPhrase] {
        getPhrasesInDifficultyRangeCalled = true
        if shouldFailOperations { return [] }
        
        // For mock purposes, assume all phrases have difficulty 50
        return mockUnplayedPhrases.filter { _ in
            let difficulty = 50
            return difficulty >= min && difficulty <= max
        }
    }
    
    func markPhraseAsPlayed(_ phraseId: String) {
        mockPlayedPhraseIds.insert(phraseId)
        mockUnplayedPhrases.removeAll { $0.id == phraseId }
    }
    
    func clearCache() {
        mockUnplayedPhrases.removeAll()
        mockPlayedPhraseIds.removeAll()
        mockUnplayedCount = 0
    }
}

class MockReachabilityManager: ReachabilityManagerProtocol {
    var isOnline = false
    
    func isConnected() -> Bool {
        return isOnline
    }
    
    func startMonitoring() {
        // Mock implementation
    }
    
    func stopMonitoring() {
        // Mock implementation
    }
}

// MARK: - Protocol Definitions

protocol NetworkManagerProtocol {
    func fetchPhrasesForCurrentPlayer(difficultyRange: DifficultyRange?) async -> [CustomPhrase]
    func isOnline() -> Bool
}

protocol PhraseCacheProtocol {
    func getRandomUnplayedPhrase() -> CustomPhrase?
    func addPhrases(_ phrases: [CustomPhrase])
    func getUnplayedPhrasesCount() -> Int
    func isEmpty() -> Bool
    func getPhrasesInDifficultyRange(min: Int, max: Int) -> [CustomPhrase]
    func markPhraseAsPlayed(_ phraseId: String)
    func clearCache()
}

protocol ReachabilityManagerProtocol {
    func isConnected() -> Bool
    func startMonitoring()
    func stopMonitoring()
}

// MARK: - Supporting Types

struct DifficultyRange {
    let min: Int
    let max: Int
}

// Mock OfflinePhraseSystem class for testing
class OfflinePhraseSystem {
    private let networkManager: NetworkManagerProtocol
    private let phraseCache: PhraseCacheProtocol
    private let reachabilityManager: ReachabilityManagerProtocol
    
    private(set) var currentDifficultyRange = DifficultyRange(min: 0, max: 1000)
    
    init(networkManager: NetworkManagerProtocol, phraseCache: PhraseCacheProtocol, reachabilityManager: ReachabilityManagerProtocol) {
        self.networkManager = networkManager
        self.phraseCache = phraseCache
        self.reachabilityManager = reachabilityManager
    }
    
    func getNextPhrase() async -> CustomPhrase? {
        // Check cache first
        if let cachedPhrase = phraseCache.getRandomUnplayedPhrase() {
            return cachedPhrase
        }
        
        // If cache is empty and we're online, try server
        if reachabilityManager.isConnected() {
            let serverPhrases = await networkManager.fetchPhrasesForCurrentPlayer(difficultyRange: currentDifficultyRange)
            
            if !serverPhrases.isEmpty {
                phraseCache.addPhrases(serverPhrases)
                return phraseCache.getRandomUnplayedPhrase()
            }
        }
        
        return nil
    }
    
    func setDifficultyRange(min: Int, max: Int) {
        currentDifficultyRange = DifficultyRange(min: min, max: max)
    }
    
    func isCacheEmpty() -> Bool {
        return phraseCache.isEmpty()
    }
    
    func needsCacheRefresh() -> Bool {
        return phraseCache.getUnplayedPhrasesCount() < 10
    }
    
    func isOnline() -> Bool {
        return reachabilityManager.isConnected()
    }
    
    func preloadPhrasesForNewSession() async {
        if reachabilityManager.isConnected() {
            let phrases = await networkManager.fetchPhrasesForCurrentPlayer(difficultyRange: currentDifficultyRange)
            if !phrases.isEmpty {
                phraseCache.addPhrases(phrases)
            }
        }
    }
}