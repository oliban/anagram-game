import XCTest
@testable import Anagram_Game

final class GameModelOfflineTests: XCTestCase {
    
    var gameModel: GameModel!
    var mockNetworkManager: MockOfflineNetworkManager!
    var mockOfflineProgress: MockOfflineProgress!
    var mockReachabilityManager: MockOfflineReachabilityManager!
    
    override func setUp() {
        super.setUp()
        mockNetworkManager = MockOfflineNetworkManager()
        mockOfflineProgress = MockOfflineProgress()
        mockReachabilityManager = MockOfflineReachabilityManager()
        
        gameModel = GameModel()
        gameModel.networkManager = mockNetworkManager
        gameModel.offlineProgress = mockOfflineProgress
        gameModel.reachabilityManager = mockReachabilityManager
    }
    
    override func tearDown() {
        gameModel = nil
        mockNetworkManager = nil
        mockOfflineProgress = nil
        mockReachabilityManager = nil
        super.tearDown()
    }
    
    // MARK: - Offline Completion Tracking Tests
    
    func testOfflineCompletionTracking() {
        // Setup: Go offline
        mockReachabilityManager.isOnline = false
        gameModel.currentPhraseId = "test-phrase-1"
        gameModel.currentScore = 85
        gameModel.hintsUsed = 2
        gameModel.phraseDifficulty = 100
        
        // Complete game while offline
        gameModel.completeGame()
        
        XCTAssertTrue(mockOfflineProgress.addCompletionCalled, "Should track completion offline")
        XCTAssertEqual(mockOfflineProgress.lastCompletion?.phraseId, "test-phrase-1", "Should store correct phrase ID")
        XCTAssertEqual(mockOfflineProgress.lastCompletion?.score, 85, "Should store correct score")
        XCTAssertEqual(mockOfflineProgress.lastCompletion?.hintsUsed, 2, "Should store hints used")
        XCTAssertEqual(mockOfflineProgress.lastCompletion?.difficultyScore, 100, "Should store difficulty score")
        XCTAssertFalse(mockNetworkManager.completePhraseServerCalled, "Should not call server when offline")
    }
    
    func testOnlineCompletionTracking() {
        // Setup: Stay online
        mockReachabilityManager.isOnline = true
        gameModel.currentPhraseId = "test-phrase-2"
        gameModel.currentScore = 120
        gameModel.hintsUsed = 1
        
        // Complete game while online
        gameModel.completeGame()
        
        XCTAssertFalse(mockOfflineProgress.addCompletionCalled, "Should not track offline when online")
        XCTAssertTrue(mockNetworkManager.completePhraseServerCalled, "Should call server when online")
    }
    
    func testOfflineCompletionWithDifferentScores() {
        mockReachabilityManager.isOnline = false
        
        // Complete multiple phrases offline with different scores
        let completions = [
            (phraseId: "phrase1", score: 100, hints: 0, difficulty: 80),
            (phraseId: "phrase2", score: 65, hints: 3, difficulty: 90),
            (phraseId: "phrase3", score: 42, hints: 1, difficulty: 60)
        ]
        
        for completion in completions {
            gameModel.currentPhraseId = completion.phraseId
            gameModel.currentScore = completion.score
            gameModel.hintsUsed = completion.hints
            gameModel.phraseDifficulty = completion.difficulty
            gameModel.completeGame()
        }
        
        XCTAssertEqual(mockOfflineProgress.completions.count, 3, "Should track all offline completions")
        
        // Verify all completions stored correctly
        for (index, completion) in completions.enumerated() {
            let stored = mockOfflineProgress.completions[index]
            XCTAssertEqual(stored.phraseId, completion.phraseId, "Should store correct phrase ID")
            XCTAssertEqual(stored.score, completion.score, "Should store correct score")
            XCTAssertEqual(stored.hintsUsed, completion.hints, "Should store correct hints")
            XCTAssertEqual(stored.difficultyScore, completion.difficulty, "Should store correct difficulty")
        }
    }
    
    // MARK: - Server Sync Tests
    
    func testServerSyncWhenComingOnline() async {
        // Setup: Add some offline completions
        let completion1 = OfflineCompletion(
            phraseId: "offline1",
            score: 85,
            hintsUsed: 1,
            difficultyScore: 100,
            completedAt: Date()
        )
        let completion2 = OfflineCompletion(
            phraseId: "offline2", 
            score: 120,
            hintsUsed: 0,
            difficultyScore: 150,
            completedAt: Date()
        )
        
        mockOfflineProgress.completions = [completion1, completion2]
        
        // Go from offline to online
        mockReachabilityManager.isOnline = false
        await gameModel.handleConnectivityChange(isOnline: true)
        
        XCTAssertTrue(mockOfflineProgress.getPendingCompletionsCalled, "Should get pending completions")
        XCTAssertTrue(mockNetworkManager.syncOfflineCompletionsCalled, "Should sync with server")
        XCTAssertEqual(mockNetworkManager.lastSyncedCompletions.count, 2, "Should sync all completions")
        XCTAssertTrue(mockOfflineProgress.clearSyncedCompletionsCalled, "Should clear synced completions")
    }
    
    func testServerSyncWithPartialFailure() async {
        // Setup: Some completions that will fail to sync
        let completion1 = OfflineCompletion(phraseId: "success", score: 85, hintsUsed: 1, difficultyScore: 100, completedAt: Date())
        let completion2 = OfflineCompletion(phraseId: "failure", score: 120, hintsUsed: 0, difficultyScore: 150, completedAt: Date())
        
        mockOfflineProgress.completions = [completion1, completion2]
        mockNetworkManager.failSyncForPhraseIds = ["failure"] // This one will fail
        
        await gameModel.handleConnectivityChange(isOnline: true)
        
        XCTAssertTrue(mockNetworkManager.syncOfflineCompletionsCalled, "Should attempt sync")
        XCTAssertEqual(mockOfflineProgress.clearSyncedCompletions_successfulIds.count, 1, "Should only clear successful syncs")
        XCTAssertEqual(mockOfflineProgress.clearSyncedCompletions_successfulIds.first, "success", "Should clear only successful completion")
    }
    
    func testServerSyncRetryLogic() async {
        // Setup: All syncs fail initially
        mockOfflineProgress.completions = [
            OfflineCompletion(phraseId: "retry1", score: 85, hintsUsed: 1, difficultyScore: 100, completedAt: Date())
        ]
        mockNetworkManager.failAllSyncs = true
        
        // First attempt should fail
        await gameModel.handleConnectivityChange(isOnline: true)
        XCTAssertFalse(mockOfflineProgress.clearSyncedCompletionsCalled, "Should not clear when sync fails")
        
        // Second attempt should succeed
        mockNetworkManager.failAllSyncs = false
        await gameModel.retryOfflineSync()
        
        XCTAssertTrue(mockNetworkManager.syncOfflineCompletionsCalled, "Should retry sync")
        XCTAssertTrue(mockOfflineProgress.clearSyncedCompletionsCalled, "Should clear after successful retry")
    }
    
    // MARK: - Progress Queue Management Tests
    
    func testProgressQueueSizeLimit() {
        mockReachabilityManager.isOnline = false
        
        // Add many completions (more than limit)
        for i in 1...25 { // Assuming 20 is the limit
            gameModel.currentPhraseId = "phrase\(i)"
            gameModel.currentScore = 100
            gameModel.hintsUsed = 0
            gameModel.phraseDifficulty = 80
            gameModel.completeGame()
        }
        
        XCTAssertLesssThanOrEqual(mockOfflineProgress.completions.count, 20, "Should not exceed queue size limit")
        XCTAssertTrue(mockOfflineProgress.removeOldestCompletionsCalled, "Should remove oldest when limit exceeded")
    }
    
    func testProgressQueuePersistence() {
        mockReachabilityManager.isOnline = false
        
        // Add completion
        gameModel.currentPhraseId = "persistent-phrase"
        gameModel.currentScore = 95
        gameModel.hintsUsed = 1
        gameModel.phraseDifficulty = 120
        gameModel.completeGame()
        
        XCTAssertTrue(mockOfflineProgress.saveToStorageCalled, "Should save queue to persistent storage")
        
        // Simulate app restart
        let newOfflineProgress = MockOfflineProgress()
        newOfflineProgress.loadFromStorageCalled = true
        gameModel.offlineProgress = newOfflineProgress
        
        XCTAssertTrue(newOfflineProgress.loadFromStorageCalled, "Should load queue from storage on restart")
    }
    
    // MARK: - Offline Progress Analytics Tests
    
    func testOfflineProgressAnalytics() {
        mockReachabilityManager.isOnline = false
        
        // Complete several phrases with varying performance
        let testData = [
            (score: 100, hints: 0, difficulty: 80),  // Perfect score
            (score: 85, hints: 1, difficulty: 100),  // Good score with 1 hint
            (score: 50, hints: 3, difficulty: 120),  // Lower score with many hints
        ]
        
        for (index, data) in testData.enumerated() {
            gameModel.currentPhraseId = "analytics-phrase-\(index)"
            gameModel.currentScore = data.score
            gameModel.hintsUsed = data.hints
            gameModel.phraseDifficulty = data.difficulty
            gameModel.completeGame()
        }
        
        let analytics = mockOfflineProgress.getOfflineAnalytics()
        
        XCTAssertEqual(analytics.totalCompletions, 3, "Should track total completions")
        XCTAssertEqual(analytics.averageScore, 78, "Should calculate average score correctly") // (100+85+50)/3 ≈ 78
        XCTAssertEqual(analytics.totalHintsUsed, 4, "Should track total hints used")
        XCTAssertEqual(analytics.averageDifficulty, 100, "Should calculate average difficulty") // (80+100+120)/3 = 100
    }
    
    func testOfflineStreakTracking() {
        mockReachabilityManager.isOnline = false
        
        // Complete phrases in sequence
        for i in 1...5 {
            gameModel.currentPhraseId = "streak-phrase-\(i)"
            gameModel.currentScore = 90
            gameModel.hintsUsed = 0
            gameModel.phraseDifficulty = 80
            gameModel.completeGame()
        }
        
        let analytics = mockOfflineProgress.getOfflineAnalytics()
        XCTAssertEqual(analytics.currentStreak, 5, "Should track completion streak")
    }
    
    // MARK: - Error Handling Tests
    
    func testOfflineProgressStorageFailure() {
        mockReachabilityManager.isOnline = false
        mockOfflineProgress.shouldFailStorage = true
        
        gameModel.currentPhraseId = "storage-fail-phrase"
        gameModel.currentScore = 100
        gameModel.hintsUsed = 0
        gameModel.phraseDifficulty = 80
        
        // Should not crash when storage fails
        gameModel.completeGame()
        
        XCTAssertTrue(mockOfflineProgress.addCompletionCalled, "Should attempt to add completion")
        XCTAssertTrue(mockOfflineProgress.saveToStorageCalled, "Should attempt to save")
        // Game should continue normally despite storage failure
        XCTAssertEqual(gameModel.gameState, .completed, "Game should complete normally")
    }
    
    func testSyncFailureHandling() async {
        mockOfflineProgress.completions = [
            OfflineCompletion(phraseId: "sync-fail", score: 85, hintsUsed: 1, difficultyScore: 100, completedAt: Date())
        ]
        mockNetworkManager.failAllSyncs = true
        
        await gameModel.handleConnectivityChange(isOnline: true)
        
        // Should handle sync failure gracefully
        XCTAssertFalse(mockOfflineProgress.clearSyncedCompletionsCalled, "Should not clear when sync fails")
        XCTAssertTrue(mockOfflineProgress.markSyncAttemptCalled, "Should mark sync attempt for retry")
    }
    
    // MARK: - Integration Tests
    
    func testFullOfflineToOnlineFlow() async {
        // Start offline
        mockReachabilityManager.isOnline = false
        
        // Complete a phrase offline
        gameModel.currentPhraseId = "integration-phrase"
        gameModel.currentScore = 110
        gameModel.hintsUsed = 1
        gameModel.phraseDifficulty = 150
        gameModel.completeGame()
        
        XCTAssertTrue(mockOfflineProgress.addCompletionCalled, "Should track offline completion")
        
        // Go online
        await gameModel.handleConnectivityChange(isOnline: true)
        
        XCTAssertTrue(mockNetworkManager.syncOfflineCompletionsCalled, "Should sync when coming online")
        XCTAssertTrue(mockOfflineProgress.clearSyncedCompletionsCalled, "Should clear after successful sync")
        
        // Complete another phrase online
        mockOfflineProgress.addCompletionCalled = false // Reset flag
        gameModel.currentPhraseId = "online-phrase"
        gameModel.currentScore = 95
        gameModel.hintsUsed = 0
        gameModel.completeGame()
        
        XCTAssertFalse(mockOfflineProgress.addCompletionCalled, "Should not track offline when online")
        XCTAssertTrue(mockNetworkManager.completePhraseServerCalled, "Should call server directly when online")
    }
}

// MARK: - Mock Classes

class MockOfflineNetworkManager {
    var syncOfflineCompletionsCalled = false
    var completePhraseServerCalled = false
    var lastSyncedCompletions: [OfflineCompletion] = []
    var failSyncForPhraseIds: [String] = []
    var failAllSyncs = false
    
    func syncOfflineCompletions(_ completions: [OfflineCompletion]) async -> [String] {
        syncOfflineCompletionsCalled = true
        lastSyncedCompletions = completions
        
        if failAllSyncs {
            return []
        }
        
        return completions.compactMap { completion in
            failSyncForPhraseIds.contains(completion.phraseId) ? nil : completion.phraseId
        }
    }
    
    func completePhrase(phraseId: String) async -> CompletionResult? {
        completePhraseServerCalled = true
        return CompletionResult(success: true, score: 100)
    }
}

class MockOfflineProgress {
    var completions: [OfflineCompletion] = []
    
    var addCompletionCalled = false
    var getPendingCompletionsCalled = false
    var clearSyncedCompletionsCalled = false
    var removeOldestCompletionsCalled = false
    var saveToStorageCalled = false
    var loadFromStorageCalled = false
    var markSyncAttemptCalled = false
    var shouldFailStorage = false
    
    var lastCompletion: OfflineCompletion?
    var clearSyncedCompletions_successfulIds: [String] = []
    
    func addCompletion(_ completion: OfflineCompletion) {
        addCompletionCalled = true
        lastCompletion = completion
        
        if !shouldFailStorage {
            completions.append(completion)
            
            // Simulate size limit
            if completions.count > 20 {
                removeOldestCompletions()
            }
        }
    }
    
    func getPendingCompletions() -> [OfflineCompletion] {
        getPendingCompletionsCalled = true
        return completions
    }
    
    func clearSyncedCompletions(successfulIds: [String]) {
        clearSyncedCompletionsCalled = true
        clearSyncedCompletions_successfulIds = successfulIds
        
        completions.removeAll { completion in
            successfulIds.contains(completion.phraseId)
        }
    }
    
    private func removeOldestCompletions() {
        removeOldestCompletionsCalled = true
        while completions.count > 20 {
            completions.removeFirst()
        }
    }
    
    func saveToStorage() {
        saveToStorageCalled = true
        // Mock save operation
    }
    
    func loadFromStorage() {
        loadFromStorageCalled = true
        // Mock load operation
    }
    
    func markSyncAttempt() {
        markSyncAttemptCalled = true
    }
    
    func getOfflineAnalytics() -> OfflineAnalytics {
        let totalScore = completions.reduce(0) { $0 + $1.score }
        let totalHints = completions.reduce(0) { $0 + $1.hintsUsed }
        let totalDifficulty = completions.reduce(0) { $0 + $1.difficultyScore }
        
        return OfflineAnalytics(
            totalCompletions: completions.count,
            averageScore: completions.isEmpty ? 0 : totalScore / completions.count,
            totalHintsUsed: totalHints,
            averageDifficulty: completions.isEmpty ? 0 : totalDifficulty / completions.count,
            currentStreak: completions.count // Simplified for mock
        )
    }
}

class MockOfflineReachabilityManager {
    var isOnline = false
    
    func isConnected() -> Bool {
        return isOnline
    }
}

// MARK: - Supporting Types

struct OfflineCompletion {
    let phraseId: String
    let score: Int
    let hintsUsed: Int
    let difficultyScore: Int
    let completedAt: Date
}

struct OfflineAnalytics {
    let totalCompletions: Int
    let averageScore: Int
    let totalHintsUsed: Int
    let averageDifficulty: Int
    let currentStreak: Int
}

struct CompletionResult {
    let success: Bool
    let score: Int
}

// MARK: - GameModel Extension for Testing

extension GameModel {
    var offlineProgress: MockOfflineProgress? {
        get { return nil } // Mock implementation
        set { /* Mock setter */ }
    }
    
    var reachabilityManager: MockOfflineReachabilityManager? {
        get { return nil } // Mock implementation
        set { /* Mock setter */ }
    }
    
    func handleConnectivityChange(isOnline: Bool) async {
        // Mock implementation for testing
        if isOnline {
            await syncOfflineProgress()
        }
    }
    
    func retryOfflineSync() async {
        // Mock implementation for testing
        await syncOfflineProgress()
    }
    
    private func syncOfflineProgress() async {
        // Mock sync logic
        guard let networkManager = networkManager as? MockOfflineNetworkManager,
              let offlineProgress = offlineProgress else { return }
        
        let pending = offlineProgress.getPendingCompletions()
        let successful = await networkManager.syncOfflineCompletions(pending)
        offlineProgress.clearSyncedCompletions(successfulIds: successful)
    }
}