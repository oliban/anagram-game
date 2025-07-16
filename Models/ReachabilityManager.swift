import Foundation
import Network
import Combine

/// Manages network connectivity state using NWPathMonitor
@Observable
class ReachabilityManager {
    
    // MARK: - Observable Properties
    
    /// Current network connectivity state
    private(set) var isConnected: Bool = true  // Start optimistically
    
    /// Current connection type (wifi, cellular, etc.)
    private(set) var connectionType: ConnectionType = .none
    
    /// Whether the connection is expensive (cellular data)
    private(set) var isExpensive: Bool = false
    
    /// Whether the connection is constrained (low data mode)
    private(set) var isConstrained: Bool = false
    
    // MARK: - Types
    
    enum ConnectionType: String, CaseIterable {
        case wifi = "WiFi"
        case cellular = "Cellular"
        case ethernet = "Ethernet"
        case other = "Other"
        case none = "None"
        
        var description: String {
            return rawValue
        }
    }
    
    // MARK: - Private Properties
    
    /// Network path monitor for detecting connectivity changes
    private let monitor = NWPathMonitor()
    
    /// Queue for network monitoring operations
    private let monitorQueue = DispatchQueue(label: "com.anagramgame.reachability", qos: .utility)
    
    /// Combine cancellables
    private var cancellables = Set<AnyCancellable>()
    
    /// Last known network status for change detection
    private var lastKnownStatus: Bool = true  // Start optimistically
    
    /// Whether the monitor has had time to initialize
    private var hasInitialized: Bool = false
    
    // MARK: - Singleton
    
    static let shared = ReachabilityManager()
    
    // MARK: - Initialization
    
    private init() {
        // Check current network status immediately
        let currentPath = monitor.currentPath
        updateConnectionStatus(with: currentPath)
        
        startMonitoring()
        
        // Give the monitor time to initialize properly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.hasInitialized = true
        }
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Starts network monitoring
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updateConnectionStatus(with: path)
            }
        }
        
        monitor.start(queue: monitorQueue)
        print("🌐 REACHABILITY: Started monitoring network connectivity")
    }
    
    /// Stops network monitoring
    func stopMonitoring() {
        monitor.cancel()
        print("🌐 REACHABILITY: Stopped monitoring network connectivity")
    }
    
    /// Forces a connectivity check
    func checkConnectivity() {
        // NWPathMonitor automatically provides updates, but we can log current status
        print("🌐 REACHABILITY: Current status - Connected: \(isConnected), Type: \(connectionType), Expensive: \(isExpensive), Constrained: \(isConstrained)")
    }
    
    /// Gets a human-readable connection status
    func getConnectionStatus() -> String {
        if !isConnected {
            return "No Internet Connection"
        }
        
        var status = "Connected via \(connectionType.description)"
        
        if isExpensive {
            status += " (Cellular Data)"
        }
        
        if isConstrained {
            status += " (Low Data Mode)"
        }
        
        return status
    }
    
    /// Provides intelligent connectivity checking that accounts for initialization timing
    func isReachable() -> Bool {
        // During initialization, be optimistic to avoid blocking legitimate requests
        if !hasInitialized {
            return true
        }
        
        // After initialization, use the actual detected state
        return isConnected
    }
    
    // MARK: - Private Methods
    
    /// Updates connection status based on network path
    private func updateConnectionStatus(with path: NWPath) {
        let wasConnected = isConnected
        let previousType = connectionType
        
        // Update connection state
        let newConnectedState = path.status == .satisfied
        isConnected = newConnectedState
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
        
        // Determine connection type
        connectionType = determineConnectionType(from: path)
        
        // Log status changes
        if wasConnected != isConnected {
            let statusChange = isConnected ? "ONLINE" : "OFFLINE"
            print("🌐 REACHABILITY: Connection status changed to \(statusChange)")
            
            // Post detailed connection info when going online
            if isConnected {
                print("🌐 REACHABILITY: Connected via \(connectionType.description)")
                if isExpensive {
                    print("🌐 REACHABILITY: Warning - Using expensive connection (cellular)")
                }
                if isConstrained {
                    print("🌐 REACHABILITY: Warning - Connection is constrained (low data mode)")
                }
            }
        } else if connectionType != previousType {
            print("🌐 REACHABILITY: Connection type changed to \(connectionType.description)")
        }
        
        // Update last known status
        lastKnownStatus = isConnected
        
        // Mark as initialized after first update
        if !hasInitialized {
            hasInitialized = true
        }
    }
    
    /// Determines connection type from network path
    private func determineConnectionType(from path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else if path.status == .satisfied {
            return .other
        } else {
            return .none
        }
    }
}

// MARK: - Convenience Extensions

extension ReachabilityManager {
    
    /// Whether we should avoid expensive operations (large downloads, etc.)
    var shouldConserveData: Bool {
        return isExpensive || isConstrained
    }
    
    /// Whether we can perform network operations
    var canPerformNetworkOperations: Bool {
        return isConnected
    }
    
    /// Whether we should prefer cached data over network requests
    var shouldPreferCache: Bool {
        return !isConnected || shouldConserveData
    }
    
    /// Gets a color indicator for UI display
    var connectionIndicatorColor: String {
        switch (isConnected, connectionType) {
        case (false, _):
            return "red"
        case (true, .wifi):
            return "green"
        case (true, .cellular):
            return isExpensive ? "orange" : "yellow"
        case (true, .ethernet):
            return "green"
        default:
            return "gray"
        }
    }
}

// MARK: - Notification Support

extension ReachabilityManager {
    
    /// Gets current connection state (replaces publisher pattern)
    var currentConnectionState: Bool {
        return isConnected
    }
    
    /// Gets current connection type (replaces publisher pattern)
    var currentConnectionType: ConnectionType {
        return connectionType
    }
    
    /// Gets current network status tuple (replaces combined publisher)
    var currentNetworkStatus: (Bool, ConnectionType) {
        return (isConnected, connectionType)
    }
}

// MARK: - Debug and Testing Support

extension ReachabilityManager {
    
    /// Forces a specific connection state for testing
    func setDebugConnectionState(connected: Bool, type: ConnectionType = .wifi, expensive: Bool = false, constrained: Bool = false) {
        #if DEBUG
        DispatchQueue.main.async {
            self.isConnected = connected
            self.connectionType = type
            self.isExpensive = expensive
            self.isConstrained = constrained
            
            print("🧪 REACHABILITY: Debug state set - Connected: \(connected), Type: \(type), Expensive: \(expensive), Constrained: \(constrained)")
        }
        #endif
    }
    
    /// Resets to actual network monitoring
    func resetToActualState() {
        #if DEBUG
        // Force a path update by restarting monitoring
        stopMonitoring()
        startMonitoring()
        print("🧪 REACHABILITY: Reset to actual network state")
        #endif
    }
    
    /// Gets detailed debug information
    func getDebugInfo() -> String {
        return """
        🌐 Network Reachability Debug Info:
        - Connected: \(isConnected)
        - Connection Type: \(connectionType.description)
        - Expensive: \(isExpensive)
        - Constrained: \(isConstrained)
        - Should Conserve Data: \(shouldConserveData)
        - Can Perform Network Ops: \(canPerformNetworkOperations)
        - Should Prefer Cache: \(shouldPreferCache)
        - Status: \(getConnectionStatus())
        """
    }
}