import Foundation

@Observable
class EmojiCollectionService {
    static let shared = EmojiCollectionService()
    private init() {}
    
    // MARK: - Properties
    
    private let networkManager = NetworkManager.shared
    
    // Current player's collection state
    var currentCollection: [PlayerEmojiCollection] = []
    var collectionSummary: EmojiCollectionSummary?
    var isLoading = false
    var errorMessage: String?
    
    // Global state
    var globalStats: GlobalEmojiStatsResponse?
    var pendingGlobalDrops: [EmojiCatalogItem] = []
    
    // MARK: - Public API
    
    /// Process emoji drops after completing a phrase
    func processEmojiDrop(for playerId: UUID, numberOfDrops: Int = Int.random(in: 1...2)) async throws -> EmojiDropResult {
        DebugLogger.shared.game("🎲 Processing emoji drop for player \(playerId) - \(numberOfDrops) drops")
        isLoading = true
        defer { isLoading = false }
        
        let request = EmojiDropRequest(playerId: playerId, numberOfDrops: numberOfDrops)
        
        let urlString = "\(AppConfig.baseURL)/api/emoji/drop"
        DebugLogger.shared.network("🎯 Emoji drop URL: \(urlString)")
        print("🎯 DEBUG: Emoji drop URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.invalidResponse
        }
        
        let result = try JSONDecoder().decode(EmojiDropResult.self, from: data)
        
        // Update local collection if we got new discoveries
        if !result.newDiscoveries.isEmpty {
            await refreshCollection(for: playerId)
            DebugLogger.shared.game("🆕 New emoji discoveries: \(result.newDiscoveries.map(\.emojiCharacter))")
        }
        
        // Handle global drops
        if result.triggeredGlobalDrop {
            await handleGlobalDrop(result: result)
        }
        
        DebugLogger.shared.game("✨ Emoji drop complete - \(result.pointsEarned) points earned")
        return result
    }
    
    /// Get player's full emoji collection
    func getPlayerCollection(playerId: UUID, rarity: EmojiRarity? = nil) async throws -> [PlayerEmojiCollection] {
        DebugLogger.shared.network("📚 Fetching emoji collection for player \(playerId)")
        
        var urlComponents = URLComponents(string: "\(AppConfig.baseURL)/api/emoji/collection/\(playerId)")!
        
        var queryItems: [URLQueryItem] = []
        if let rarity = rarity {
            queryItems.append(URLQueryItem(name: "rarity", value: rarity.rawValue))
        }
        urlComponents.queryItems = queryItems.isEmpty ? nil : queryItems
        
        guard let url = urlComponents.url else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let collections = try JSONDecoder().decode([PlayerEmojiCollection].self, from: data)
        
        // Update local cache
        if rarity == nil {
            currentCollection = collections
        }
        
        return collections
    }
    
    /// Get collection summary with statistics
    func getCollectionSummary(for playerId: UUID) async throws -> EmojiCollectionSummary {
        DebugLogger.shared.network("📊 Fetching collection summary for player \(playerId)")
        
        guard let url = URL(string: "\(AppConfig.baseURL)/api/emoji/collection/\(playerId)/summary") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let summary = try JSONDecoder().decode(EmojiCollectionSummary.self, from: data)
        
        collectionSummary = summary
        return summary
    }
    
    /// Get global emoji statistics (for Legends page)
    func getGlobalStats() async throws -> GlobalEmojiStatsResponse {
        DebugLogger.shared.network("🌍 Fetching global emoji statistics")
        
        guard let url = URL(string: "\(AppConfig.baseURL)/api/emoji/global/stats") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let stats = try JSONDecoder().decode(GlobalEmojiStatsResponse.self, from: data)
        
        globalStats = stats
        return stats
    }
    
    /// Get organized collection by rarity for display
    func getOrganizedCollection(for playerId: UUID) async throws -> [EmojiCollectionSection] {
        let collections = try await getPlayerCollection(playerId: playerId)
        let summary = try await getCollectionSummary(for: playerId)
        
        var sections: [EmojiCollectionSection] = []
        
        for rarity in EmojiRarity.allCases {
            let rarityEmojis = collections.filter { collection in
                collection.emoji?.rarity == rarity
            }
            
            let totalInRarity = summary.collectionsByRarity[rarity] ?? 0
            
            sections.append(EmojiCollectionSection(
                rarity: rarity,
                emojis: rarityEmojis,
                totalInRarity: totalInRarity
            ))
        }
        
        return sections
    }
    
    // MARK: - Private Methods
    
    private func refreshCollection(for playerId: UUID) async {
        do {
            _ = try await getPlayerCollection(playerId: playerId)
            _ = try await getCollectionSummary(for: playerId)
        } catch {
            DebugLogger.shared.error("❌ Failed to refresh collection: \(error)")
            errorMessage = "Failed to refresh collection"
        }
    }
    
    private func handleGlobalDrop(result: EmojiDropResult) async {
        DebugLogger.shared.game("🌍 Global drop triggered! Message: \(result.globalDropMessage ?? "")")
        
        // Add to pending global drops for UI to display
        pendingGlobalDrops.append(contentsOf: result.newDiscoveries.filter { $0.rarity.triggersGlobalDrop })
        
        // Notify other systems about global drop
        NotificationCenter.default.post(
            name: .emojiGlobalDropTriggered,
            object: result.globalDropMessage
        )
    }
    
    /// Clear pending global drops (called after UI displays them)
    func clearPendingGlobalDrops() {
        pendingGlobalDrops.removeAll()
    }
    
    /// Check if an emoji triggers global drops
    func triggersGlobalDrop(rarity: EmojiRarity) -> Bool {
        return rarity.triggersGlobalDrop
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let emojiGlobalDropTriggered = Notification.Name("emojiGlobalDropTriggered")
}

// NetworkError is already defined in NetworkModels.swift