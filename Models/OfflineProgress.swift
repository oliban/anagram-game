import Foundation
import Combine

/// Represents a game completion that occurred while offline
struct OfflineCompletion: Codable, Identifiable, Equatable {
    let id: String
    let phraseId: String
    let playerId: String
    let phraseContent: String
    let score: Int
    let timeToComplete: Double
    let hintsUsed: Int
    let completedAt: Date
    let difficultyScore: Int
    
    /// Creates a new offline completion record
    init(phraseId: String, playerId: String, phraseContent: String, score: Int, timeToComplete: Double, hintsUsed: Int, difficultyScore: Int) {
        self.id = UUID().uuidString
        self.phraseId = phraseId
        self.playerId = playerId
        self.phraseContent = phraseContent
        self.score = score
        self.timeToComplete = timeToComplete
        self.hintsUsed = hintsUsed
        self.completedAt = Date()
        self.difficultyScore = difficultyScore
    }
    
    /// Gets a summary for debugging
    var summary: String {
        return "\(phraseContent) - \(score) pts (\(hintsUsed) hints, \(Int(timeToComplete))s)"
    }
}

/// Manages offline progress tracking and server synchronization
@Observable
class OfflineProgressManager {
    
    // MARK: - Observable Properties
    
    private(set) var pendingCompletions: [OfflineCompletion] = []
    private(set) var syncInProgress: Bool = false
    private(set) var lastSyncTime: Date?
    private(set) var syncErrors: [String] = []
    
    // MARK: - Configuration
    
    private let userDefaultsKey = "OfflineCompletions"
    private let syncErrorsKey = "OfflineSyncErrors"
    private let lastSyncKey = "LastOfflineSync"
    private let maxRetryAttempts = 3
    private let maxQueueSize = 100
    
    // MARK: - Dependencies
    
    private let userDefaults: UserDefaults
    private let networkManager = NetworkManager.shared
    
    // MARK: - Initialization
    
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadFromStorage()
        setupNetworkObserver()
    }
    
    // MARK: - Public Methods
    
    /// Records a game completion while offline
    func recordCompletion(
        phraseId: String,
        playerId: String,
        phraseContent: String,
        score: Int,
        timeToComplete: Double,
        hintsUsed: Int,
        difficultyScore: Int
    ) {
        let completion = OfflineCompletion(
            phraseId: phraseId,
            playerId: playerId,
            phraseContent: phraseContent,
            score: score,
            timeToComplete: timeToComplete,
            hintsUsed: hintsUsed,
            difficultyScore: difficultyScore
        )
        
        addCompletion(completion)
        print("📱 OFFLINE: Recorded completion - \(completion.summary)")
    }
    
    /// Manually triggers sync with server (returns success status)
    @MainActor
    func syncWithServer() async -> Bool {
        guard !syncInProgress else {
            print("⏳ OFFLINE: Sync already in progress")
            return false
        }
        
        guard networkManager.isOnline else {
            print("❌ OFFLINE: Cannot sync - no internet connection")
            return false
        }
        
        guard !pendingCompletions.isEmpty else {
            print("✅ OFFLINE: No pending completions to sync")
            return true
        }
        
        return await performSync()
    }
    
    /// Gets count of pending completions
    var pendingCount: Int {
        return pendingCompletions.count
    }
    
    /// Checks if there are any pending completions
    var hasPendingCompletions: Bool {
        return !pendingCompletions.isEmpty
    }
    
    /// Gets summary of offline progress
    func getProgressSummary() -> String {
        let pending = pendingCompletions.count
        let lastSync = lastSyncTime?.formatted(.dateTime.hour().minute()) ?? "Never"
        let errorCount = syncErrors.count
        
        var summary = """
        📱 Offline Progress:
        - Pending completions: \(pending)
        - Last sync: \(lastSync)
        """
        
        if errorCount > 0 {
            summary += "\n- Sync errors: \(errorCount)"
        }
        
        if syncInProgress {
            summary += "\n- Status: Syncing..."
        }
        
        return summary
    }
    
    /// Clears all sync errors
    func clearSyncErrors() {
        syncErrors.removeAll()
        saveToStorage()
        print("🧹 OFFLINE: Cleared sync errors")
    }
    
    /// Clears all pending completions (use carefully!)
    func clearAllPendingCompletions() {
        pendingCompletions.removeAll()
        saveToStorage()
        print("🗑️ OFFLINE: Cleared all pending completions")
    }
    
    // MARK: - Private Methods
    
    /// Adds a completion to the queue
    private func addCompletion(_ completion: OfflineCompletion) {
        // Prevent duplicate completions for the same phrase
        if pendingCompletions.contains(where: { $0.phraseId == completion.phraseId }) {
            print("⚠️ OFFLINE: Duplicate completion for phrase \(completion.phraseId), skipping")
            return
        }
        
        pendingCompletions.append(completion)
        
        // Enforce queue size limit (remove oldest)
        while pendingCompletions.count > maxQueueSize {
            let removed = pendingCompletions.removeFirst()
            print("⚠️ OFFLINE: Queue full, removed oldest completion: \(removed.summary)")
        }
        
        saveToStorage()
    }
    
    /// Sets up network connectivity observer
    private func setupNetworkObserver() {
        // Monitor when network comes back online
        // Note: For @Observable classes, we'll implement periodic checking or use notifications
        // since direct observation isn't available like with @Published
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                if self.networkManager.isOnline && !self.pendingCompletions.isEmpty && !self.syncInProgress {
                    print("✅ OFFLINE: Network restored, starting sync")
                    let _ = await self.syncWithServer()
                }
            }
        }
    }
    
    /// Performs the actual sync operation
    private func performSync() async -> Bool {
        syncInProgress = true
        
        let completionsToSync = Array(pendingCompletions)
        var successCount = 0
        var failureCount = 0
        
        print("🔄 OFFLINE: Starting sync of \(completionsToSync.count) completions")
        
        for completion in completionsToSync {
            let success = await syncSingleCompletion(completion)
            
            if success {
                // Remove from pending queue
                if let index = pendingCompletions.firstIndex(where: { $0.id == completion.id }) {
                    pendingCompletions.remove(at: index)
                }
                successCount += 1
            } else {
                failureCount += 1
            }
        }
        
        // Update sync time if we had any success
        if successCount > 0 {
            lastSyncTime = Date()
        }
        
        syncInProgress = false
        saveToStorage()
        
        print("✅ OFFLINE: Sync completed - \(successCount) success, \(failureCount) failed")
        
        return failureCount == 0
    }
    
    /// Syncs a single completion with the server
    private func syncSingleCompletion(_ completion: OfflineCompletion) async -> Bool {
        // Try to submit the completion to the server
        let success = await networkManager.submitGameCompletion(
            phraseId: completion.phraseId,
            playerId: completion.playerId,
            timeToComplete: completion.timeToComplete,
            hintsUsed: completion.hintsUsed,
            score: completion.score
        )
        
        if success {
            print("✅ OFFLINE: Synced completion - \(completion.summary)")
            return true
        } else {
            let errorMsg = "Failed to sync completion for phrase \(completion.phraseId)"
            addSyncError(errorMsg)
            print("❌ OFFLINE: \(errorMsg)")
            return false
        }
    }
    
    /// Adds a sync error to the error list
    private func addSyncError(_ error: String) {
        let timestampedError = "[\(Date().formatted(.dateTime.hour().minute()))] \(error)"
        syncErrors.append(timestampedError)
        
        // Keep only last 10 errors
        while syncErrors.count > 10 {
            syncErrors.removeFirst()
        }
    }
    
    /// Saves data to UserDefaults
    private func saveToStorage() {
        do {
            // Save pending completions
            let completionsData = try JSONEncoder().encode(pendingCompletions)
            userDefaults.set(completionsData, forKey: userDefaultsKey)
            
            // Save sync errors
            userDefaults.set(syncErrors, forKey: syncErrorsKey)
            
            // Save last sync time
            if let lastSync = lastSyncTime {
                userDefaults.set(lastSync, forKey: lastSyncKey)
            }
            
            userDefaults.synchronize()
            
        } catch {
            print("❌ OFFLINE: Failed to save to storage: \(error)")
        }
    }
    
    /// Loads data from UserDefaults
    private func loadFromStorage() {
        // Load pending completions
        if let completionsData = userDefaults.data(forKey: userDefaultsKey) {
            do {
                pendingCompletions = try JSONDecoder().decode([OfflineCompletion].self, from: completionsData)
                print("📥 OFFLINE: Loaded \(pendingCompletions.count) pending completions")
            } catch {
                print("❌ OFFLINE: Failed to load completions: \(error)")
                pendingCompletions = []
            }
        }
        
        // Load sync errors
        if let errors = userDefaults.array(forKey: syncErrorsKey) as? [String] {
            syncErrors = errors
        }
        
        // Load last sync time
        lastSyncTime = userDefaults.object(forKey: lastSyncKey) as? Date
    }
    
}

// MARK: - NetworkManager Extension

extension NetworkManager {
    
    /// Submits a game completion to the server
    func submitGameCompletion(
        phraseId: String,
        playerId: String,
        timeToComplete: Double,
        hintsUsed: Int,
        score: Int
    ) async -> Bool {
        guard isOnline else {
            print("❌ NETWORK: Cannot submit completion - offline")
            return false
        }
        
        // Use AppConfig directly instead of private baseURL
        guard let url = URL(string: "\(AppConfig.baseURL)/api/phrases/\(phraseId)/complete") else {
            print("❌ NETWORK: Invalid completion URL")
            return false
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let completionData = [
                "playerId": playerId,
                "timeToComplete": timeToComplete,
                "hintsUsed": hintsUsed,
                "score": score
            ] as [String: Any]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: completionData)
            
            // Use URLSession.shared instead of private urlSession
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                let success = httpResponse.statusCode == 200
                print(success ? "✅ NETWORK: Completion submitted" : "❌ NETWORK: Completion failed - status \(httpResponse.statusCode)")
                return success
            }
            
            return false
        } catch {
            print("❌ NETWORK: Error submitting completion: \(error)")
            return false
        }
    }
}