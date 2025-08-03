//
//  PhraseService.swift
//  Anagram Game
//
//  Created by Claude on 2025-07-29.
//  Handles phrase CRUD operations, hints, and completion logic
//

import Foundation

class PhraseService: PhraseServiceDelegate {
    @Published var currentPhrase: CustomPhrase?
    @Published var hintStatus: HintStatus?
    @Published var currentPhrasePreview: PhrasePreview.PhraseData?
    
    private let baseURL = AppConfig.baseURL
    private var urlSession: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 30.0
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - Phrase Management
    
    func fetchPhraseForPlayer(playerId: String) async throws -> PhrasePreview {
        guard let url = URL(string: "\(baseURL)/api/phrases/for/\(playerId)") else {
            throw NetworkError.invalidURL
        }
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ PHRASE: Failed to fetch phrase. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                throw NetworkError.serverOffline
            }
            
            let phrasePreview = try JSONDecoder().decode(PhrasePreview.self, from: data)
            
            await MainActor.run {
                self.currentPhrasePreview = phrasePreview.phrase
                self.hintStatus = phrasePreview.phrase.hintStatus
            }
            
            print("✅ PHRASE: Fetched phrase for player \(playerId)")
            return phrasePreview
        } catch {
            print("❌ PHRASE: Error fetching phrase: \(error)")
            throw NetworkError.serverOffline
        }
    }
    
    func fetchPhrasesForPlayer(playerId: String, level: Int? = nil) async throws -> [CustomPhrase] {
        // Build URL with optional level parameter
        var urlString = "\(baseURL)/api/phrases/for/\(playerId)"
        if let level = level {
            urlString += "?level=\(level)"
            print("🎯 PHRASE: Fetching phrases for player level \(level)")
        }
        
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ PHRASE: Failed to fetch phrases. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                throw NetworkError.serverOffline
            }
            
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let phrasesData = jsonResponse["phrases"] {
                let jsonData = try JSONSerialization.data(withJSONObject: phrasesData)
                let phrases = try JSONDecoder().decode([CustomPhrase].self, from: jsonData)
                print("🔍 PHRASE: Successfully decoded \(phrases.count) phrases")
                return phrases
            }
            
            throw NetworkError.invalidResponse
            
        } catch {
            print("❌ PHRASE: Error fetching phrases: \(error.localizedDescription)")
            throw NetworkError.connectionFailed
        }
    }
    
    func createCustomPhrase(content: String, playerId: String, targetId: String?, hint: String = "", isGlobal: Bool = false, language: String = "en") async throws -> CustomPhrase {
        guard let url = URL(string: "\(baseURL)/api/phrases/create") else {
            throw NetworkError.invalidURL
        }
        
        let requestBody = [
            "content": content,
            "senderId": playerId,
            "targetId": targetId as Any,
            "hint": hint,
            "isGlobal": isGlobal,
            "language": language
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
                print("❌ PHRASE: Failed to create custom phrase. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                throw NetworkError.serverOffline
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let phraseData = json["phrase"] as? [String: Any] {
                
                // Manually create CustomPhrase from dictionary
                let phrase = try parseCustomPhraseFromDictionary(phraseData)
                
                print("✅ PHRASE: Created custom phrase with ID: \(phrase.id)")
                return phrase
            }
            
            throw NetworkError.invalidResponse
            
        } catch {
            print("❌ PHRASE: Error creating custom phrase: \(error.localizedDescription)")
            throw NetworkError.connectionFailed
        }
    }
    
    // MARK: - Hint System
    
    func useHint(phraseId: String, playerId: String) async throws -> HintResponse {
        guard let url = URL(string: "\(baseURL)/api/phrases/\(phraseId)/hint") else {
            throw NetworkError.invalidURL
        }
        
        let requestBody = ["playerId": playerId]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ HINT: Failed to use hint. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                throw NetworkError.serverOffline
            }
            
            let hintResponse = try JSONDecoder().decode(HintResponse.self, from: data)
            
            print("✅ HINT: Used hint level \(hintResponse.hint.level) for phrase \(phraseId)")
            return hintResponse
            
        } catch {
            print("❌ HINT: Error using hint: \(error.localizedDescription)")
            throw NetworkError.connectionFailed
        }
    }
    
    // MARK: - Phrase Completion
    
    func completePhraseOnServer(phraseId: String, playerId: String, hintsUsed: Int, completionTime: Int, celebrationEmojis: [EmojiCatalogItem] = []) async throws -> CompletionResult {
        guard let url = URL(string: "\(baseURL)/api/phrases/\(phraseId)/complete") else {
            throw NetworkError.invalidURL
        }
        
        // Convert celebrationEmojis to JSON-serializable format
        let emojiData = celebrationEmojis.map { emoji in
            return [
                "id": emoji.id.uuidString,
                "emoji_character": emoji.emojiCharacter,
                "name": emoji.name,
                "rarity_tier": emoji.rarity.rawValue,
                "drop_rate_percentage": emoji.dropRatePercentage,
                "points_reward": emoji.pointsReward,
                "unicode_version": emoji.unicodeVersion ?? "",
                "is_active": emoji.isActive,
                "created_at": ISO8601DateFormatter().string(from: emoji.createdAt)
            ] as [String: Any]
        }
        
        let requestBody: [String: Any] = [
            "playerId": playerId,
            "hintsUsed": hintsUsed,
            "completionTime": completionTime,
            "celebrationEmojis": emojiData
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ COMPLETE: Failed to complete phrase. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                throw NetworkError.serverOffline
            }
            
            let completionResult = try JSONDecoder().decode(CompletionResult.self, from: data)
            
            print("✅ COMPLETE: Completed phrase \(phraseId) with score \(completionResult.completion.finalScore)")
            return completionResult
            
        } catch {
            print("❌ COMPLETE: Error completing phrase: \(error.localizedDescription)")
            throw NetworkError.connectionFailed
        }
    }
    
    // MARK: - Socket Event Handling
    
    func handleNewPhrase(data: [Any]) {
        guard let payload = data.first as? [String: Any] else {
            print("❌ SOCKET: No payload in data or not a dictionary")
            return
        }
        
        guard let phraseData = payload["phrase"] as? [String: Any] else {
            print("❌ SOCKET: No 'phrase' field in payload or not a dictionary")
            return
        }
        
        guard let senderName = payload["senderName"] as? String else {
            print("❌ SOCKET: No 'senderName' field in payload or not a string")
            return
        }
        
        do {
            // Add senderName to the phrase data for decoding
            var mutablePhraseData = phraseData
            mutablePhraseData["senderName"] = senderName
            
            let jsonData = try JSONSerialization.data(withJSONObject: mutablePhraseData)
            let decoder = JSONDecoder()
            let phrase = try decoder.decode(CustomPhrase.self, from: jsonData)
            
            DispatchQueue.main.async {
                // Update service state
                self.currentPhrase = phrase
                
                // Update NetworkManager compatibility properties for GameModel
                NetworkManager.shared.lastReceivedPhrase = phrase
                NetworkManager.shared.hasNewPhrase = true
                NetworkManager.shared.justReceivedPhrase = phrase
            }
            
            print("📨 SOCKET: Received new phrase: \(phrase.content)")
            print("🐛 SOCKET DEBUG: targetId = '\(phrase.targetId ?? "nil")', senderName = '\(phrase.senderName)'")
            
        } catch {
            print("❌ SOCKET: Failed to parse new phrase: \(error.localizedDescription)")
        }
    }
    
    func handlePhraseCompletionNotification(data: [Any]) {
        guard let notificationData = data.first as? [String: Any],
              let playerName = notificationData["playerName"] as? String,
              let phraseContent = notificationData["phrase"] as? String else {
            print("❌ SOCKET: Invalid completion notification data format")
            return
        }
        
        print("🎉 SOCKET: \(playerName) completed phrase: \(phraseContent)")
        
        // Post notification for UI to handle
        NotificationCenter.default.post(
            name: .phraseCompletedByOtherPlayer,
            object: nil,
            userInfo: ["playerName": playerName, "phrase": phraseContent]
        )
    }
    
    // MARK: - Helper Methods
    
    private func parseCustomPhraseFromDictionary(_ data: [String: Any]) throws -> CustomPhrase {
        guard let id = data["id"] as? String,
              let content = data["content"] as? String,
              let senderId = data["senderId"] as? String,
              let isConsumed = data["isConsumed"] as? Bool,
              let senderName = data["senderName"] as? String else {
            throw NetworkError.invalidResponse
        }
        
        let targetId = data["targetId"] as? String
        let language = data["language"] as? String ?? "en"
        
        // Handle date parsing
        let createdAt: Date
        if let createdAtString = data["createdAt"] as? String {
            let formatter = ISO8601DateFormatter()
            createdAt = formatter.date(from: createdAtString) ?? Date()
        } else {
            createdAt = Date()
        }
        
        // Create the phrase manually since we're parsing from dictionary
        let clue = data["clue"] as? String ?? "No clue available"
        
        return CustomPhrase(
            id: id,
            content: content,
            senderId: senderId,
            targetId: targetId,
            createdAt: createdAt,
            isConsumed: isConsumed,
            senderName: senderName,
            language: language,
            clue: clue
        )
    }
}

// MARK: - CustomPhrase Initializer Extension

extension CustomPhrase {
    init(id: String, content: String, senderId: String, targetId: String?, createdAt: Date, isConsumed: Bool, senderName: String, language: String, clue: String, difficultyLevel: Int = 50, theme: String? = nil, celebrationEmojis: [EmojiCatalogItem] = []) {
        self.id = id
        self.content = content
        self.senderId = senderId
        self.targetId = targetId
        self.createdAt = createdAt
        self.isConsumed = isConsumed
        self.senderName = senderName
        self.language = language
        self.clue = clue
        self.difficultyLevel = difficultyLevel
        self.theme = theme
        self.celebrationEmojis = celebrationEmojis
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let phraseCompletedByOtherPlayer = Notification.Name("phraseCompletedByOtherPlayer")
}