import Foundation
import UIKit
import os.log

/// Performance monitoring system for baseline measurements and optimization tracking
class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    
    // MARK: - Measurement Storage
    private var measurements: [String: Any] = [:]
    private var fpsReadings: [Double] = []
    private var memoryReadings: [Double] = []
    private var gameResetTimes: [TimeInterval] = []
    
    // MARK: - FPS Tracking
    private var displayLink: CADisplayLink?
    private var frameCount: Int = 0
    private var lastTimestamp: CFTimeInterval = 0
    private var currentFPS: Double = 0
    
    // MARK: - Memory Tracking
    private var initialMemoryUsage: Double = 0
    private var peakMemoryUsage: Double = 0
    
    // MARK: - Game Reset Timing
    private var gameResetStartTime: CFTimeInterval = 0
    
    // MARK: - Logging
    private let logger = Logger(subsystem: "com.fredrik.anagramgame", category: "Performance")
    
    private init() {
        recordInitialMemory()
        startFPSMonitoring()
    }
    
    deinit {
        stopFPSMonitoring()
    }
    
    // MARK: - FPS Monitoring
    
    func startFPSMonitoring() {
        guard displayLink == nil else { return }
        
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkDidFire))
        displayLink?.add(to: .main, forMode: .common)
        
        logger.info("🎯 Started FPS monitoring")
    }
    
    func stopFPSMonitoring() {
        displayLink?.invalidate()
        displayLink = nil
        logger.info("⏹️ Stopped FPS monitoring")
    }
    
    @objc private func displayLinkDidFire(_ displayLink: CADisplayLink) {
        frameCount += 1
        
        if lastTimestamp == 0 {
            lastTimestamp = displayLink.timestamp
            return
        }
        
        let elapsed = displayLink.timestamp - lastTimestamp
        
        // Calculate FPS every second
        if elapsed >= 1.0 {
            currentFPS = Double(frameCount) / elapsed
            fpsReadings.append(currentFPS)
            
            // Keep only last 60 seconds of readings
            if fpsReadings.count > 60 {
                fpsReadings.removeFirst()
            }
            
            frameCount = 0
            lastTimestamp = displayLink.timestamp
            
            // Log significant FPS drops
            if currentFPS < 30 {
                logger.warning("⚠️ Low FPS detected: \(String(format: "%.1f", currentFPS)) fps")
            }
        }
    }
    
    // MARK: - Memory Monitoring
    
    private func recordInitialMemory() {
        initialMemoryUsage = getCurrentMemoryUsage()
        peakMemoryUsage = initialMemoryUsage
        logger.info("📊 Initial memory usage: \(String(format: "%.1f", initialMemoryUsage)) MB")
    }
    
    func recordCurrentMemory(context: String = "") {
        let currentMemory = getCurrentMemoryUsage()
        memoryReadings.append(currentMemory)
        
        if currentMemory > peakMemoryUsage {
            peakMemoryUsage = currentMemory
        }
        
        let contextStr = context.isEmpty ? "" : " (\(context))"
        logger.info("💾 Memory usage\(contextStr): \(String(format: "%.1f", currentMemory)) MB")
    }
    
    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return 0
        }
        
        return Double(info.resident_size) / 1024.0 / 1024.0 // Convert to MB
    }
    
    // MARK: - Game Reset Timing
    
    func startGameResetTimer() {
        gameResetStartTime = CACurrentMediaTime()
        logger.info("⏱️ Game reset started")
    }
    
    func endGameResetTimer() {
        guard gameResetStartTime > 0 else { return }
        
        let resetTime = CACurrentMediaTime() - gameResetStartTime
        gameResetTimes.append(resetTime)
        gameResetStartTime = 0
        
        logger.info("✅ Game reset completed in \(String(format: "%.3f", resetTime)) seconds")
        
        // Record memory after reset
        recordCurrentMemory(context: "after game reset")
    }
    
    // MARK: - Performance Snapshots
    
    func recordPerformanceSnapshot(label: String) {
        let snapshot: [String: Any] = [
            "timestamp": Date(),
            "label": label,
            "currentFPS": currentFPS,
            "averageFPS": fpsReadings.isEmpty ? 0 : fpsReadings.reduce(0, +) / Double(fpsReadings.count),
            "minFPS": fpsReadings.min() ?? 0,
            "maxFPS": fpsReadings.max() ?? 0,
            "currentMemory": getCurrentMemoryUsage(),
            "peakMemory": peakMemoryUsage,
            "memoryGrowth": getCurrentMemoryUsage() - initialMemoryUsage,
            "averageResetTime": gameResetTimes.isEmpty ? 0 : gameResetTimes.reduce(0, +) / Double(gameResetTimes.count),
            "totalResets": gameResetTimes.count
        ]
        
        measurements[label] = snapshot
        
        logger.info("📸 Performance snapshot '\(label)': FPS=\(String(format: "%.1f", currentFPS)), Memory=\(String(format: "%.1f", getCurrentMemoryUsage()))MB")
    }
    
    // MARK: - Automatic Testing Scenarios
    
    func startAutomaticBaselineTesting() {
        logger.info("🧪 Starting automatic baseline testing")
        
        recordPerformanceSnapshot(label: "baseline_start")
        
        // Schedule periodic measurements
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] timer in
            self?.recordCurrentMemory(context: "periodic check")
            
            // Stop after 5 minutes of monitoring
            if timer.fireDate.timeIntervalSinceNow < -300 {
                timer.invalidate()
                self?.finishBaselineTesting()
            }
        }
    }
    
    private func finishBaselineTesting() {
        recordPerformanceSnapshot(label: "baseline_end")
        generateBaselineReport()
    }
    
    // MARK: - Report Generation
    
    func generateBaselineReport() {
        let report = generatePerformanceReport()
        
        // Write to file
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let reportURL = documentsPath.appendingPathComponent("baseline_performance_report.txt")
        
        do {
            try report.write(to: reportURL, atomically: true, encoding: .utf8)
            logger.info("📄 Baseline report saved to: \(reportURL.path)")
        } catch {
            logger.error("❌ Failed to save baseline report: \(error)")
        }
        
        // Also log to console
        print("\n" + "="*50)
        print("📊 BASELINE PERFORMANCE REPORT")
        print("="*50)
        print(report)
        print("="*50 + "\n")
    }
    
    private func generatePerformanceReport() -> String {
        let deviceModel = UIDevice.current.model
        let systemVersion = UIDevice.current.systemVersion
        let timestamp = DateFormatter.iso8601WithFractionalSeconds.string(from: Date())
        
        var report = """
        ANAGRAM GAME - BASELINE PERFORMANCE REPORT
        Generated: \(timestamp)
        Device: \(deviceModel) (iOS \(systemVersion))
        Git Branch: refactor/tile-optimization-and-cleanup
        Git Tag: stable-before-phase-1a
        
        PERFORMANCE METRICS:
        """
        
        // FPS Analysis
        if !fpsReadings.isEmpty {
            let avgFPS = fpsReadings.reduce(0, +) / Double(fpsReadings.count)
            let minFPS = fpsReadings.min() ?? 0
            let maxFPS = fpsReadings.max() ?? 0
            
            report += """
            
            FPS ANALYSIS:
            - Average FPS: \(String(format: "%.1f", avgFPS))
            - Minimum FPS: \(String(format: "%.1f", minFPS))
            - Maximum FPS: \(String(format: "%.1f", maxFPS))
            - Current FPS: \(String(format: "%.1f", currentFPS))
            - FPS Readings Count: \(fpsReadings.count)
            """
        }
        
        // Memory Analysis
        let currentMemory = getCurrentMemoryUsage()
        report += """
        
        MEMORY ANALYSIS:
        - Initial Memory: \(String(format: "%.1f", initialMemoryUsage)) MB
        - Current Memory: \(String(format: "%.1f", currentMemory)) MB
        - Peak Memory: \(String(format: "%.1f", peakMemoryUsage)) MB
        - Memory Growth: \(String(format: "%.1f", currentMemory - initialMemoryUsage)) MB
        - Memory Readings Count: \(memoryReadings.count)
        """
        
        // Game Reset Analysis
        if !gameResetTimes.isEmpty {
            let avgResetTime = gameResetTimes.reduce(0, +) / Double(gameResetTimes.count)
            let minResetTime = gameResetTimes.min() ?? 0
            let maxResetTime = gameResetTimes.max() ?? 0
            
            report += """
            
            GAME RESET ANALYSIS:
            - Average Reset Time: \(String(format: "%.3f", avgResetTime)) seconds
            - Fastest Reset: \(String(format: "%.3f", minResetTime)) seconds
            - Slowest Reset: \(String(format: "%.3f", maxResetTime)) seconds
            - Total Resets: \(gameResetTimes.count)
            """
        }
        
        // Performance Snapshots
        if !measurements.isEmpty {
            report += "\n\nPERFORMACE SNAPSHOTS:"
            for (label, data) in measurements {
                if let snapshot = data as? [String: Any] {
                    report += "\n\n\(label.uppercased()):"
                    for (key, value) in snapshot {
                        report += "\n  \(key): \(value)"
                    }
                }
            }
        }
        
        return report
    }
    
    // MARK: - Public Interface
    
    var averageFPS: Double {
        return fpsReadings.isEmpty ? 0 : fpsReadings.reduce(0, +) / Double(fpsReadings.count)
    }
    
    var memoryGrowth: Double {
        return getCurrentMemoryUsage() - initialMemoryUsage
    }
    
    var averageResetTime: Double {
        return gameResetTimes.isEmpty ? 0 : gameResetTimes.reduce(0, +) / Double(gameResetTimes.count)
    }
}

// MARK: - DateFormatter Extension
extension DateFormatter {
    static let iso8601WithFractionalSeconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}