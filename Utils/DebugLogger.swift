//
//  DebugLogger.swift
//  Anagram Game
//
//  Created by Claude on 2025-07-29.
//

import Foundation

/// Centralized debug logging utility that handles all debug message sending
/// Eliminates duplicate sendDebugToServer functions across GameModel and PhysicsGameView
class DebugLogger {
    
    // MARK: - Shared Instance
    static let shared = DebugLogger()
    private init() {}
    
    // MARK: - Debug Logging
    
    /// Sends debug message to server for performance monitoring
    /// - Parameter message: Debug message to send
    func sendToServer(_ message: String) async {
        guard AppConfig.isPerformanceMonitoringEnabled else { return }
        guard let url = URL(string: "\(AppConfig.baseURL)/api/debug/log") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let debugData: [String: Any] = [
            "message": message,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "source": "iOS"
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: debugData)
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                print("✅ DEBUG_LOG_SENT: \(message)")
            } else {
                print("⚠️ DEBUG_LOG_FAILED: \(message)")
            }
        } catch {
            print("❌ DEBUG_LOG_ERROR: Failed to send debug message - \(error)")
        }
    }
    
    /// Sends debug message with context information
    /// - Parameters:
    ///   - message: Debug message to send
    ///   - context: Additional context information
    func sendWithContext(_ message: String, context: [String: Any] = [:]) async {
        let contextString = context.isEmpty ? "" : " | Context: \(context)"
        await sendToServer("\(message)\(contextString)")
    }
    
    /// Sends performance-related debug message
    /// - Parameters:
    ///   - event: Performance event name
    ///   - metrics: Performance metrics dictionary
    func sendPerformance(event: String, metrics: [String: Any]) async {
        let message = "PERFORMANCE_\(event.uppercased()): \(metrics)"
        await sendToServer(message)
    }
    
    /// Sends memory-related debug message
    /// - Parameters:
    ///   - operation: Memory operation description
    ///   - memoryMB: Memory usage in MB
    func sendMemory(operation: String, memoryMB: Double) async {
        let message = "MEMORY_\(operation.uppercased()): \(String(format: "%.1f", memoryMB))MB"
        await sendToServer(message)
    }
    
    /// Sends game state debug message
    /// - Parameters:
    ///   - state: Game state description
    ///   - details: Additional state details
    func sendGameState(_ state: String, details: String = "") async {
        let message = details.isEmpty ? "GAME_STATE: \(state)" : "GAME_STATE: \(state) - \(details)"
        await sendToServer(message)
    }
}