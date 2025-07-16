import Foundation
import Combine

/// Manages phrase selection with cache-first strategy and offline fallback
@Observable
class PhraseManager {
    
    // MARK: - Dependencies
    
    private let phraseCache = PhraseCache()
    private var networkManager: NetworkManager { NetworkManager.shared }
    
    // MARK: - Observable Properties
    
    private(set) var cacheStatus: String = "Initializing..."
    private(set) var lastFetchTime: Date?
    private(set) var totalCachedPhrases: Int = 0
    private(set) var unplayedPhrasesCount: Int = 0
    
    // MARK: - Initialization
    
    init() {
        initializeCache()
        setupNetworkObservers()
    }
    
    // MARK: - Public Methods
    
    /// Gets the next phrase with cache-first strategy
    @MainActor
    func getNextPhrase() async -> CustomPhrase? {
        print("🔍 PHRASE MANAGER: Getting next phrase")
        
        // First, try to get from cache
        if let cachedPhrase = phraseCache.getRandomUnplayedPhrase() {
            print("✅ PHRASE MANAGER: Found cached phrase: '\(cachedPhrase.customPhrase.content)' from \(cachedPhrase.customPhrase.senderName)")
            return cachedPhrase.customPhrase
        }
        
        // If cache is empty, try to fetch from server
        print("🌐 PHRASE MANAGER: Cache empty, fetching from server")
        print("🔍 PHRASE MANAGER: NetworkManager currentPlayer: \(networkManager.currentPlayer?.name ?? "nil")")
        
        // Check if NetworkManager is properly initialized
        if networkManager.currentPlayer == nil {
            print("⚠️ PHRASE MANAGER: currentPlayer is nil - registration may not be complete")
        }
        
        let phrases = await networkManager.fetchPhrasesForCurrentPlayer()
        print("🔍 PHRASE MANAGER: Received \(phrases.count) phrases from server")
        
        if let firstPhrase = phrases.first {
            print("✅ PHRASE MANAGER: Got phrase from server: '\(firstPhrase.content)' from \(firstPhrase.senderName)")
            
            // Cache the phrase for future use
            let difficulty = getServerDifficulty(for: firstPhrase) ?? calculateDifficultyScore(for: firstPhrase.content)
            phraseCache.addPhrases([firstPhrase], withDifficulties: [difficulty])
            updateCacheStatus()
            
            return firstPhrase
        } else {
            print("🔍 PHRASE MANAGER: No phrases from server, checking currentPlayer again")
            print("🔍 PHRASE MANAGER: Final currentPlayer check: \(networkManager.currentPlayer?.name ?? "nil")")
        }
        
        print("❌ PHRASE MANAGER: No phrases available from server")
        return nil
    }
    
    /// Marks a phrase as played
    func markPhraseAsPlayed(_ phraseId: String, score: Int? = nil) {
        phraseCache.markPhraseAsPlayed(phraseId, score: score)
        updateCacheStatus()
        
        // Check if we need to refresh cache
        if phraseCache.getUnplayedPhrasesCount() < 10 {
            Task {
                await refreshCacheInBackground()
            }
        }
    }
    
    /// Forces a cache refresh from server
    @MainActor
    func refreshCache() async -> Bool {
        print("🔄 PHRASE MANAGER: Attempting to refresh cache")
        return await fetchAndCachePhrasesInBackground()
    }
    
    /// Gets cache statistics for debugging
    func getCacheStatistics() -> CacheStatistics {
        return phraseCache.getCacheStatistics()
    }
    
    /// Gets a health report for debugging
    @MainActor
    func getHealthReport() -> String {
        let reachability = networkManager.isOnline ? "Online" : "Offline"
        let cacheReport = phraseCache.getHealthReport()
        
        return """
        🎯 Phrase Manager Status:
        - Network: \(reachability)
        - Last fetch: \(lastFetchTime?.formatted() ?? "Never")
        
        \(cacheReport)
        """
    }
    
    /// Gets phrase availability status for UI
    func getAvailabilityStatus() -> PhraseAvailabilityStatus {
        return phraseCache.getAvailabilityStatus()
    }
    
    /// Gets user-friendly status message for UI
    @MainActor
    func getStatusMessage() -> String {
        let cacheStatus = phraseCache.getAvailabilityStatus()
        
        // Always try to be optimistic about network connectivity since HTTP requests work
        switch cacheStatus {
        case .empty:
            return "Downloading phrases..."
        case .allPlayed:
            return "Getting new phrases..."
        case .low(let remaining):
            return "\(remaining) phrases left - downloading more"
        case .good(let available):
            return "\(available) phrases ready to play"
        }
    }
    
    // MARK: - Private Methods
    
    /// Initializes the phrase cache
    private func initializeCache() {
        // Load existing cache
        let _ = phraseCache.loadCache()
        
        // Perform maintenance
        phraseCache.performMaintenance()
        
        // Update status
        updateCacheStatus()
        
        // Log cache contents for debugging
        let unplayedCount = phraseCache.getUnplayedPhrasesCount()
        print("📱 PHRASE MANAGER: Initialized with \(totalCachedPhrases) cached phrases, \(unplayedCount) unplayed")
        
        // If cache is low, try to fetch in background
        if unplayedCount < 10 {
            Task {
                await refreshCacheInBackground()
            }
        }
    }
    
    /// Sets up network state observers
    private func setupNetworkObservers() {
        // Monitor network connectivity changes using periodic checks
        // Note: For @Observable classes, we use periodic checking instead of publishers
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                if self.phraseCache.getUnplayedPhrasesCount() < 10 {
                    print("✅ PHRASE MANAGER: Cache low, refreshing")
                    await self.refreshCacheInBackground()
                }
            }
        }
    }
    
    /// Updates cache status properties
    private func updateCacheStatus() {
        totalCachedPhrases = phraseCache.getCachedPhrasesCount()
        unplayedPhrasesCount = phraseCache.getUnplayedPhrasesCount()
        
        if totalCachedPhrases == 0 {
            cacheStatus = "Empty - need internet connection"
        } else if unplayedPhrasesCount == 0 {
            cacheStatus = "All phrases played - refreshing..."
        } else if unplayedPhrasesCount < 5 {
            cacheStatus = "Low (\(unplayedPhrasesCount) remaining)"
        } else {
            cacheStatus = "Good (\(unplayedPhrasesCount) available)"
        }
    }
    
    /// Fetches a single phrase and caches it
    private func fetchAndCachePhrase() async -> CustomPhrase? {
        let phrases = await networkManager.fetchPhrasesForCurrentPlayer()
        
        if let firstPhrase = phrases.first {
            // Use server's difficulty level if available, otherwise calculate locally
            let difficulty = getServerDifficulty(for: firstPhrase) ?? calculateDifficultyScore(for: firstPhrase.content)
            
            // Add to cache
            phraseCache.addPhrases([firstPhrase], withDifficulties: [difficulty])
            
            lastFetchTime = Date()
            updateCacheStatus()
            
            print("📦 PHRASE MANAGER: Fetched and cached 1 phrase from server")
            return firstPhrase
        }
        
        print("❌ PHRASE MANAGER: No phrases available from server")
        return nil
    }
    
    /// Refreshes cache in background
    private func refreshCacheInBackground() async {
        let _ = await fetchAndCachePhrasesInBackground()
    }
    
    /// Fetches and caches multiple phrases from server
    @MainActor
    private func fetchAndCachePhrasesInBackground() async -> Bool {
        print("🔍 PHRASE MANAGER: Starting background fetch...")
        let phrases = await networkManager.fetchPhrasesForCurrentPlayer()
        print("🔍 PHRASE MANAGER: Received \(phrases.count) phrases from NetworkManager")
        
        // DEBUG: Log cache status before adding phrases
        let beforeCount = phraseCache.getUnplayedPhrasesCount()
        print("🔍 PHRASE MANAGER: Cache before adding: \(beforeCount) unplayed phrases")
        
        if !phrases.isEmpty {
            // Use server's difficulty levels where available, otherwise calculate locally
            let difficulties = phrases.map { phrase in
                getServerDifficulty(for: phrase) ?? calculateDifficultyScore(for: phrase.content)
            }
            
            // Add to cache
            phraseCache.addPhrases(phrases, withDifficulties: difficulties)
            
            lastFetchTime = Date()
            updateCacheStatus()
            
            let newUnplayedCount = phraseCache.getUnplayedPhrasesCount()
            print("📦 PHRASE MANAGER: Fetched and cached \(phrases.count) phrases from server")
            print("📦 PHRASE MANAGER: Cache now has \(newUnplayedCount) unplayed phrases")
            
            // DEBUG: Log detailed caching results
            print("🔍 PHRASE MANAGER: Called phraseCache.addPhrases with \(phrases.count) phrases")
            print("🔍 PHRASE MANAGER: Cache after adding: \(newUnplayedCount) unplayed phrases")
            
            return true
        }
        
        print("❌ PHRASE MANAGER: No phrases available from server for background fetch")
        return false
    }
    
    /// Gets the server's difficulty level for a phrase
    private func getServerDifficulty(for phrase: CustomPhrase) -> Int? {
        return phrase.difficultyLevel
    }
    
    /// Calculates difficulty score for a phrase (fallback when server doesn't provide it)
    private func calculateDifficultyScore(for content: String) -> Int {
        let words = content.components(separatedBy: " ")
        let totalLetters = content.replacingOccurrences(of: " ", with: "").count
        
        // Simple difficulty calculation adjusted for level 1 range (0-50)
        let baseScore = 10 + (words.count * 5) + (totalLetters * 1)
        
        // Cap between 0-50 to match level 1 difficulty range
        return min(max(baseScore, 0), 50)
    }
    
}

// MARK: - Integration Helpers

extension PhraseManager {
    
    /// Checks if we have any phrases available (cache or network)
    @MainActor
    var hasPhrasesAvailable: Bool {
        return phraseCache.hasUnplayedPhrases() || networkManager.isOnline
    }
    
    /// Gets the number of phrases that should be cached
    @MainActor
    var shouldRefreshCache: Bool {
        return phraseCache.getUnplayedPhrasesCount() < 10 && networkManager.isOnline
    }
    
    /// Preloads cache if needed (call after player registration)
    @MainActor
    func preloadCacheIfNeeded() async {
        let unplayedCount = phraseCache.getUnplayedPhrasesCount()
        print("📱 PHRASE MANAGER: Preload check - unplayed count: \(unplayedCount)")
        if unplayedCount < 20 {
            print("📱 PHRASE MANAGER: Preloading cache after registration")
            let success = await fetchAndCachePhrasesInBackground()
            print("📱 PHRASE MANAGER: Preload result: \(success)")
            let newUnplayedCount = phraseCache.getUnplayedPhrasesCount()
            print("📱 PHRASE MANAGER: After preload - unplayed count: \(newUnplayedCount)")
        }
    }
}