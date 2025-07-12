import Foundation
import UIKit

class DeviceManager {
    static let shared = DeviceManager()
    private init() {}
    
    private let deviceIdKey = "anagram_game_device_id"
    
    /// Get or generate a unique device identifier
    func getDeviceId() -> String {
        // Check if we already have a device ID stored
        if let existingId = UserDefaults.standard.string(forKey: deviceIdKey), !existingId.isEmpty {
            return existingId
        }
        
        // Generate a new unique device ID
        let newDeviceId = generateUniqueDeviceId()
        
        // Store it for future use
        UserDefaults.standard.set(newDeviceId, forKey: deviceIdKey)
        
        print("📱 DEVICE: Generated new device ID: \(newDeviceId)")
        return newDeviceId
    }
    
    /// Generate a unique device identifier
    private func generateUniqueDeviceId() -> String {
        // Combine multiple sources to create a unique identifier
        let uuid = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)
        
        // Create a short, readable device ID
        let shortId = "\(timestamp)_\(uuid.prefix(8))"
        return shortId
    }
    
    /// Reset device ID (for testing purposes)
    func resetDeviceId() {
        UserDefaults.standard.removeObject(forKey: deviceIdKey)
        print("📱 DEVICE: Device ID reset")
    }
    
    /// Get device info for debugging
    func getDeviceInfo() -> [String: String] {
        return [
            "deviceId": getDeviceId(),
            "model": UIDevice.current.model,
            "systemVersion": UIDevice.current.systemVersion,
            "name": UIDevice.current.name
        ]
    }
}