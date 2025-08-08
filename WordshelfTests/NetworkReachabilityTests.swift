import XCTest
import Network
@testable import Anagram_Game

final class NetworkReachabilityTests: XCTestCase {
    
    var reachabilityManager: ReachabilityManager!
    var mockNetworkMonitor: MockNetworkMonitor!
    
    override func setUp() {
        super.setUp()
        mockNetworkMonitor = MockNetworkMonitor()
        reachabilityManager = ReachabilityManager(networkMonitor: mockNetworkMonitor)
    }
    
    override func tearDown() {
        reachabilityManager.stopMonitoring()
        reachabilityManager = nil
        mockNetworkMonitor = nil
        super.tearDown()
    }
    
    // MARK: - Basic Reachability Tests
    
    func testInitialReachabilityState() {
        XCTAssertFalse(reachabilityManager.isOnline, "Reachability should start as offline")
        XCTAssertEqual(reachabilityManager.connectionStatus, .unknown, "Initial connection status should be unknown")
    }
    
    func testStartMonitoring() {
        let expectation = XCTestExpectation(description: "Monitoring should start")
        
        reachabilityManager.startMonitoring { success in
            XCTAssertTrue(success, "Start monitoring should succeed")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(mockNetworkMonitor.isMonitoring, "Mock monitor should be monitoring")
    }
    
    func testStopMonitoring() {
        reachabilityManager.startMonitoring { _ in }
        XCTAssertTrue(mockNetworkMonitor.isMonitoring, "Monitor should be active")
        
        reachabilityManager.stopMonitoring()
        XCTAssertFalse(mockNetworkMonitor.isMonitoring, "Monitor should be stopped")
    }
    
    // MARK: - Online/Offline Detection Tests
    
    func testOnlineDetection() {
        let expectation = XCTestExpectation(description: "Should detect online state")
        
        reachabilityManager.onConnectivityChanged = { isOnline in
            if isOnline {
                XCTAssertTrue(self.reachabilityManager.isOnline, "isOnline should be true")
                XCTAssertEqual(self.reachabilityManager.connectionStatus, .online, "Connection status should be online")
                expectation.fulfill()
            }
        }
        
        reachabilityManager.startMonitoring { _ in }
        mockNetworkMonitor.simulateConnectivityChange(isConnected: true, interfaceType: .wifi)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testOfflineDetection() {
        let expectation = XCTestExpectation(description: "Should detect offline state")
        
        // First go online
        reachabilityManager.startMonitoring { _ in }
        mockNetworkMonitor.simulateConnectivityChange(isConnected: true, interfaceType: .wifi)
        
        // Then test offline detection
        reachabilityManager.onConnectivityChanged = { isOnline in
            if !isOnline {
                XCTAssertFalse(self.reachabilityManager.isOnline, "isOnline should be false")
                XCTAssertEqual(self.reachabilityManager.connectionStatus, .offline, "Connection status should be offline")
                expectation.fulfill()
            }
        }
        
        mockNetworkMonitor.simulateConnectivityChange(isConnected: false, interfaceType: .other)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testConnectivityToggle() {
        let expectations = [
            XCTestExpectation(description: "Should detect online"),
            XCTestExpectation(description: "Should detect offline"),
            XCTestExpectation(description: "Should detect online again")
        ]
        var callCount = 0
        
        reachabilityManager.onConnectivityChanged = { isOnline in
            switch callCount {
            case 0:
                XCTAssertTrue(isOnline, "First change should be online")
                expectations[0].fulfill()
            case 1:
                XCTAssertFalse(isOnline, "Second change should be offline")
                expectations[1].fulfill()
            case 2:
                XCTAssertTrue(isOnline, "Third change should be online again")
                expectations[2].fulfill()
            default:
                XCTFail("Unexpected connectivity change")
            }
            callCount += 1
        }
        
        reachabilityManager.startMonitoring { _ in }
        
        // Simulate connectivity changes
        mockNetworkMonitor.simulateConnectivityChange(isConnected: true, interfaceType: .wifi)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.mockNetworkMonitor.simulateConnectivityChange(isConnected: false, interfaceType: .other)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.mockNetworkMonitor.simulateConnectivityChange(isConnected: true, interfaceType: .cellular)
        }
        
        wait(for: expectations, timeout: 2.0)
    }
    
    // MARK: - Connection Type Detection Tests
    
    func testWiFiConnectionDetection() {
        let expectation = XCTestExpectation(description: "Should detect WiFi connection")
        
        reachabilityManager.onConnectivityChanged = { isOnline in
            if isOnline {
                XCTAssertEqual(self.reachabilityManager.connectionType, .wifi, "Connection type should be WiFi")
                expectation.fulfill()
            }
        }
        
        reachabilityManager.startMonitoring { _ in }
        mockNetworkMonitor.simulateConnectivityChange(isConnected: true, interfaceType: .wifi)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testCellularConnectionDetection() {
        let expectation = XCTestExpectation(description: "Should detect cellular connection")
        
        reachabilityManager.onConnectivityChanged = { isOnline in
            if isOnline {
                XCTAssertEqual(self.reachabilityManager.connectionType, .cellular, "Connection type should be cellular")
                expectation.fulfill()
            }
        }
        
        reachabilityManager.startMonitoring { _ in }
        mockNetworkMonitor.simulateConnectivityChange(isConnected: true, interfaceType: .cellular)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Notification Tests
    
    func testConnectivityChangeNotifications() {
        let expectation = XCTestExpectation(description: "Should receive connectivity notifications")
        expectation.expectedFulfillmentCount = 2
        
        var notificationCount = 0
        NotificationCenter.default.addObserver(forName: .connectivityChanged, object: nil, queue: .main) { notification in
            notificationCount += 1
            
            guard let userInfo = notification.userInfo,
                  let isOnline = userInfo["isOnline"] as? Bool else {
                XCTFail("Notification should contain isOnline userInfo")
                return
            }
            
            if notificationCount == 1 {
                XCTAssertTrue(isOnline, "First notification should indicate online")
            } else if notificationCount == 2 {
                XCTAssertFalse(isOnline, "Second notification should indicate offline")
            }
            
            expectation.fulfill()
        }
        
        reachabilityManager.startMonitoring { _ in }
        mockNetworkMonitor.simulateConnectivityChange(isConnected: true, interfaceType: .wifi)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.mockNetworkMonitor.simulateConnectivityChange(isConnected: false, interfaceType: .other)
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - Error Handling Tests
    
    func testMonitoringFailure() {
        mockNetworkMonitor.shouldFailStart = true
        
        let expectation = XCTestExpectation(description: "Should handle monitoring failure")
        
        reachabilityManager.startMonitoring { success in
            XCTAssertFalse(success, "Start monitoring should fail")
            XCTAssertFalse(self.mockNetworkMonitor.isMonitoring, "Monitor should not be active")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGracefulPathUpdate() {
        reachabilityManager.startMonitoring { _ in }
        
        // Simulate various path states
        mockNetworkMonitor.simulateConnectivityChange(isConnected: true, interfaceType: .wifi)
        XCTAssertTrue(reachabilityManager.isOnline, "Should be online with WiFi")
        
        mockNetworkMonitor.simulateConnectivityChange(isConnected: true, interfaceType: .cellular)
        XCTAssertTrue(reachabilityManager.isOnline, "Should remain online with cellular")
        
        mockNetworkMonitor.simulateConnectivityChange(isConnected: false, interfaceType: .other)
        XCTAssertFalse(reachabilityManager.isOnline, "Should be offline")
    }
    
    // MARK: - Performance Tests
    
    func testMultipleQuickConnectivityChanges() {
        let expectation = XCTestExpectation(description: "Should handle rapid connectivity changes")
        expectation.expectedFulfillmentCount = 5
        
        var changeCount = 0
        reachabilityManager.onConnectivityChanged = { _ in
            changeCount += 1
            expectation.fulfill()
        }
        
        reachabilityManager.startMonitoring { _ in }
        
        // Simulate rapid connectivity changes
        for i in 0..<5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) {
                self.mockNetworkMonitor.simulateConnectivityChange(
                    isConnected: i % 2 == 0,
                    interfaceType: i % 2 == 0 ? .wifi : .other
                )
            }
        }
        
        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(changeCount, 5, "Should receive all connectivity changes")
    }
}

// MARK: - Mock Network Monitor

class MockNetworkMonitor: NetworkMonitorProtocol {
    private(set) var isMonitoring = false
    private(set) var pathUpdateHandler: ((NWPath) -> Void)?
    var shouldFailStart = false
    
    func start(queue: DispatchQueue) -> Bool {
        if shouldFailStart {
            return false
        }
        isMonitoring = true
        return true
    }
    
    func cancel() {
        isMonitoring = false
        pathUpdateHandler = nil
    }
    
    func setPathUpdateHandler(_ handler: @escaping (NWPath) -> Void) {
        pathUpdateHandler = handler
    }
    
    func simulateConnectivityChange(isConnected: Bool, interfaceType: NWInterface.InterfaceType) {
        guard let handler = pathUpdateHandler else { return }
        
        let mockPath = MockNWPath(isConnected: isConnected, interfaceType: interfaceType)
        DispatchQueue.main.async {
            handler(mockPath)
        }
    }
}

// MARK: - Mock NWPath

class MockNWPath: NWPath {
    private let _status: NWPath.Status
    private let _availableInterfaces: [NWInterface]
    
    init(isConnected: Bool, interfaceType: NWInterface.InterfaceType) {
        _status = isConnected ? .satisfied : .unsatisfied
        _availableInterfaces = isConnected ? [MockNWInterface(type: interfaceType)] : []
        super.init()
    }
    
    override var status: NWPath.Status {
        return _status
    }
    
    override var availableInterfaces: [NWInterface] {
        return _availableInterfaces
    }
}

// MARK: - Mock NWInterface

class MockNWInterface: NWInterface {
    private let _type: NWInterface.InterfaceType
    
    init(type: NWInterface.InterfaceType) {
        _type = type
        super.init()
    }
    
    override var type: NWInterface.InterfaceType {
        return _type
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let connectivityChanged = Notification.Name("ConnectivityChanged")
}

// MARK: - Protocol for Dependency Injection

protocol NetworkMonitorProtocol {
    func start(queue: DispatchQueue) -> Bool
    func cancel()
    func setPathUpdateHandler(_ handler: @escaping (NWPath) -> Void)
}