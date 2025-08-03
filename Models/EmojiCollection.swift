import Foundation

// MARK: - Emoji Rarity System

enum EmojiRarity: String, CaseIterable, Codable {
    case legendary = "legendary"
    case mythic = "mythic"
    case epic = "epic"
    case rare = "rare"
    case uncommon = "uncommon"
    case common = "common"
    
    var displayName: String {
        switch self {
        case .legendary: return "Legendary"
        case .mythic: return "Mythic"
        case .epic: return "Epic"
        case .rare: return "Rare"
        case .uncommon: return "Uncommon"
        case .common: return "Common"
        }
    }
    
    var color: String {
        switch self {
        case .legendary: return "#FFD700" // Gold
        case .mythic: return "#9B59B6"     // Purple
        case .epic: return "#3498DB"       // Blue
        case .rare: return "#E74C3C"       // Red
        case .uncommon: return "#F39C12"   // Orange
        case .common: return "#95A5A6"     // Gray
        }
    }
    
    var dropRateRange: String {
        switch self {
        case .legendary: return "0.1% - 0.5%"
        case .mythic: return "0.6% - 2%"
        case .epic: return "2.1% - 5%"
        case .rare: return "5.1% - 15%"
        case .uncommon: return "15.1% - 35%"
        case .common: return "35.1% - 100%"
        }
    }
    
    var triggersGlobalDrop: Bool {
        return self == .legendary || self == .mythic || self == .epic
    }
}

// MARK: - Emoji Catalog Models

struct EmojiCatalogItem: Codable, Identifiable, Hashable {
    let id: UUID
    let emojiCharacter: String
    let name: String
    let rarity: EmojiRarity
    let dropRatePercentage: Double
    let pointsReward: Int
    let unicodeVersion: String?
    let isActive: Bool
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case emojiCharacter = "emoji_character"
        case name
        case rarity = "rarity_tier"
        case dropRatePercentage = "drop_rate_percentage"
        case pointsReward = "points_reward"
        case unicodeVersion = "unicode_version"
        case isActive = "is_active"
        case createdAt = "created_at"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        emojiCharacter = try container.decode(String.self, forKey: .emojiCharacter)
        name = try container.decode(String.self, forKey: .name)
        rarity = try container.decode(EmojiRarity.self, forKey: .rarity)
        pointsReward = try container.decode(Int.self, forKey: .pointsReward)
        unicodeVersion = try container.decodeIfPresent(String.self, forKey: .unicodeVersion)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        
        // Handle created_at as ISO string
        if let createdAtString = try? container.decode(String.self, forKey: .createdAt) {
            let formatter = ISO8601DateFormatter()
            createdAt = formatter.date(from: createdAtString) ?? Date()
        } else {
            createdAt = try container.decode(Date.self, forKey: .createdAt)
        }
        
        // Handle drop_rate_percentage as either String or Double
        if let dropRateString = try? container.decode(String.self, forKey: .dropRatePercentage) {
            dropRatePercentage = Double(dropRateString) ?? 0.0
        } else {
            dropRatePercentage = try container.decode(Double.self, forKey: .dropRatePercentage)
        }
    }
}

struct PlayerEmojiCollection: Codable, Identifiable {
    let id: UUID
    let playerId: UUID
    let emojiId: UUID
    let discoveredAt: Date
    let isFirstGlobalDiscovery: Bool
    
    // Populated from joins
    var emoji: EmojiCatalogItem?
    
    enum CodingKeys: String, CodingKey {
        case id
        case playerId = "player_id"
        case emojiId = "emoji_id"
        case discoveredAt = "discovered_at"
        case isFirstGlobalDiscovery = "is_first_global_discovery"
    }
}

struct EmojiGlobalDiscovery: Codable, Identifiable {
    let id: UUID
    let emojiId: UUID
    let firstDiscovererId: UUID?
    let discoveredAt: Date
    
    // Populated from joins
    var emoji: EmojiCatalogItem?
    var firstDiscoverer: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case emojiId = "emoji_id"
        case firstDiscovererId = "first_discoverer_id"
        case discoveredAt = "discovered_at"
    }
}

// MARK: - Collection Summary Models

struct EmojiCollectionSummary: Codable {
    let totalEmojis: Int
    let collectedEmojis: Int
    let totalPoints: Int
    let collectionsByRarity: [EmojiRarity: Int]
    let recentDiscoveries: [PlayerEmojiCollection]
    let globalFirstDiscoveries: Int
    
    var completionPercentage: Double {
        guard totalEmojis > 0 else { return 0.0 }
        return Double(collectedEmojis) / Double(totalEmojis) * 100.0
    }
}

struct EmojiDropResult: Codable {
    let droppedEmojis: [EmojiCatalogItem]
    let newDiscoveries: [EmojiCatalogItem]
    let pointsEarned: Int
    let triggeredGlobalDrop: Bool
    let globalDropMessage: String?
}

// MARK: - API Request/Response Models

struct EmojiDropRequest: Codable {
    let playerId: UUID
    let numberOfDrops: Int // 1-3 as currently implemented
}

struct EmojiCollectionRequest: Codable {
    let playerId: UUID
    let rarity: EmojiRarity?
    let limit: Int?
    let offset: Int?
}

struct GlobalEmojiStatsResponse: Codable {
    let topRarestEmojis: [EmojiGlobalDiscovery]
    let recentGlobalDiscoveries: [EmojiGlobalDiscovery]
    let totalActiveEmojis: Int
    let totalDiscoveries: Int
}

// MARK: - Collection Display Models

struct EmojiCollectionSection: Identifiable {
    let id = UUID()
    let rarity: EmojiRarity
    let emojis: [PlayerEmojiCollection]
    let totalInRarity: Int
    
    var completionPercentage: Double {
        guard totalInRarity > 0 else { return 0.0 }
        return Double(emojis.count) / Double(totalInRarity) * 100.0
    }
}

// MARK: - Local Storage Models

struct LocalEmojiProgress: Codable {
    let playerId: UUID
    let lastSyncDate: Date
    let cachedCollections: [PlayerEmojiCollection]
    let cachedSummary: EmojiCollectionSummary
}