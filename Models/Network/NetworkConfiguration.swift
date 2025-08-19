//
//  NetworkConfiguration.swift
//  Anagram Game
//
//  Created by Claude on 2025-07-29.
//  Extracted from NetworkManager.swift during refactoring
//

import Foundation

// MARK: - Configuration Models

struct SharedAppConfig: Codable {
    let services: ServiceConfig
    let development: EnvironmentConfig
    let staging: EnvironmentConfig
    let production: EnvironmentConfig
}

struct ServiceConfig: Codable {
    let gameServer: ServiceInfo
    let webDashboard: ServiceInfo
    let database: ServiceInfo
}

struct ServiceInfo: Codable {
    let port: Int
    let host: String
}

struct EnvironmentConfig: Codable {
    let host: String
    let description: String
}

// MARK: - Configuration Loader

private func loadSharedConfig() -> SharedAppConfig {
    // Dynamic configuration based on build environment
    // No static JSON file needed - configuration is determined at build time
    
    #if DEBUG
    let _ = true  // Development mode marker
    #else
    let _ = false // Production mode marker  
    #endif
    
    // Environment-aware configuration
    // Note: host values here are not used - actual hosts come from developmentConfig/productionConfig
    let gameServerConfig = ServiceInfo(port: 3000, host: "localhost")
    let webDashboardConfig = ServiceInfo(port: 3001, host: "localhost")
    let databaseConfig = ServiceInfo(port: 5432, host: "localhost")
    
    let services = ServiceConfig(
        gameServer: gameServerConfig,
        webDashboard: webDashboardConfig,
        database: databaseConfig
    )
    
    // Environment configurations
    let developmentConfig = EnvironmentConfig(host: "192.168.1.188", description: "Local Development Server")
    let stagingConfig = EnvironmentConfig(host: "bras-voluntary-survivor-presidential.trycloudflare.com", description: "Pi Staging Server (Cloudflare tunnel)")
    let productionConfig = EnvironmentConfig(host: "anagram-staging-alb-1354034851.eu-west-1.elb.amazonaws.com", description: "AWS Production Server")
    
    let config = SharedAppConfig(
        services: services,
        development: developmentConfig,
        staging: stagingConfig,
        production: productionConfig
    )
    
    #if DEBUG
    print("✅ CONFIG: Generated dynamic configuration for development")
    #else
    print("✅ CONFIG: Generated dynamic configuration for production")
    #endif
    return config
}

// MARK: - App Configuration

struct AppConfig {
    private static let sharedConfig = loadSharedConfig()
    
    // Cache detected environment for session
    private static var detectedEnvironment: String?
    private static var detectionInProgress = false
    
    // Environment detection - automatically detects best server
    private static var currentEnvironment: String {
        get async {
            // Return cached result if available
            if let cached = detectedEnvironment {
                return cached
            }
            
            // Prevent multiple concurrent detections
            if detectionInProgress {
                // Wait briefly and return cached result or fallback
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                return detectedEnvironment ?? "staging"
            }
            
            detectionInProgress = true
            defer { detectionInProgress = false }
            
            #if DEBUG
            // In DEBUG builds, auto-detect best server
            let detected = await detectBestEnvironment()
            #else
            // Production builds always use staging
            let detected = "staging"
            #endif
            
            detectedEnvironment = detected
            print("🔧 CONFIG: Using \(detected.uppercased()) environment")
            return detected
        }
    }
    
    // Smart server detection
    private static func detectBestEnvironment() async -> String {
        print("🔍 AUTO-DETECT: Testing server connectivity...")
        
        // Test servers in priority order: staging -> local -> fallback
        let servers = [
            ("staging", await getCurrentStagingURL()),
            ("local", "http://192.168.1.188:3000")
        ]
        
        for (env, url) in servers {
            print("🔍 AUTO-DETECT: Testing \(env) at \(url)")
            if await isServerReachable(url) {
                print("✅ AUTO-DETECT: Using \(env) environment - server is healthy")
                return env
            }
        }
        
        print("⚠️ AUTO-DETECT: No servers reachable, defaulting to staging")
        return "staging" // Always fallback to staging
    }
    
    // Test if server is reachable and healthy
    private static func isServerReachable(_ baseURL: String, timeout: TimeInterval = 3.0) async -> Bool {
        do {
            guard let url = URL(string: "\(baseURL)/api/status") else { return false }
            
            var request = URLRequest(url: url, timeoutInterval: timeout)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check for valid HTTP response
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }
            
            // Verify server responds with expected status
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String,
               status == "healthy" {
                return true
            }
            
        } catch {
            // Network error, timeout, etc.
        }
        return false
    }
    
    // Get current staging server URL (tries multiple methods)
    private static func getCurrentStagingURL() async -> String {
        // Method 1: Try to get tunnel URL from Pi directly (if we add this endpoint)
        if let tunnelURL = await fetchTunnelFromPi() {
            return "https://\(tunnelURL)"
        }
        
        // Method 2: Use the current hardcoded tunnel URL
        let currentTunnelURL = "https://\(sharedConfig.staging.host)"
        
        // Method 3: If tunnel fails, try Pi local IP as last resort
        return currentTunnelURL
    }
    
    // Optional: Fetch current tunnel URL from Pi (requires endpoint on Pi)
    private static func fetchTunnelFromPi() async -> String? {
        do {
            // Pi could expose current tunnel URL via simple HTTP endpoint
            guard let url = URL(string: "http://192.168.1.222:8080/current-tunnel") else { return nil }
            
            let request = URLRequest(url: url, timeoutInterval: 2.0)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            
            let tunnelHost = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return tunnelHost?.isEmpty == false ? tunnelHost : nil
            
        } catch {
            // Pi might not be reachable or endpoint doesn't exist yet
            return nil
        }
    }
    
    // Get current environment configuration
    private static func getEnvironmentConfig(_ environment: String) -> EnvironmentConfig {
        switch environment {
        case "local":
            return sharedConfig.development
        case "staging":
            return sharedConfig.staging
        case "aws":
            return sharedConfig.production
        default:
            print("⚠️ CONFIG: Unknown environment '\(environment)', falling back to local")
            return sharedConfig.development
        }
    }
    
    // Server Configuration - dynamically loaded from shared config
    static var serverPort: String { 
        return String(sharedConfig.services.gameServer.port)
    }
    
    // Cached URL for synchronous access
    private static var cachedBaseURL: String?
    
    // Async baseURL with smart detection
    static func getBaseURL() async -> String {
        let environment = await currentEnvironment
        let config = getEnvironmentConfig(environment)
        let host = config.host
        
        // Determine URL format based on host type and environment
        let url: String
        if host.contains("amazonaws.com") {
            // AWS ELB - no port needed
            url = "http://\(host)"
        } else if host.contains("trycloudflare.com") {
            // Cloudflare tunnel - HTTPS, no port needed
            url = "https://\(host)"
        } else if host == "STAGING_PLACEHOLDER" {
            // Staging placeholder - this means tunnel URL wasn't set
            url = "http://192.168.1.222:3000"  // Fallback to Pi local IP
            print("⚠️ CONFIG: Staging tunnel URL not set, falling back to Pi local IP")
        } else {
            // Local or Pi staging server - needs port
            let port = sharedConfig.services.gameServer.port
            url = "http://\(host):\(port)"
        }
        
        print("🔧 CONFIG: Using \(environment.uppercased()) server: \(url)")
        print("🔧 CONFIG: Environment: \(config.description)")
        
        // Cache for synchronous access
        cachedBaseURL = url
        return url
    }
    
    // Synchronous baseURL (uses cached value or staging fallback)
    static var baseURL: String {
        // Return cached URL if available
        if let cached = cachedBaseURL {
            return cached
        }
        
        // Fallback to staging URL for immediate synchronous access
        let stagingConfig = sharedConfig.staging
        let fallbackURL = "https://\(stagingConfig.host)"
        
        print("🔧 CONFIG: Using synchronous staging fallback: \(fallbackURL)")
        cachedBaseURL = fallbackURL
        
        // Trigger async detection in background for next time
        Task {
            _ = await getBaseURL()
        }
        
        return fallbackURL
    }
    
    // Contribution system URLs - consolidated into game-server
    static var contributionBaseURL: String {
        // All contribution requests now go through game-server (port 3000)
        return baseURL
    }
    
    static var contributionAPIURL: String {
        // Contribution system is now integrated into game-server
        return "\(baseURL)/api/contribution/request"
    }
    
    // Async versions for when you want smart detection
    static func getContributionBaseURL() async -> String {
        return await getBaseURL()
    }
    
    static func getContributionAPIURL() async -> String {
        return "\(await getBaseURL())/api/contribution/request"
    }
    
    // Initialize smart detection (call this early in app lifecycle)
    static func initializeSmartDetection() {
        Task {
            print("🚀 CONFIG: Initializing smart server detection...")
            _ = await getBaseURL()
            print("🚀 CONFIG: Smart detection complete")
        }
    }
    
    // Force re-detection (useful when network conditions change)
    static func refreshServerDetection() {
        detectedEnvironment = nil
        cachedBaseURL = nil
        initializeSmartDetection()
    }
    
    // Timing Configuration
    static let connectionRetryDelay: UInt64 = 2_000_000_000  // 2 seconds in nanoseconds
    static let registrationStabilizationDelay: UInt64 = 1_000_000_000  // 1 second in nanoseconds
    static let playerListRefreshInterval: TimeInterval = 15.0  // 15 seconds
    static let notificationDisplayDuration: TimeInterval = 3.0  // 3 seconds
    
    // Performance Monitoring Configuration - Disabled by default to reduce API calls
    static var isPerformanceMonitoringEnabled: Bool = {
        // Default to disabled for cleaner startup behavior
        // Can be enabled later if needed for debugging
        return false
    }()
    
    // Update performance monitoring based on server configuration
    static func updatePerformanceMonitoringFromServer(_ enabled: Bool) {
        isPerformanceMonitoringEnabled = enabled
        print("⚙️ CONFIG: Performance monitoring \(enabled ? "enabled" : "disabled") by server")
        
        // Notify observers that configuration has changed
        NotificationCenter.default.post(name: .performanceMonitoringConfigChanged, object: enabled)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let performanceMonitoringConfigChanged = Notification.Name("performanceMonitoringConfigChanged")
}
