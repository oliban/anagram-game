//
//  NetworkModels.swift
//  Anagram Game
//
//  Created by Claude on 2025-07-29.
//  Extracted from NetworkManager.swift during refactoring
//

import Foundation

// MARK: - Network Error Types

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case serverOffline
    case connectionFailed
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .serverOffline: return "Server is offline"
        case .connectionFailed: return "Connection failed"
        case .invalidResponse: return "Invalid server response"
        }
    }
}

// MARK: - Registration Models

enum RegistrationResult {
    case success
    case nameConflict(suggestions: [String])
    case failure(message: String)
}

private struct RegistrationRequestBody: Encodable {
    let name: String
    let deviceId: String
}

// MARK: - Server Configuration Models  

struct ServerConfig: Codable {
    let performanceMonitoringEnabled: Bool
    let serverVersion: String
    let timestamp: String
}

// MARK: - Player Models

struct Player: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let lastSeen: Date
    let isActive: Bool
    let phrasesCompleted: Int
    
    private enum CodingKeys: String, CodingKey {
        case id, name, lastSeen, isActive, phrasesCompleted
    }
    
    // Manual initializer for creating Player instances in code
    init(id: String, name: String, lastSeen: Date, isActive: Bool, phrasesCompleted: Int) {
        self.id = id
        self.name = name
        self.lastSeen = lastSeen
        self.isActive = isActive
        self.phrasesCompleted = phrasesCompleted
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        phrasesCompleted = try container.decode(Int.self, forKey: .phrasesCompleted)
        
        // Handle date parsing
        let dateString = try container.decode(String.self, forKey: .lastSeen)
        let formatter = ISO8601DateFormatter()
        lastSeen = formatter.date(from: dateString) ?? Date()
    }
}

public struct PlayerStats: Codable {
    let dailyScore: Int
    let dailyRank: Int
    let weeklyScore: Int
    let weeklyRank: Int
    let totalScore: Int
    let totalRank: Int
    let totalPhrases: Int
    let skillTitle: String?
    let skillLevel: Int?
}

public struct LeaderboardEntry: Codable {
    let rank: Int
    let playerName: String
    let totalScore: Int
    let phrasesCompleted: Int
}

public struct LegendPlayer: Codable, Identifiable {
    public let id: String
    public let name: String
    public let totalScore: Int
    public let skillLevel: Int
    public let skillTitle: String
    public let phrasesCompleted: Int
}

struct LegendPlayersResponse: Codable {
    let players: [LegendPlayer]
    let minimumSkillLevel: Int
    let minimumSkillTitle: String
    let count: Int
}

// MARK: - Phrase Models

struct CustomPhrase: Codable, Identifiable, Equatable {
    let id: String
    let content: String
    let senderId: String
    let targetId: String?  // Made optional to handle null values for global phrases
    let createdAt: Date
    let isConsumed: Bool
    let senderName: String
    let language: String // Language code for LanguageTile feature
    let clue: String // Hint clue for level 3 hints
    let difficultyLevel: Int // Server-provided difficulty score
    let theme: String? // Theme for ThemeInformationTile feature
    
    private enum CodingKeys: String, CodingKey {
        case id, content, senderId, targetId, createdAt, isConsumed, senderName, language, clue
        case difficultyLevel, theme
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        senderId = try container.decode(String.self, forKey: .senderId)
        targetId = try container.decodeIfPresent(String.self, forKey: .targetId)  // Handle null values
        isConsumed = try container.decode(Bool.self, forKey: .isConsumed)
        senderName = try container.decodeIfPresent(String.self, forKey: .senderName) ?? "Unknown Player"
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en" // Default to English
        clue = try container.decodeIfPresent(String.self, forKey: .clue) ?? "" // Server sends "clue" field, default to empty if missing
        difficultyLevel = try container.decodeIfPresent(Int.self, forKey: .difficultyLevel) ?? 50 // Default to medium difficulty if missing
        theme = try container.decodeIfPresent(String.self, forKey: .theme) // Theme is optional
        
        // Handle date parsing - make optional since server might not include it
        if let dateString = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            let formatter = ISO8601DateFormatter()
            createdAt = formatter.date(from: dateString) ?? Date()
        } else {
            createdAt = Date() // Default to current date
        }
    }
}

struct CompletionResult: Codable {
    let success: Bool
    let completion: CompletionData
    let timestamp: String
    
    struct CompletionData: Codable {
        let finalScore: Int
        let hintsUsed: Int
        let completionTime: Int
    }
}

struct PhrasePreview: Codable {
    let success: Bool
    let phrase: PhraseData
    let timestamp: String
    
    struct PhraseData: Codable {
        let id: String
        let content: String
        let hint: String
        let difficultyLevel: Int
        let isGlobal: Bool
        let hintStatus: HintStatus
        let scorePreview: ScorePreview
    }
}

// MARK: - Hint System Models

struct HintStatus: Codable {
    let hintsUsed: [UsedHint]
    let nextHintLevel: Int?
    let hintsRemaining: Int
    let currentScore: Int
    let nextHintScore: Int?
    let canUseNextHint: Bool
    
    struct UsedHint: Codable {
        let level: Int
        let usedAt: Date
        
        init(level: Int, usedAt: Date) {
            self.level = level
            self.usedAt = usedAt
        }
        
        private enum CodingKeys: String, CodingKey {
            case level, usedAt
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            level = try container.decode(Int.self, forKey: .level)
            
            // Handle date parsing
            let dateString = try container.decode(String.self, forKey: .usedAt)
            let formatter = ISO8601DateFormatter()
            usedAt = formatter.date(from: dateString) ?? Date()
        }
    }
}

struct ScorePreview: Codable {
    let noHints: Int
    let level1: Int
    let level2: Int
    let level3: Int
}

struct HintResponse: Codable {
    let success: Bool
    let hint: HintData
    let scorePreview: ScorePreview
    let timestamp: String
    
    struct HintData: Codable {
        let level: Int
        let content: String
        let currentScore: Int
        let nextHintScore: Int?
        let hintsRemaining: Int
        let canUseNextHint: Bool
    }
}

// MARK: - Difficulty Analysis Models

public struct DifficultyAnalysis: Codable {
    let phrase: String
    let language: String
    let score: Double
    let difficulty: String
    let timestamp: String
}

// MARK: - Helper Extensions

extension DateFormatter {
    static let iso8601Full: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}