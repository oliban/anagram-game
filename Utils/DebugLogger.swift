//
//  DebugLogger.swift
//  Anagram Game
//
//  Created by Claude on 2025-07-29.
//

import Foundation
import UIKit

/// Centralized debug logging utility that handles all debug message sending
/// Eliminates duplicate sendDebugToServer functions across GameModel and PhysicsGameView
class DebugLogger {
    
    // MARK: - Shared Instance
    static let shared = DebugLogger()
    
    // MARK: - File Logging
    private let logURL: URL
    private let dateFormatter: DateFormatter
    private let maxFileSize: Int = 5 * 1024 * 1024 // 5MB
    
    private init() {
        // Setup file logging - use shared location visible in Simulator
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        // Include device name in filename to distinguish logs from different simulators
        let deviceName = UIDevice.current.name.replacingOccurrences(of: " ", with: "-")
        self.logURL = documentsPath.appendingPathComponent("anagram-debug-\(deviceName).log")
        
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        // Print the log file path so we can find it
        print("📂 DebugLogger: Log file at \(logURL.path)")
        
        // Create initial log entry
        fileLog("🚀 DebugLogger initialized - Session started")
        fileLog("📱 App bundle: \(Bundle.main.bundleIdentifier ?? "unknown")")
        fileLog("📱 iOS Version: \(UIDevice.current.systemVersion)")
        fileLog("📱 Device: \(UIDevice.current.model)")
    }
    
    // MARK: - Debug Logging
    
    /// Sends debug message to server for performance monitoring
    /// - Parameter message: Debug message to send
    func sendToServer(_ message: String) async {
        // Respect performance monitoring setting to reduce API calls
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
        // Skip performance monitoring to reduce log noise
        return
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
    
    // MARK: - File Logging Methods
    
    /// Logs a message to the file with timestamp
    func fileLog(_ message: String, category: String = "General") {
        let timestamp = dateFormatter.string(from: Date())
        let logEntry = "[\(timestamp)] [\(category)] \(message)\n"
        
        // Also print to console for Xcode debugging
        print("🗂️ \(logEntry.trimmingCharacters(in: .whitespacesAndNewlines))")
        
        // Write to file
        writeToFile(logEntry)
    }
    
    private func writeToFile(_ logEntry: String) {
        guard let data = logEntry.data(using: .utf8) else { return }
        
        // Check if file exists
        if FileManager.default.fileExists(atPath: logURL.path) {
            // Check file size and rotate if needed
            if let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path),
               let fileSize = attributes[.size] as? Int,
               fileSize > maxFileSize {
                rotateLogFile()
            }
            
            // Append to existing file
            if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            // Create new file
            try? data.write(to: logURL)
        }
    }
    
    private func rotateLogFile() {
        let oldLogURL = logURL.appendingPathExtension("old")
        
        // Remove old backup if it exists
        try? FileManager.default.removeItem(at: oldLogURL)
        
        // Move current log to backup
        try? FileManager.default.moveItem(at: logURL, to: oldLogURL)
        
        fileLog("📄 Log file rotated - Previous log saved as .old")
    }
    
    // Convenience methods for different log levels
    func ui(_ message: String) {
        fileLog("🎨 \(message)", category: "UI")
    }
    
    func network(_ message: String) {
        fileLog("🌐 \(message)", category: "NETWORK")
    }
    
    func info(_ message: String) {
        fileLog("ℹ️ \(message)", category: "INFO")
    }
    
    func error(_ message: String) {
        fileLog("❌ \(message)", category: "ERROR")
    }
    
    func game(_ message: String) {
        fileLog("🎮 \(message)", category: "GAME")
    }
}