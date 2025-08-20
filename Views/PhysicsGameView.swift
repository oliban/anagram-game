//
//  PhysicsGameView.swift
//  Anagram Game
//
//  Created by Fredrik Säfsten on 2025-07-05.
//

import SwiftUI
import SpriteKit
import CoreMotion




// Hint Button Component embedded in PhysicsGameView


struct PhysicsGameView: View {
    @ObservedObject var gameModel: GameModel
    @Binding var showingGame: Bool
    @State private var motionManager = CMMotionManager()
    @State private var gameScene: PhysicsGameScene?
    @State private var celebrationMessage = ""
    @State private var isSkipping = false
    @State private var showingPhraseCreation = false
    @State private var isJolting = false
    @StateObject private var networkManager = NetworkManager.shared
    
    // Computed property to check if skip should be disabled
    private var shouldDisableSkip: Bool {
        return isSkipping || gameModel.gameState == .noPhrasesAvailable || gameModel.currentSentence == "No more phrases available"
    }
    
    // Real-time metrics
    @State private var currentFPS: Double = 60.0
    @State private var currentMemoryMB: Double = 100.0
    @State private var tilesCount: Int = 0
    @State private var metricsTimer: Timer?
    
    // Performance monitoring configuration - disabled for troubleshooting
    @State private var isPerformanceMonitoringEnabled = false
    
    // Static reference to avoid SwiftUI state issues
    private static var sharedScene: PhysicsGameScene?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // SpriteKit scene for physics
                SpriteKitView(scene: getOrCreateScene(size: geometry.size))
                    .ignoresSafeArea()
                
                // UI Layout - Clean and Simple
                VStack {
                    // TOP ROW - Lobby/Hint buttons on left, progression bar on right
                    HStack(alignment: .top) {
                        // Left group: Lobby + Hint buttons (stacked)
                        VStack(alignment: .leading, spacing: 8) {
                            // Back to Lobby button
                            Button(action: {
                                Task {
                                    await gameModel.skipCurrentGame()
                                    showingGame = false
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.left")
                                    Text("Lobby")
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(20)
                                .shadow(radius: 4)
                            }
                            
                            // Hint button aligned to left edge of lobby button
                            HStack {
                                HintButtonView(phraseId: gameModel.currentPhraseId ?? "local-fallback", gameModel: gameModel, gameScene: gameScene ?? PhysicsGameView.sharedScene) { _ in
                                    // No longer used - clue is now displayed persistently
                                }
                                .scaleEffect(0.85, anchor: .leading) // Scale from leading edge to maintain left alignment
                                Spacer()
                            }
                            
                        }
                        .padding(.leading, 16)
                        .padding(.top, 10) // Match progress bar's top padding
                        
                        Spacer(minLength: 2) // Minimal space for progress bar
                        
                        // Score and Version Stack - using more width
                        VStack(spacing: 2) {
                            // Total Score Display with Level
                            UnifiedSkillLevelView(
                                levelConfig: gameModel.levelConfig,
                                totalScore: gameModel.playerTotalScore,
                                isLevelingUp: gameModel.isLevelingUp
                            )
                            .frame(maxWidth: .infinity) // Use maximum available width
                            
                        }
                        .padding(.trailing, 10)
                        .padding(.top, 10)
                    }
                    
                    // MIDDLE - Game content and overlays
                    // Custom phrase info now handled by MessageTile spawning
                    
                    
                    
                    // Celebration is now handled entirely in SpriteKit scene
                    // No SwiftUI text overlay needed
                    
                    
                    
                    Spacer() // Push bottom controls down
                    
                    // Connection indicator overlay - only visible when not connected
                    if networkManager.connectionStatus != .connected {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(connectionStatusColor)
                                .frame(width: 10, height: 10)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                                .animation(.easeInOut(duration: 0.3), value: networkManager.connectionStatus)
                            
                            Text(networkManager.connectionStatus.description)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .onAppear {
                                    DebugLogger.shared.network("Connection status displayed: \(networkManager.connectionStatus.description)")
                                }
                                .onChange(of: networkManager.connectionStatus) { oldValue, newValue in
                                    let oldDesc = oldValue.description
                                    let newDesc = newValue.description
                                    DebugLogger.shared.network("Connection status changed: \(oldDesc) → \(newDesc)")
                                }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(connectionStatusBackgroundColor)
                                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .padding(.bottom, 8)
                    }
                    
                    // REAL-TIME METRICS DISPLAY - conditional on performance monitoring
                    if isPerformanceMonitoringEnabled {
                        VStack(spacing: 4) {
                            HStack(spacing: 16) {
                                // FPS
                                VStack(spacing: 2) {
                                    Text("FPS")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    Text("\(String(format: "%.1f", currentFPS))")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(currentFPS < 30 ? .red : (currentFPS < 50 ? .orange : .green))
                                }
                                
                                // Memory
                                VStack(spacing: 2) {
                                    Text("MEM")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    Text("\(String(format: "%.0f", currentMemoryMB))MB")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(currentMemoryMB > 200 ? .red : (currentMemoryMB > 150 ? .orange : .green))
                                }
                                
                                // Tiles Count
                                VStack(spacing: 2) {
                                    Text("TILES")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    Text("\(tilesCount)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                }
                                
                                // Quake State
                                VStack(spacing: 2) {
                                    Text("QUAKE")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    Text(getQuakeStateText())
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(getQuakeStateColor())
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(12)
                            .shadow(radius: 3)
                        }
                        .padding(.bottom, 8)
                    }
                    
                    // BOTTOM ROW - Clean layout inside ZStack
                    HStack(alignment: .bottom) {
                        // Bottom-left: Send Phrase button 
                        Button(action: {
                            showingPhraseCreation = true
                        }) {
                            HStack {
                                Image(systemName: "square.and.pencil")
                                Text("Send Phrase")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.8))
                            .cornerRadius(20)
                            .shadow(radius: 4)
                        }
                        .offset(y: isJolting ? -8 : 0)
                        .animation(.easeInOut(duration: 0.15), value: isJolting)
                        .padding(.leading, 20)
                        
                        Spacer() // Push buttons to the right
                        
                        // CHEAT TEST BUTTON - Cycles through all rarity effects
                        #if DEBUG
                        Button(action: {
                            testCelebrationEffect()
                        }) {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                Text("🎆")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.purple.opacity(0.8))
                            .cornerRadius(20)
                            .shadow(radius: 4)
                        }
                        .offset(y: isJolting ? -8 : 0)
                        .animation(.easeInOut(duration: 0.15), value: isJolting)
                        .padding(.trailing, 10)
                        #endif
                        
                        // Bottom-right: Skip button (moved from left)
                        Button(action: {
                            print("🔥🔥🔥 SKIP BUTTON TAPPED IN UI 🔥🔥🔥")
                            Task {
                                // Enhanced memory tracking for skip operation
                                let preSkipMemory: Double
                                let preSkipTiles: Int
                                let preSkipChildren: Int
                                
                                if isPerformanceMonitoringEnabled {
                                    preSkipMemory = getMemoryUsage()
                                    preSkipTiles = gameScene?.tiles.count ?? 0
                                    preSkipChildren = gameScene?.children.count ?? 0
                                    
                                    // Log detailed pre-skip state
                                    await DebugLogger.shared.sendToServer("SKIP_PRESSED: Memory before: \(String(format: "%.1f", preSkipMemory))MB, Tiles: \(preSkipTiles), Scene children: \(preSkipChildren)")
                                    
                                } else {
                                    preSkipMemory = 0.0
                                    preSkipTiles = 0
                                    preSkipChildren = 0
                                }
                                
                                isSkipping = true
                                
                                print("🔥 About to call gameModel.skipCurrentGame()")
                                await gameModel.skipCurrentGame()
                                print("🔥 Finished calling gameModel.skipCurrentGame()")
                                
                                // The GameModel.startNewGame() will handle scene updates automatically
                                // Longer delay to ensure tile creation is fully complete
                                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                                
                                // Track memory after skip operation completes
                                if isPerformanceMonitoringEnabled {
                                    let postSkipMemory = getMemoryUsage()
                                    let postSkipTiles = gameScene?.tiles.count ?? 0
                                    let postSkipChildren = gameScene?.children.count ?? 0
                                    let memoryDelta = postSkipMemory - preSkipMemory
                                    let tilesDelta = postSkipTiles - preSkipTiles
                                    let childrenDelta = postSkipChildren - preSkipChildren
                                    
                                    await DebugLogger.shared.sendToServer("SKIP_COMPLETE: Memory after: \(String(format: "%.1f", postSkipMemory))MB (Δ\(String(format: "%.1f", memoryDelta))MB), Tiles: \(postSkipTiles) (Δ\(tilesDelta)), Children: \(postSkipChildren) (Δ\(childrenDelta))")
                                    
                                }
                                
                                isSkipping = false
                            }
                        }) {
                            HStack {
                                if isSkipping {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Loading...")
                                } else if gameModel.gameState == .noPhrasesAvailable || gameModel.currentSentence == "No more phrases available" {
                                    Image(systemName: "pause.circle.fill")
                                    Text("No Skip")
                                } else {
                                    Image(systemName: "forward.fill")
                                    Text("Skip")
                                }
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.orange.opacity(0.8))
                            .cornerRadius(20)
                            .shadow(radius: 4)
                        }
                        .disabled(shouldDisableSkip)
                        .opacity(shouldDisableSkip ? 0.6 : 1.0)
                        .offset(y: isJolting ? -8 : 0)
                        .animation(.easeInOut(duration: 0.15), value: isJolting)
                        .padding(.trailing, 10)
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .fullScreenCover(isPresented: $showingPhraseCreation) {
            PhraseCreationView(isPresented: $showingPhraseCreation)
        }
        .onAppear {
            print("🎬 PhysicsGameView appeared")
            
            // Start metrics timer immediately
            startMetricsTimer()
            
            // Listen for performance monitoring configuration changes
            NotificationCenter.default.addObserver(
                forName: .performanceMonitoringConfigChanged,
                object: nil,
                queue: .main
            ) { notification in
                if let enabled = notification.object as? Bool {
                    isPerformanceMonitoringEnabled = enabled
                    print("🎬 PhysicsGameView: Performance monitoring \(enabled ? "enabled" : "disabled") by server")
                }
            }
            
            // Delay setup to ensure scene is created first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.setupGame()
            }
        }
        .onDisappear {
            motionManager.stopDeviceMotionUpdates()
            metricsTimer?.invalidate()
            
            // Remove notification observer to prevent memory leaks
            NotificationCenter.default.removeObserver(self, name: .performanceMonitoringConfigChanged, object: nil)
        }
    }
    
    // MARK: - Metrics Helper Functions
    
    private func getQuakeStateText() -> String {
        guard let scene = gameScene ?? PhysicsGameView.sharedScene else { return "—" }
        switch scene.quakeState {
        case .none: return "NONE"
        case .normal: return "NORM"
        case .superQuake: return "SUPER"
        }
    }
    
    private func getQuakeStateColor() -> Color {
        guard let scene = gameScene ?? PhysicsGameView.sharedScene else { return .gray }
        switch scene.quakeState {
        case .none: return .gray
        case .normal: return .orange
        case .superQuake: return .red
        }
    }
    
    private func startMetricsTimer() {
        guard isPerformanceMonitoringEnabled else { 
            print("📊 METRICS: Performance monitoring disabled, skipping timer setup")
            return 
        }
        
        metricsTimer?.invalidate()
        print("📊 METRICS: Starting metrics timer...")
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.updateMetrics()
        }
        print("📊 METRICS: Timer started successfully")
    }
    
    private func updateMetrics() {
        guard isPerformanceMonitoringEnabled else { return }
        
        DispatchQueue.main.async {
            // Always update memory usage
            self.currentMemoryMB = self.getMemoryUsage()
            
            // Update scene-dependent metrics if scene is available
            if let scene = gameScene ?? PhysicsGameView.sharedScene {
                self.currentFPS = scene.currentFPS
                self.tilesCount = scene.tiles.count
                
                // Log metrics to console
                print("📊 REAL-TIME METRICS: FPS: \(String(format: "%.1f", self.currentFPS)), Memory: \(String(format: "%.1f", self.currentMemoryMB))MB, Tiles: \(self.tilesCount), Quake: \(scene.quakeState)")
                
                // Send metrics to server every 10 updates (every 5 seconds)
                if Int.random(in: 1...10) == 1 {
                    Task {
                        await self.sendMetricsToServer(fps: self.currentFPS, memory: self.currentMemoryMB, tiles: self.tilesCount, quakeState: scene.quakeState)
                    }
                }
            } else {
                print("⚠️ METRICS: No scene available - Memory: \(String(format: "%.1f", self.currentMemoryMB))MB")
            }
        }
    }
    
    private func getMemoryUsage() -> Double {
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
    
    private func sendMetricsToServer(fps: Double, memory: Double, tiles: Int, quakeState: PhysicsGameScene.QuakeState) async {
        guard isPerformanceMonitoringEnabled else { return }
        guard let url = URL(string: "\(AppConfig.baseURL)/api/debug/performance") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let quakeString = switch quakeState {
        case .none: "none"
        case .normal: "normal" 
        case .superQuake: "super"
        }
        
        let logData: [String: Any] = [
            "event": "real_time_metrics",
            "fps": fps,
            "memory_mb": memory,
            "tiles_count": tiles,
            "quake_state": quakeString,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "playerId": gameModel.playerId ?? "unknown",
            "component": "PhysicsGameView_RealTime"
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: logData)
            request.httpBody = jsonData
            let _ = try await URLSession.shared.data(for: request)
        } catch {
            print("❌ Failed to send real-time metrics: \(error)")
        }
    }
    
    private func getOrCreateScene(size: CGSize) -> PhysicsGameScene {
        if let existingScene = PhysicsGameView.sharedScene {
            print("♻️ Reusing shared scene")
            return existingScene
        }
        
        // Validate size to prevent invalid scene creation
        // Use reasonable defaults for iPhone screen sizes if geometry is not ready
        let validSize = CGSize(
            width: size.width > 0 ? size.width : 393,  // iPhone 14 Pro width
            height: size.height > 0 ? size.height : 852  // iPhone 14 Pro height
        )
        
        print("🚀 Creating SINGLE scene with size: \(validSize) (original: \(size))")
        let newScene = PhysicsGameScene(gameModel: gameModel, size: validSize)
        
        PhysicsGameView.sharedScene = newScene
        print("✅ Scene stored")
        return newScene
    }
    
    private func setupGame() {
        
        // Set up gameScene reference and callbacks
        if let sharedScene = PhysicsGameView.sharedScene {
            print("✅ Found shared scene, setting up callbacks")
            
            // Set gameScene reference
            gameScene = sharedScene
            
            // Set up celebration callback - no longer displays text messages
            sharedScene.onCelebration = { message in
                // Celebration is now handled entirely in SpriteKit scene
                // No SwiftUI text overlay needed
                print("🎊 Celebration triggered: \(message)")
            }
            
            // Set up jolt callback for UI buttons
            sharedScene.onJolt = {
                DispatchQueue.main.async {
                    self.isJolting = true
                    // Reset after brief animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.isJolting = false
                    }
                }
            }
            
            sharedScene.motionManager = motionManager
            sharedScene.resetGame()
        } else {
            print("❌ No shared scene available")
        }
        
        setupMotionManager()
    }
    
    private func setupMotionManager() {
        print("🎯 setupMotionManager() called")
        print("🎯 Motion manager available: \(motionManager.isDeviceMotionAvailable)")
        
        guard motionManager.isDeviceMotionAvailable else { 
            print("❌ Device motion not available")
            return 
        }
        
        print("✅ Starting device motion updates")
        motionManager.deviceMotionUpdateInterval = 1.0 / 10.0  // Faster updates for debugging
        motionManager.startDeviceMotionUpdates(to: .main) { motion, error in
            guard let motion = motion, error == nil else { 
                print("❌ Motion error: \(error?.localizedDescription ?? "Unknown")")
                return 
            }
            
            // NO SwiftUI state updates here - everything handled in scene
            PhysicsGameView.sharedScene?.updateGravity(from: motion.gravity)
        }
        print("✅ Motion updates started")
        
        // Start metrics timer for real-time display
        startMetricsTimer()
    }
    
    private var connectionStatusColor: Color {
        switch networkManager.connectionStatus {
        case .disconnected:
            return .red
        case .connecting:
            return .yellow
        case .connected:
            return .green
        case .error:
            return .red
        }
    }
    
    private var connectionStatusBackgroundColor: Color {
        switch networkManager.connectionStatus {
        case .disconnected, .error:
            return Color.red.opacity(0.9)
        case .connecting:
            return Color.orange.opacity(0.9)
        case .connected:
            return Color.green.opacity(0.9)
        }
    }
    
    // MARK: - Debug Test Functions
    
    #if DEBUG
    private func testCelebrationEffect() {
        DebugLogger.shared.ui("🚨 CHEAT BUTTON PRESSED: Triggering normal phrase completion")
        
        guard let scene = gameScene else { 
            DebugLogger.shared.error("❌ ERROR: No game scene found")
            return 
        }
        
        DebugLogger.shared.ui("✅ SCENE FOUND: Game scene is available")
        
        // Enable tile preservation mode for emoji effects during celebration
        scene.disableImmediateEmojiEffects = true
        DebugLogger.shared.ui("🎭 PRESERVATION: Enabled tile preservation mode - newly dropped tiles will be preserved during new game creation")
        
        // Trigger EXACT same sequence as normal phrase completion (lines 2258-2264)
        scene.animateShelvesToFloor()
        gameModel.completeGame() // Calculate score immediately
        
        // Trigger celebration on next run loop to ensure score is updated
        DispatchQueue.main.async { [weak scene] in
            scene?.triggerCelebration() // Celebrate with updated score
        }
        
        DebugLogger.shared.ui("✅ CHEAT: Normal phrase completion sequence triggered")
    }
    
    private func getEmojiForRarity(_ rarity: EmojiRarity) -> String {
        switch rarity {
        case .legendary: return "👑"
        case .mythic: return "🌟"
        case .epic: return "⚡"
        case .rare: return "💎"
        case .uncommon: return "✨"
        case .common: return "⭐"
        }
    }
    
    private func getDropRateForRarity(_ rarity: EmojiRarity) -> Double {
        switch rarity {
        case .legendary: return 0.1
        case .mythic: return 0.5
        case .epic: return 2.0
        case .rare: return 8.0
        case .uncommon: return 20.0
        case .common: return 69.4
        }
    }
    
    private func getTestPointsForRarity(_ rarity: EmojiRarity) -> Int {
        switch rarity {
        case .legendary: return 500
        case .mythic: return 200
        case .epic: return 100
        case .rare: return 25
        case .uncommon: return 5
        case .common: return 1
        }
    }
    #endif
}

// Protocol for tiles that can be respawned when they go off-screen
class PhysicsGameScene: SKScene, MessageTileSpawner, SKPhysicsContactDelegate {
    
    // MARK: - Emoji Effects Queue for Cleanup Phase
    private var newlyDroppedEmojiTiles: [EmojiIconTile] = [] // Track tiles from current game only
    var disableImmediateEmojiEffects = false // Flag to disable immediate effects during cheat test
    
    
    // MARK: - Scale Factor for Easy Experimentation
    static let componentScaleFactor: CGFloat = 0.90  // 0.90 = 10% smaller, 1.1 = 10% larger (public for external access)
    
    // Congratulatory messages for celebration
    private static let congratulatoryMessages = [
        "YEY you rock!",
        "Fantastic!",
        "Awesome job!",
        "Brilliant!",
        "You're amazing!",
        "Perfect!",
        "Outstanding!",
        "Incredible!",
        "Well done!",
        "Spectacular!"
    ]
    
    private let gameModel: GameModel
    var motionManager: CMMotionManager?
    var onCelebration: ((String) -> Void)?
    var onJolt: (() -> Void)?
    
    private var bookshelf: SKNode!
    private var bookshelfOriginalPosition: CGPoint = CGPoint.zero
    private var shelfOriginalPositions: [SKNode: CGPoint] = [:]
    private var physicsBodyOriginalPositions: [SKSpriteNode: CGPoint] = [:]
    private var isBookshelfJolting: Bool = false
    private var hasBookshelfAnimated: Bool = false
    private var floor: SKNode!
    var tiles: [LetterTile] = []
    private var scoreTile: ScoreTile?
    private var languageTile: LanguageTile?
    
    // Debug text area
    private var debugTextNode: SKLabelNode?
    private var debugBackground: SKShapeNode?
    private var debugMessages: [String] = []
    private let maxDebugMessages = 8
    private var messageTiles: [MessageTile] = []
    private var themeTiles: [ThemeInformationTile] = []
    
    // Unified collection for respawn tracking
    private var allRespawnableTiles: [RespawnableTile] {
        var allTiles: [RespawnableTile] = []
        allTiles.append(contentsOf: tiles)
        allTiles.append(contentsOf: messageTiles)
        allTiles.append(contentsOf: themeTiles)
        if let scoreTile = scoreTile { allTiles.append(scoreTile) }
        if let languageTile = languageTile { allTiles.append(languageTile) }
        return allTiles
    }
    private var shelves: [SKNode] = []  // Track individual shelves for hint system
    var celebrationText: String = ""

    enum QuakeState { case none, normal, superQuake }
    var quakeState: QuakeState = .none
    private var quakeEndAction: SKAction?
    
    // FPS tracking
    private var lastUpdateTime: TimeInterval = 0
    private var frameCount: Int = 0
    private var lastFPSUpdateTime: TimeInterval = 0
    var currentFPS: Double = 60.0
    
    init(gameModel: GameModel, size: CGSize) {
        self.gameModel = gameModel
        super.init(size: size)
        
        // Set explicit background color to avoid device-specific rendering issues
        backgroundColor = UIColor.systemBackground
        
        setupPhysicsWorld()
        setupEnvironment()
        // setupDebugTextArea()  // Debug display disabled
        
        // Connect this scene as the message tile spawner
        gameModel.messageTileSpawner = self
        
        // Debug: Verify connection is made
        print("🔗 Scene connected to GameModel as messageTileSpawner")
        
        // Notify GameModel that connection is established (for pending debug tiles)
        gameModel.onMessageTileSpawnerConnected()
        // Scene connection debug logging removed to reduce API calls during startup
        
        // Listen for emoji points changes to update score display in real-time
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(handleEmojiPointsChanged(_:)), 
            name: NSNotification.Name("EmojiPointsChanged"), 
            object: gameModel
        )
        
        // Don't create tiles automatically - wait for setupGame() to call resetGame()
        
        // Enable simple automatic scoring
        let checkAction = SKAction.sequence([
            SKAction.wait(forDuration: 3.0),  // Check every 3 seconds
            SKAction.run { [weak self] in
                self?.checkSolution()
            }
        ])
        run(SKAction.repeatForever(checkAction))
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupPhysicsWorld() {
        physicsWorld.gravity = CGVector(dx: 0, dy: -30.0) // Much stronger gravity for heavy feel
        physicsWorld.contactDelegate = self
        
        // Create world boundaries
        let boundary = SKPhysicsBody(edgeLoopFrom: self.frame)
        boundary.friction = 0.1  // Lower friction on screen edges
        boundary.restitution = 0.4  // Higher bounce off screen edges
        physicsBody = boundary
    }
    
    private func setupDebugTextArea() {
        // FULL WIDTH DEBUG BOX - RIGHT EDGE TO RIGHT EDGE
        let debugWidth = size.width - 20  // Full width minus small margins (back to original)
        let debugHeight: CGFloat = 150
        
        debugBackground = SKShapeNode(rectOf: CGSize(width: debugWidth, height: debugHeight))
        debugBackground?.fillColor = UIColor.black.withAlphaComponent(0.95)
        debugBackground?.strokeColor = .yellow
        debugBackground?.lineWidth = 3
        debugBackground?.position = CGPoint(x: 200, y: size.height/2 - debugHeight/2 - 80)  // 200px to the right (back 100px)
        debugBackground?.zPosition = 1000
        addChild(debugBackground!)
        
        // Text positioned at top-left of debug box
        debugTextNode = SKLabelNode()
        debugTextNode?.fontSize = 11
        debugTextNode?.fontName = "Courier"
        debugTextNode?.fontColor = .white
        debugTextNode?.verticalAlignmentMode = .top
        debugTextNode?.horizontalAlignmentMode = .left
        debugTextNode?.position = CGPoint(x: 200 - debugWidth/2 + 10, y: size.height/2 - 90)  // 200px to the right (back 100px)
        debugTextNode?.zPosition = 1001
        debugTextNode?.numberOfLines = 0
        debugTextNode?.preferredMaxLayoutWidth = debugWidth - 20
        addChild(debugTextNode!)
        
        // Initial debug message
        addDebugMessage("=== PHYSICS DEBUG ACTIVE ===")
        addDebugMessage("Drop heavy (M,W,Q,X,Z) on light (I,L,J,T)")
        addDebugMessage("Weights: LIGHT=0.15, MED=0.2, HEAVY=0.3")
        addDebugMessage("Velocity threshold: < -20 for squashing")
    }
    
    private func addDebugMessage(_ message: String) {
        // Debug messages disabled
        return
    }
    
    private func updateDebugDisplay() {
        let displayText = "DEBUG OUTPUT\n" + debugMessages.joined(separator: "\n")
        debugTextNode?.text = displayText
    }
    
    private func setupEnvironment() {
        // Apply isometric transformation to the entire scene
        let _ = CGAffineTransform.identity
            .scaledBy(x: 1.0, y: 0.6)
            .rotated(by: .pi / 6)
        
        // Create isometric floor with depth
        floor = SKNode()
        floor.position = CGPoint(x: size.width / 2, y: size.height * 0.15 + 50 - 50)
        addChild(floor)
        
        // Floor shape removed - keeping only physics body for collision detection
        let floorWidth: CGFloat = size.width * 0.9
        
        // Physics body for floor (invisible rectangle for physics)
        let floorPhysics = SKSpriteNode(color: .clear, size: CGSize(width: floorWidth, height: 20))
        floorPhysics.physicsBody = SKPhysicsBody(rectangleOf: floorPhysics.size)
        floorPhysics.physicsBody?.isDynamic = false
        floorPhysics.physicsBody?.friction = 0.6  // Higher friction to prevent sliding around
        floorPhysics.physicsBody?.categoryBitMask = PhysicsCategories.floor
        floorPhysics.physicsBody?.contactTestBitMask = PhysicsCategories.tile
        floorPhysics.physicsBody?.collisionBitMask = PhysicsCategories.tile
        floor.addChild(floorPhysics)
        
        // Create realistic bookshelf
        bookshelf = SKNode()
        bookshelfOriginalPosition = CGPoint(x: size.width / 2, y: size.height * 0.4 + 70 - 50)
        bookshelf.position = bookshelfOriginalPosition
        addChild(bookshelf)
        
        let baseShelfWidthRatio: CGFloat = 0.75  // Original shelf width ratio
        let baseShelfHeight: CGFloat = 374  // Original shelf height
        let shelfWidth: CGFloat = size.width * baseShelfWidthRatio * PhysicsGameScene.componentScaleFactor
        let shelfHeight: CGFloat = baseShelfHeight * PhysicsGameScene.componentScaleFactor
        let shelfDepth: CGFloat = 50
        
        // Create bookshelf frame structure
        createBookshelfFrame(width: shelfWidth, height: shelfHeight, depth: shelfDepth)
        
        // Clear shelves array for clean setup
        shelves.removeAll()
        
        // Create multiple shelves with proper wood grain appearance
        for i in 0..<4 {
            let baseShelfSpacing: CGFloat = 113.3  // Increased by 10% from 103
            let shelfY = CGFloat(-140 + (CGFloat(i) * baseShelfSpacing * PhysicsGameScene.componentScaleFactor))
            let shelf = createRealisticShelf(width: shelfWidth - 20, y: shelfY, depth: shelfDepth)  // Reduced inset from 30 to 20
            shelf.name = "shelf_\(i)"  // Add identifier for hint system
            bookshelf.addChild(shelf)
            shelves.append(shelf)  // Track shelf for hint system
            
            // Store original position for physics body reset
            shelfOriginalPositions[shelf] = shelf.position
            
            // Store original physics body positions in world coordinates
            for child in shelf.children {
                if let physicsNode = child as? SKSpriteNode, physicsNode.physicsBody != nil {
                    // Convert to world coordinates and store
                    let worldPosition = shelf.convert(physicsNode.position, to: self)
                    physicsBodyOriginalPositions[physicsNode] = worldPosition
                }
            }
        }
        
    }
    
    private func createBookshelfFrame(width: CGFloat, height: CGFloat, depth: CGFloat) {
        let wallThickness: CGFloat = 12
        let depthOffset: CGFloat = 15  // 3D depth effect
        
        // Left side panel - properly aligned with consistent thickness
        let leftPanel = SKShapeNode()
        let leftPath = CGMutablePath()
        // Front face - moved 10px to the left
        leftPath.move(to: CGPoint(x: -width / 2 - wallThickness/2 - 10, y: -height / 2))
        leftPath.addLine(to: CGPoint(x: -width / 2 - wallThickness/2 - 10, y: height / 2))
        leftPath.addLine(to: CGPoint(x: -width / 2 + wallThickness/2 - 10, y: height / 2))
        leftPath.addLine(to: CGPoint(x: -width / 2 + wallThickness/2 - 10, y: -height / 2))
        leftPath.closeSubpath()
        
        leftPanel.path = leftPath
        leftPanel.fillColor = UIColor(red: 0.65, green: 0.45, blue: 0.25, alpha: 1.0)  // Medium wood color
        leftPanel.strokeColor = UIColor(red: 0.4, green: 0.25, blue: 0.15, alpha: 1.0)
        leftPanel.lineWidth = 1.5
        leftPanel.zPosition = 2
        bookshelf.addChild(leftPanel)
        
        // Left panel 3D depth side
        let leftDepth = SKShapeNode()
        let leftDepthPath = CGMutablePath()
        leftDepthPath.move(to: CGPoint(x: -width / 2 + wallThickness/2 - 10, y: height / 2))
        leftDepthPath.addLine(to: CGPoint(x: -width / 2 + wallThickness/2 - 10, y: -height / 2))
        leftDepthPath.addLine(to: CGPoint(x: -width / 2 + wallThickness/2 + depthOffset - 10, y: -height / 2 + depthOffset))
        leftDepthPath.addLine(to: CGPoint(x: -width / 2 + wallThickness/2 + depthOffset - 10, y: height / 2 + depthOffset))
        leftDepthPath.closeSubpath()
        
        leftDepth.path = leftDepthPath
        leftDepth.fillColor = UIColor(red: 0.55, green: 0.38, blue: 0.22, alpha: 1.0)  // Darker shadow side
        leftDepth.strokeColor = UIColor(red: 0.4, green: 0.25, blue: 0.15, alpha: 1.0)
        leftDepth.lineWidth = 1
        leftDepth.zPosition = 1
        bookshelf.addChild(leftDepth)
        
        // Right side panel - properly aligned and connected to shelves
        let rightPanel = SKShapeNode()
        let rightPath = CGMutablePath()
        // Front face
        rightPath.move(to: CGPoint(x: width / 2 - wallThickness/2, y: -height / 2))
        rightPath.addLine(to: CGPoint(x: width / 2 - wallThickness/2, y: height / 2))
        rightPath.addLine(to: CGPoint(x: width / 2 + wallThickness/2, y: height / 2))
        rightPath.addLine(to: CGPoint(x: width / 2 + wallThickness/2, y: -height / 2))
        rightPath.closeSubpath()
        
        rightPanel.path = rightPath
        rightPanel.fillColor = UIColor(red: 0.65, green: 0.45, blue: 0.25, alpha: 1.0)  // Same medium wood color
        rightPanel.strokeColor = UIColor(red: 0.4, green: 0.25, blue: 0.15, alpha: 1.0)
        rightPanel.lineWidth = 1.5
        rightPanel.zPosition = 6  // Higher than shelves to render over them
        bookshelf.addChild(rightPanel)
        
        // Right panel 3D depth side
        let rightDepth = SKShapeNode()
        let rightDepthPath = CGMutablePath()
        rightDepthPath.move(to: CGPoint(x: width / 2 + wallThickness/2, y: height / 2))
        rightDepthPath.addLine(to: CGPoint(x: width / 2 + wallThickness/2, y: -height / 2))
        rightDepthPath.addLine(to: CGPoint(x: width / 2 + wallThickness/2 + depthOffset, y: -height / 2 + depthOffset))
        rightDepthPath.addLine(to: CGPoint(x: width / 2 + wallThickness/2 + depthOffset, y: height / 2 + depthOffset))
        rightDepthPath.closeSubpath()
        
        rightDepth.path = rightDepthPath
        rightDepth.fillColor = UIColor(red: 0.55, green: 0.38, blue: 0.22, alpha: 1.0)  // Darker shadow side
        rightDepth.strokeColor = UIColor(red: 0.4, green: 0.25, blue: 0.15, alpha: 1.0)
        rightDepth.lineWidth = 1
        rightDepth.zPosition = 5  // Higher than shelves
        bookshelf.addChild(rightDepth)
    }
    
    private func createRealisticShelf(width: CGFloat, y: CGFloat, depth: CGFloat) -> SKNode {
        let shelf = SKNode()
        shelf.position = CGPoint(x: 0, y: y)
        
        // Calculate proper wall connection points to match new wall structure
        let wallThickness: CGFloat = 12  // Match frame wall thickness
        let shelfThickness: CGFloat = 8   // Slightly thinner shelves
        let depthOffset: CGFloat = 15     // Match frame depth effect
        
        // Shelf extends INTO the walls for seamless connection
        let wallOverlap: CGFloat = 8  // How much shelf extends into wall thickness
        
        // Shelf top surface - extends into walls for seamless connection
        let shelfTop = SKShapeNode()
        let topPath = CGMutablePath()
        topPath.move(to: CGPoint(x: -width / 2 - wallThickness/2 - wallOverlap, y: shelfThickness / 2))
        topPath.addLine(to: CGPoint(x: width / 2 + wallThickness/2 + wallOverlap, y: shelfThickness / 2))
        topPath.addLine(to: CGPoint(x: width / 2 + wallThickness/2 + wallOverlap + depthOffset, y: shelfThickness / 2 + depthOffset))
        topPath.addLine(to: CGPoint(x: -width / 2 - wallThickness/2 - wallOverlap + depthOffset, y: shelfThickness / 2 + depthOffset))
        topPath.closeSubpath()
        
        shelfTop.path = topPath
        shelfTop.fillColor = UIColor(red: 0.85, green: 0.65, blue: 0.45, alpha: 1.0)  // Light wood for top
        shelfTop.strokeColor = .clear  // No stroke for seamless blending
        shelfTop.lineWidth = 0
        shelfTop.zPosition = 4  // Above walls to cover connection
        shelf.addChild(shelfTop)
        
        // Shelf front face - extends into walls
        let shelfFront = SKShapeNode()
        let frontPath = CGMutablePath()
        frontPath.move(to: CGPoint(x: -width / 2 - wallThickness/2 - wallOverlap, y: -shelfThickness / 2))
        frontPath.addLine(to: CGPoint(x: width / 2 + wallThickness/2 + wallOverlap, y: -shelfThickness / 2))
        frontPath.addLine(to: CGPoint(x: width / 2 + wallThickness/2 + wallOverlap, y: shelfThickness / 2))
        frontPath.addLine(to: CGPoint(x: -width / 2 - wallThickness/2 - wallOverlap, y: shelfThickness / 2))
        frontPath.closeSubpath()
        
        shelfFront.path = frontPath
        shelfFront.fillColor = UIColor(red: 0.65, green: 0.45, blue: 0.25, alpha: 1.0)  // Match wall color
        shelfFront.strokeColor = .clear  // No stroke for seamless blending
        shelfFront.lineWidth = 0
        shelfFront.zPosition = 3  // Above wall depth, below top
        shelf.addChild(shelfFront)
        
        // Shelf right edge - seamlessly blends with right wall
        let shelfRight = SKShapeNode()
        let rightPath = CGMutablePath()
        rightPath.move(to: CGPoint(x: width / 2 + wallThickness/2 + wallOverlap, y: shelfThickness / 2))
        rightPath.addLine(to: CGPoint(x: width / 2 + wallThickness/2 + wallOverlap, y: -shelfThickness / 2))
        rightPath.addLine(to: CGPoint(x: width / 2 + wallThickness/2 + wallOverlap + depthOffset, y: -shelfThickness / 2 + depthOffset))
        rightPath.addLine(to: CGPoint(x: width / 2 + wallThickness/2 + wallOverlap + depthOffset, y: shelfThickness / 2 + depthOffset))
        rightPath.closeSubpath()
        
        shelfRight.path = rightPath
        shelfRight.fillColor = UIColor(red: 0.55, green: 0.38, blue: 0.22, alpha: 1.0)  // Shadow side
        shelfRight.strokeColor = .clear  // No stroke for seamless blending
        shelfRight.lineWidth = 0
        shelfRight.zPosition = 2  // Below front face
        shelf.addChild(shelfRight)
        
        // Shelf left edge - seamlessly blends with left wall
        let shelfLeft = SKShapeNode()
        let leftPath = CGMutablePath()
        leftPath.move(to: CGPoint(x: -width / 2 - wallThickness/2 - wallOverlap, y: -shelfThickness / 2))
        leftPath.addLine(to: CGPoint(x: -width / 2 - wallThickness/2 - wallOverlap, y: shelfThickness / 2))
        leftPath.addLine(to: CGPoint(x: -width / 2 - wallThickness/2 - wallOverlap + depthOffset, y: shelfThickness / 2 + depthOffset))
        leftPath.addLine(to: CGPoint(x: -width / 2 - wallThickness/2 - wallOverlap + depthOffset, y: -shelfThickness / 2 + depthOffset))
        leftPath.closeSubpath()
        
        shelfLeft.path = leftPath
        shelfLeft.fillColor = UIColor(red: 0.60, green: 0.42, blue: 0.24, alpha: 1.0)  // Medium shadow side
        shelfLeft.strokeColor = .clear  // No stroke for seamless blending
        shelfLeft.lineWidth = 0
        shelfLeft.zPosition = 2  // Below front face, same as right edge
        shelf.addChild(shelfLeft)
        
        // Physics body for shelf - properly sized to match visual shelf
        let shelfPhysics = SKSpriteNode(color: .clear, size: CGSize(width: width + wallThickness, height: shelfThickness))
        shelfPhysics.physicsBody = SKPhysicsBody(rectangleOf: shelfPhysics.size)
        shelfPhysics.physicsBody?.isDynamic = false
        shelfPhysics.physicsBody?.friction = 0.05  // Low friction for tilt mechanics
        shelfPhysics.physicsBody?.restitution = 0.2  // Low bounce
        shelfPhysics.physicsBody?.categoryBitMask = PhysicsCategories.shelf
        shelfPhysics.physicsBody?.contactTestBitMask = PhysicsCategories.tile
        shelfPhysics.physicsBody?.collisionBitMask = PhysicsCategories.tile
        shelf.addChild(shelfPhysics)
        
        return shelf
    }
    
    private func createTiles() {
        // Clear existing tiles
        tiles.forEach { $0.removeFromParent() }
        tiles.removeAll()
        
        // Clear existing score tile
        scoreTile?.removeFromParent()
        scoreTile = nil
        languageTile?.removeFromParent()
        languageTile = nil
        
        // Clear existing theme tiles
        themeTiles.forEach { $0.removeFromParent() }
        themeTiles.removeAll()
        
        // Convert any remaining new_discovery_emoji tiles to collectible_emoji FIRST
        // This ensures discovery detection works correctly in subsequent games
        convertNewDiscoveriesToCollectibles()
        
        // Age all existing emoji tiles by one game and cleanup old ones
        incrementEmojiTileAges()
        cleanupOldEmojiTiles()
        
        // Age all existing information tiles by one game and cleanup old ones
        incrementInformationTileAges()
        cleanupOldInformationTiles()
        
        // Don't apply glow to existing tiles - only to newly dropped ones
        
        // Clear newly dropped emoji tiles list for new game (unless celebration is running)
        if !disableImmediateEmojiEffects {
            newlyDroppedEmojiTiles.removeAll()
            DebugLogger.shared.ui("🔄 NEW GAME: Cleared newly dropped emoji tiles list for normal game start")
        } else {
            DebugLogger.shared.ui("🎭 CELEBRATION: Preserving newly dropped tiles list during celebration (\(newlyDroppedEmojiTiles.count) tiles)")
        }
        
        // Don't create tiles if we're in noPhrasesAvailable state or have no letters
        if gameModel.gameState == .noPhrasesAvailable || gameModel.scrambledLetters.isEmpty {
            DebugLogger.shared.ui("⚠️ createTiles: Skipping tile creation - no phrases available or no letters")
            return
        }
        
        // Create tiles for current sentence
        let letters = gameModel.scrambledLetters
        let baseTileSize: CGFloat = 40  // Original tile size
        let tileSize = CGSize(width: baseTileSize * PhysicsGameScene.componentScaleFactor, 
                             height: baseTileSize * PhysicsGameScene.componentScaleFactor)
        
        // Calculate spawn area at top center for rain effect
        let spawnY = size.height * 0.9  // Near top of screen
        let spawnWidth = size.width * 0.4  // Narrower area for center clustering
        
        // Create tiles with staggered delays for rain effect
        for (index, letter) in letters.enumerated() {
            let delay = Double(index) * 0.3  // 300ms delay between each tile
            
            let spawnAction = SKAction.run { [weak self] in
                guard let self = self else { return }
                
                let tile = LetterTile(letter: letter, size: tileSize)
                
                // Random position near top center
                let randomX = CGFloat.random(in: -spawnWidth/2...spawnWidth/2)
                let baseX = self.size.width / 2 + randomX
                let randomYOffset = CGFloat.random(in: -20...20)
                let position = CGPoint(x: baseX, y: spawnY + randomYOffset)
                
                tile.position = position
                
                // Add random rotation for visual variety
                tile.zRotation = CGFloat.random(in: -0.3...0.3)
                
                self.tiles.append(tile)
                self.addChild(tile)
                
                print("Spawned tile '\(letter)' at \(position) with delay \(delay)s")
            }
            
            let delayAction = SKAction.wait(forDuration: delay)
            let sequence = SKAction.sequence([delayAction, spawnAction])
            
            run(sequence)
        }
        
        // Handle "no phrases" state - spawn information tile instead
        if gameModel.gameState == .noPhrasesAvailable {
            print("📋 NO_PHRASES: Spawning information tile instead of game tiles")
            
            // Spawn the "no phrases" information tile
            let noPhrasesMessage = "No more phrases. Try again later."
            spawnMessageTile(message: noPhrasesMessage)
            
            print("✅ NO_PHRASES: Information tile spawned successfully")
            return
        }
        
        // Create score tile - rectangular and falls down like other tiles
        let baseScoreTileWidth: CGFloat = 100  // Original score tile width
        let baseScoreTileHeight: CGFloat = 40  // Original score tile height  
        let scoreTileSize = CGSize(width: baseScoreTileWidth * PhysicsGameScene.componentScaleFactor, 
                                  height: baseScoreTileHeight * PhysicsGameScene.componentScaleFactor)
        scoreTile = ScoreTile(size: scoreTileSize)
        
        // Position score tile to fall from the right side
        let scoreSpawnX = size.width * 0.8  // Right side
        let scoreSpawnY = size.height * 0.95  // Near top
        scoreTile?.position = CGPoint(x: scoreSpawnX, y: scoreSpawnY)
        
        // Add slight rotation for visual interest
        scoreTile?.zRotation = CGFloat.random(in: -0.2...0.2)
        
        // Update score and add to scene with delay
        if let scoreTile = scoreTile {
            let currentScore = calculateCurrentScore()
            let difficulty = gameModel.phraseDifficulty
            scoreTile.updateScore(currentScore, difficulty: difficulty)
            
            let delayAction = SKAction.wait(forDuration: 1.0)  // Wait 1 second after tiles
            let addAction = SKAction.run { [weak self] in
                self?.addChild(scoreTile)
                print("Score tile spawned with score: \(currentScore) (difficulty: \(difficulty))")
            }
            
            run(SKAction.sequence([delayAction, addAction]))
        }
        
        // Create language tile - same size as letter tiles  
        let languageTileSize = CGSize(width: baseTileSize * PhysicsGameScene.componentScaleFactor, 
                                     height: baseTileSize * PhysicsGameScene.componentScaleFactor)
        let currentLanguage = getCurrentPhraseLanguage()
        languageTile = LanguageTile(language: currentLanguage, size: languageTileSize)
        
        // Position language tile to fall from the left side
        let languageSpawnX = size.width * 0.2  // Left side
        let languageSpawnY = size.height * 0.95  // Near top
        languageTile?.position = CGPoint(x: languageSpawnX, y: languageSpawnY)
        
        // Add slight rotation for visual interest
        languageTile?.zRotation = CGFloat.random(in: -0.2...0.2)
        
        // Add language tile to scene with delay
        if let languageTile = languageTile {
            let delayAction = SKAction.wait(forDuration: 1.2)  // Wait 1.2 seconds (slightly after score tile)
            let addAction = SKAction.run { [weak self] in
                self?.addChild(languageTile)
                print("Language tile spawned with language: \(currentLanguage)")
            }
            
            run(SKAction.sequence([delayAction, addAction]))
        }
    }
    
    private func calculateCurrentScore(hintsUsed: Int? = nil) -> Int {
        let actualHintsUsed = hintsUsed ?? gameModel.hintsUsed
        let baseScore = ScoreCalculator.shared.applyHintPenalty(baseScore: gameModel.phraseDifficulty, hintsUsed: actualHintsUsed)
        // Include emoji points for real-time score display
        return baseScore + gameModel.emojiPointsThisPhrase
    }
    
    private func getCurrentPhraseLanguage() -> String {
        return gameModel.currentCustomPhrase?.language ?? "en"
    }
    
    func updateScoreTile(hintsUsed: Int? = nil) {
        let currentScore = calculateCurrentScore(hintsUsed: hintsUsed)
        let actualHintsUsed = hintsUsed ?? gameModel.hintsUsed
        let difficulty = gameModel.phraseDifficulty
        scoreTile?.updateScore(currentScore, difficulty: difficulty)
        print("Score tile updated to: \(currentScore) (difficulty: \(difficulty), hints: \(actualHintsUsed))")
        
        // Debug logging for difficulty issues
        let actualDifficulty = NetworkManager.analyzeDifficultyClientSide(phrase: gameModel.currentSentence, language: "en").score
        print("🔍 DEBUG: SCORE_TILE_UPDATE: phrase='\(gameModel.currentSentence)' displayed_difficulty=\(difficulty) actual_difficulty=\(actualDifficulty) current_score=\(currentScore)")
        
        // Send debug to server
        Task {
            await DebugLogger.shared.sendToServer("SCORE_TILE_UPDATE: phrase='\(gameModel.currentSentence)' displayed_difficulty=\(difficulty) actual_difficulty=\(actualDifficulty) current_score=\(currentScore)")
        }
        
        // Special logging for 100-point bugs
        if difficulty == 100 {
            print("🔍 DEBUG: BUG_100_POINTS: '\(gameModel.currentSentence)' showing 100pts but should be \(actualDifficulty)")
            Task {
                await DebugLogger.shared.sendToServer("BUG_100_POINTS: '\(gameModel.currentSentence)' showing 100pts but should be \(actualDifficulty)")
            }
        }
    }
    
    @objc private func handleEmojiPointsChanged(_ notification: Notification) {
        // Update score tile in real-time when emoji points are added
        print("🎯 REAL-TIME: Emoji points changed, updating score tile")
        updateScoreTile()
    }
    
    func queueEmojiEffectForCleanup(rarity: EmojiRarity, points: Int) {
        let emojiChar = getEmojiForRarity(rarity)
        DebugLogger.shared.ui("⏰ QUEUE: For cheat test only - creating temporary \(rarity.displayName) \(emojiChar) tile for effects")
        // Note: Tile preservation will be handled by normal celebration sequence
        
        // Create a temporary tile with the requested rarity for cheat testing
        let baseTileSize: CGFloat = 40
        let tileSize = CGSize(width: baseTileSize * PhysicsGameScene.componentScaleFactor, 
                            height: baseTileSize * PhysicsGameScene.componentScaleFactor)
        let tempTile = EmojiIconTile(emoji: emojiChar, rarity: rarity, size: tileSize)
        
        // Position above screen for rain effect (same as other emoji tiles)
        let spawnY = size.height * 0.9  // High above visible area
        let spawnWidth = size.width * 0.4  // Center clustering
        let randomX = CGFloat.random(in: -spawnWidth/2...spawnWidth/2)
        let baseX = size.width / 2 + randomX
        let randomYOffset = CGFloat.random(in: -20...20)
        tempTile.position = CGPoint(x: baseX, y: spawnY + randomYOffset)
        
        // Add random rotation for visual variety
        tempTile.zRotation = CGFloat.random(in: -0.3...0.3)
        tempTile.name = "cheat_test_tile"
        addChild(tempTile)
        newlyDroppedEmojiTiles.append(tempTile)
        
        // Give the tile initial downward velocity for falling effect
        let giveInitialVelocity = SKAction.run {
            tempTile.physicsBody?.velocity = CGVector(dx: 0, dy: -200)
            tempTile.physicsBody?.applyImpulse(CGVector(dx: 0, dy: -100))
        }
        let delayAction = SKAction.wait(forDuration: 0.1) // Small delay before physics kick-in
        let dropAction = SKAction.sequence([delayAction, giveInitialVelocity])
        tempTile.run(dropAction)
        
        DebugLogger.shared.ui("🎭 CHEAT: Created temporary \(rarity.displayName) tile for testing effects")
        DebugLogger.shared.ui("📍 CHEAT TRACK: Added cheat tile to newly dropped list (total: \(newlyDroppedEmojiTiles.count))")
    }
    
    private func getEmojiForRarity(_ rarity: EmojiRarity) -> String {
        switch rarity {
        case .legendary: return "👑"
        case .mythic: return "🌟"
        case .epic: return "⚡"
        case .rare: return "💎"
        case .uncommon: return "✨"
        case .common: return "⭐"
        }
    }
    
    private func getPointsForRarity(_ rarity: EmojiRarity) -> Int {
        switch rarity {
        case .legendary: return 500
        case .mythic: return 200
        case .epic: return 100
        case .rare: return 25
        case .uncommon: return 5
        case .common: return 1
        }
    }
    
    private func bounceScoreTile() {
        guard let scoreTile = scoreTile else { 
            print("⚠️ BOUNCE: No score tile found")
            return 
        }
        
        guard let physicsBody = scoreTile.physicsBody else {
            print("⚠️ BOUNCE: Score tile has no physics body")
            return
        }
        
        // Apply forceful upward impulse with random angle
        let baseForce: CGFloat = 400 // Strong upward force
        let randomAngle = CGFloat.random(in: -0.5...0.5) // Random angle in radians (roughly ±30 degrees)
        
        let dx = baseForce * sin(randomAngle)
        let dy = baseForce * cos(randomAngle)
        
        let randomImpulse = CGVector(dx: dx, dy: dy)
        physicsBody.applyImpulse(randomImpulse)
        
        print("💥 BOUNCE: Applied physics impulse to score tile")
    }
    
    func updateLanguageTile() {
        let newLanguage = getCurrentPhraseLanguage()
        languageTile?.updateFlag(language: newLanguage)
        print("Language tile updated to: \(newLanguage)")
    }
    
    
    
    func spawnMessageTile(message: String) {
        // Create new message tile - width calculated based on text length
        let newMessageTile = MessageTile(message: message, sceneSize: size)
        
        // Position message tile to fall from the left side (opposite of score tile)
        // Add some randomness to X position to avoid stacking
        let baseSpawnX = size.width * 0.2  // Left side base position
        let randomOffsetX = Float.random(in: -50...50)  // Random offset
        let messageSpawnX = baseSpawnX + CGFloat(randomOffsetX)
        let messageSpawnY = size.height * 0.95  // Near top
        newMessageTile.position = CGPoint(x: messageSpawnX, y: messageSpawnY)
        
        // Add small random rotation for natural look
        let randomRotation = Float.random(in: -0.2...0.2)
        newMessageTile.zRotation = CGFloat(randomRotation)
        
        // Add to scene and track in array
        addChild(newMessageTile)
        messageTiles.append(newMessageTile)
        
        print("Message tile spawned with text: \(message) (Total: \(messageTiles.count))")
    }
    
    func spawnThemeTile(theme: String) {
        let newThemeTile = ThemeInformationTile(theme: theme, size: CGSize(width: 120, height: 60))
        newThemeTile.position = CGPoint(x: size.width * 0.7, y: size.height * 0.95)
        
        // Add to scene and track in array
        addChild(newThemeTile)
        themeTiles.append(newThemeTile)
        
        print("Theme tile spawned with theme: \(theme) (Total: \(themeTiles.count))")
    }
    
    func updateGravity(from gravity: CMAcceleration) {
        // Determine the desired quake state based on device tilt
        let desiredState: QuakeState
        if gravity.z > 0.29 {
            desiredState = .superQuake
        } else if gravity.z > 0.10 {
            desiredState = .normal
        } else {
            desiredState = .none
        }
    
        // Transition to the new state if it's different
        if desiredState != self.quakeState {
            switch desiredState {
            case .none:
                stopShelfShaking()
            case .normal:
                stopShelfShaking() // Stop any previous shaking before starting new one
                startShelfShaking()
            case .superQuake:
                stopShelfShaking() // Stop any previous shaking
                startSuperShelfShaking()
            }
            self.quakeState = desiredState
        }

        // Always maintain normal gravity
        physicsWorld.gravity = CGVector(dx: 0, dy: -30.0) // Much stronger gravity for heavy feel

        // ALWAYS show tile positions for debugging (not just when falling)
    }
    
    // Debug function to manually trigger quake states
    func debugTriggerQuake(state: QuakeState) {
        print("🧪 DEBUG: Manually triggering quake state: \(state)")
        switch state {
        case .none:
            stopShelfShaking()
        case .normal:
            stopShelfShaking()
            startShelfShaking()
        case .superQuake:
            stopShelfShaking()
            startSuperShelfShaking()
        }
        self.quakeState = state
        let floorY = size.height * 0.25
        
        // Remove any existing status markers from tiles
        for tile in tiles {
            tile.childNode(withName: "status_marker")?.removeFromParent()
        }
        
        if self.quakeState != .none {
            // Apply forces to tiles on shelves only
            
            for (index, tile) in tiles.enumerated() {
                let tileY = tile.position.y
                let isOnShelf = tileY > (floorY + 100)
                let shelfStatus = isOnShelf ? "📚 ON SHELF" : "🏠 ON FLOOR"
                
                print("💥 Tile \(index): \(tile.letter) at Y=\(String(format: "%.1f", tileY)) - \(shelfStatus)")
                
                guard let physicsBody = tile.physicsBody else {
                    print("❌ Tile \(index) has NO physics body!")
                    continue
                }
                
                // Only apply falling forces to tiles that are actually on shelves
                if isOnShelf {
                    // Temporarily reduce damping for falling
                    physicsBody.linearDamping = 0.1
                    physicsBody.angularDamping = 0.1
                    
                    if self.quakeState == .superQuake {
                        // Apply VIOLENT forces
                        physicsBody.applyForce(CGVector(dx: 0, dy: -4000))
                        physicsBody.applyImpulse(CGVector(dx: CGFloat.random(in: -200...200), dy: -400))
                    } else {
                        // Apply moderate forces so tiles don't vanish off screen
                        physicsBody.applyForce(CGVector(dx: 0, dy: -2000))
                        physicsBody.applyImpulse(CGVector(dx: CGFloat.random(in: -100...100), dy: -200))
                    }
                }
            }
            
            // Make all surfaces completely frictionless
            enumerateChildNodes(withName: "//*") { node, _ in
                if let physicsBody = node.physicsBody, !physicsBody.isDynamic {
                    physicsBody.friction = 0.0
                }
            }
        } else {
            // Restore normal friction when not falling
            enumerateChildNodes(withName: "//*") { node, _ in
                if let physicsBody = node.physicsBody, !physicsBody.isDynamic {
                    physicsBody.friction = 0.05
                }
            }
        }
    }
    
    func triggerQuake() {
        triggerQuakeWithDuration(3.0)
    }
    
    func triggerHint() {
        let targetWords = gameModel.getExpectedWords()
        let numberOfWords = targetWords.count
        
        // Light up the same number of shelves as there are words in the target phrase
        let shelvesToLight = min(numberOfWords, shelves.count)
        
        for i in 0..<shelvesToLight {
            lightUpShelf(shelves[i], wordIndex: i)
        }
        
    }
    
    private func lightUpShelf(_ shelf: SKNode, wordIndex: Int) {
        // Remove any existing highlights
        shelf.childNode(withName: "hint_glow")?.removeFromParent()
        
        // Get shelf dimensions that match the actual shelf creation
        let wallThickness: CGFloat = 12
        let wallOverlap: CGFloat = 8
        let baseShelfWidthRatio: CGFloat = 0.75  // Original shelf width ratio
        let shelfWidth: CGFloat = size.width * baseShelfWidthRatio * PhysicsGameScene.componentScaleFactor - 20
        let shelfThickness: CGFloat = 8
        let depthOffset: CGFloat = 15
        
        // Enhanced, more vibrant color palette for better visibility
        let hintColors: [UIColor] = [
            UIColor(red: 1.0, green: 0.8, blue: 0.4, alpha: 1.0),   // Bright warm orange (1st word)
            UIColor(red: 0.6, green: 1.0, blue: 0.6, alpha: 1.0),   // Vibrant mint green (2nd word)
            UIColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 1.0),   // Bright sky blue (3rd word)
            UIColor(red: 0.9, green: 0.6, blue: 1.0, alpha: 1.0)   // Bright lavender (4th word)
        ]
        
        let colorIndex = wordIndex % hintColors.count
        let hintColor = hintColors[colorIndex]
        
        // Create a container for all glow elements
        let glowContainer = SKNode()
        glowContainer.name = "hint_glow"
        
        // 1. Create glow for the shelf top surface (matches the isometric top)
        let topGlow = SKShapeNode()
        let topPath = CGMutablePath()
        topPath.move(to: CGPoint(x: -shelfWidth / 2 - wallThickness/2 - wallOverlap, y: shelfThickness / 2))
        topPath.addLine(to: CGPoint(x: shelfWidth / 2 + wallThickness/2 + wallOverlap, y: shelfThickness / 2))
        topPath.addLine(to: CGPoint(x: shelfWidth / 2 + wallThickness/2 + wallOverlap + depthOffset, y: shelfThickness / 2 + depthOffset))
        topPath.addLine(to: CGPoint(x: -shelfWidth / 2 - wallThickness/2 - wallOverlap + depthOffset, y: shelfThickness / 2 + depthOffset))
        topPath.closeSubpath()
        
        topGlow.path = topPath
        topGlow.fillColor = hintColor.withAlphaComponent(0.8)  // Much more prominent
        topGlow.strokeColor = hintColor.withAlphaComponent(1.0)
        topGlow.lineWidth = 3
        topGlow.zPosition = 5  // Above the actual shelf
        
        // 2. Create glow for the shelf front face
        let frontGlow = SKShapeNode()
        let frontPath = CGMutablePath()
        frontPath.move(to: CGPoint(x: -shelfWidth / 2 - wallThickness/2 - wallOverlap, y: -shelfThickness / 2))
        frontPath.addLine(to: CGPoint(x: shelfWidth / 2 + wallThickness/2 + wallOverlap, y: -shelfThickness / 2))
        frontPath.addLine(to: CGPoint(x: shelfWidth / 2 + wallThickness/2 + wallOverlap, y: shelfThickness / 2))
        frontPath.addLine(to: CGPoint(x: -shelfWidth / 2 - wallThickness/2 - wallOverlap, y: shelfThickness / 2))
        frontPath.closeSubpath()
        
        frontGlow.path = frontPath
        frontGlow.fillColor = hintColor.withAlphaComponent(0.75)  // Much more prominent
        frontGlow.strokeColor = hintColor.withAlphaComponent(0.9)
        frontGlow.lineWidth = 3
        frontGlow.zPosition = 4  // Just above the front face
        
        // 3. Create glow for the shelf right edge (3D depth side)
        let rightGlow = SKShapeNode()
        let rightPath = CGMutablePath()
        rightPath.move(to: CGPoint(x: shelfWidth / 2 + wallThickness/2 + wallOverlap, y: shelfThickness / 2))
        rightPath.addLine(to: CGPoint(x: shelfWidth / 2 + wallThickness/2 + wallOverlap, y: -shelfThickness / 2))
        rightPath.addLine(to: CGPoint(x: shelfWidth / 2 + wallThickness/2 + wallOverlap + depthOffset, y: -shelfThickness / 2 + depthOffset))
        rightPath.addLine(to: CGPoint(x: shelfWidth / 2 + wallThickness/2 + wallOverlap + depthOffset, y: shelfThickness / 2 + depthOffset))
        rightPath.closeSubpath()
        
        rightGlow.path = rightPath
        rightGlow.fillColor = hintColor.withAlphaComponent(0.7)  // Much more prominent
        rightGlow.strokeColor = hintColor.withAlphaComponent(0.85)
        rightGlow.lineWidth = 3
        rightGlow.zPosition = 3
        
        // Add all glow elements to container
        glowContainer.addChild(frontGlow)
        glowContainer.addChild(rightGlow)
        glowContainer.addChild(topGlow)
        
        // First: Enhanced pulsating intro for better attention
        let pulseBright = SKAction.fadeAlpha(to: 1.0, duration: 0.25)
        let pulseDim = SKAction.fadeAlpha(to: 0.3, duration: 0.25)
        let pulseSequence = SKAction.sequence([pulseBright, pulseDim])
        let pulsatingIntro = SKAction.repeat(pulseSequence, count: 5)  // 5 pulses = ~2.5 seconds
        
        // Then: settle into more prominent breathing
        let breatheOut = SKAction.fadeAlpha(to: 0.5, duration: 2.0)
        let breatheIn = SKAction.fadeAlpha(to: 0.9, duration: 2.0)
        let breathing = SKAction.sequence([breatheOut, breatheIn])
        let repeatBreathing = SKAction.repeatForever(breathing)
        
        // Combine: pulsating intro then continuous breathing
        let fullAnimation = SKAction.sequence([pulsatingIntro, repeatBreathing])
        glowContainer.run(fullAnimation)
        
        // Add glow container to shelf
        shelf.addChild(glowContainer)
        
    }
    
    private func clearAllHints() {
        // Clear shelf highlights
        for shelf in shelves {
            // Remove the glow container which contains all glow elements
            shelf.childNode(withName: "hint_glow")?.removeFromParent()
        }
        
        // Clear tile highlights and restore original colors
        clearTileHints()
    }
    
    private func clearTileHints() {
        // Clear tile highlights and restore original colors
        for tile in tiles {
            // Restore original front face color for LetterTile objects
            tile.restoreFrontFace()
        }
    }
    
    // Public hint methods callable from HintButtonView
    func showHint1() {
        // Hint 1: Highlight all shelves to show word count
        // Only clear tile hints, not shelf hints
        clearTileHints()
        let wordCount = gameModel.getExpectedWords().count
        
        let shelvesToHighlight = min(wordCount, shelves.count)
        
        for i in 0..<shelvesToHighlight {
            lightUpShelf(shelves[i], wordIndex: i)
        }
        
        // Show theme tile on first hint if phrase has a theme
        print("🎯 THEME DEBUG: hintsUsed=\(gameModel.hintsUsed), currentPhrase=\(gameModel.currentCustomPhrase?.content ?? "nil"), theme=\(gameModel.currentCustomPhrase?.theme ?? "nil")")
        if gameModel.hintsUsed == 0, let theme = gameModel.currentCustomPhrase?.theme, !theme.isEmpty {
            print("🎯 THEME: Spawning theme tile with theme: \(theme)")
            spawnThemeTile(theme: theme)
        } else {
            print("🎯 THEME: Not spawning tile - hintsUsed=\(gameModel.hintsUsed), theme=\(gameModel.currentCustomPhrase?.theme ?? "nil")")
        }
        
        // Apply bounce effect when hint is used
        bounceScoreTile()
    }
    
    func showHint2() {
        // Hint 2: Highlight first letter tiles
        // Only clear tile hints, preserve shelf highlights from Hint 1
        clearTileHints()
        highlightFirstLetterTiles()
        
        // Apply bounce effect when hint is used
        bounceScoreTile()
    }
    
    func showHint3() {
        // Hint 3: Don't clear tile highlights - preserve blue highlighting from Hint 2
        // Only show text hint, maintain all visual hints from previous levels
        
        // Apply bounce effect when hint is used
        bounceScoreTile()
    }
    
    private func joltPlayingField() {
        // Apply brief upward impulse to all tiles to create jolt effect
        let impulseStrength: CGFloat = 64.0  // Reduced by another 20% (80 * 0.8 = 64)
        
        for tile in allRespawnableTiles {
            // Apply random upward impulse with slight horizontal variation
            let horizontalVariation = CGFloat.random(in: -12...12)  // Reduced by 20% (15 * 0.8 = 12)
            let verticalImpulse = impulseStrength + CGFloat.random(in: -12...12)  // Reduced by 20% (15 * 0.8 = 12)
            let impulse = CGVector(dx: horizontalVariation, dy: verticalImpulse)
            
            tile.physicsBody?.applyImpulse(impulse)
            
            // Also add slight random angular impulse for rotation
            let angularImpulse = CGFloat.random(in: -0.4...0.4)  // Reduced by 20% (0.5 * 0.8 = 0.4)
            tile.physicsBody?.applyAngularImpulse(angularImpulse)
        }
        
        // Add bookshelf jolt animation
        joltBookshelf()
        
        // Trigger UI button jolt animation
        onJolt?()
        
        // Trigger haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred(intensity: 1.0)
        
        print("⚡ JOLT: Applied impulse to \(allRespawnableTiles.count) tiles, bookshelf, UI buttons, and haptic feedback")
    }
    
    private func joltBookshelf() {
        // Don't jolt bookshelf if it has already been animated (dropped)
        if hasBookshelfAnimated || bookshelf.hasActions() || bookshelf.physicsBody != nil {
            return
        }
        
        // Stop any existing jolt animation to prevent accumulation
        bookshelf.removeAction(forKey: "shelfJolt")
        
        // Set jolting flag to prevent collision detection during animation
        isBookshelfJolting = true
        
        // Reset to original position first
        bookshelf.position = bookshelfOriginalPosition
        
        // Create brief shake animation using absolute positions
        let shakeDistance: CGFloat = 8.0
        let shakeDuration: TimeInterval = 0.1
        
        // Calculate shake positions relative to original position
        let upPosition = CGPoint(x: bookshelfOriginalPosition.x, y: bookshelfOriginalPosition.y + shakeDistance)
        let downPosition = CGPoint(x: bookshelfOriginalPosition.x, y: bookshelfOriginalPosition.y - shakeDistance)
        let rightPosition = CGPoint(x: bookshelfOriginalPosition.x + shakeDistance * 0.5, y: bookshelfOriginalPosition.y)
        let leftPosition = CGPoint(x: bookshelfOriginalPosition.x - shakeDistance * 0.5, y: bookshelfOriginalPosition.y)
        
        // Create shake sequence using absolute positions
        let shakeSequence = SKAction.sequence([
            SKAction.move(to: upPosition, duration: shakeDuration),
            SKAction.move(to: downPosition, duration: shakeDuration),
            SKAction.move(to: rightPosition, duration: shakeDuration),
            SKAction.move(to: leftPosition, duration: shakeDuration),
            SKAction.move(to: bookshelfOriginalPosition, duration: shakeDuration)  // Always return to original
        ])
        
        // Apply to bookshelf with unique key
        bookshelf.run(shakeSequence, withKey: "shelfJolt")
        
        // Force physics body positions to sync with visual positions after animation
        let delayAction = SKAction.wait(forDuration: 0.5)  // Wait for animation to complete
        let updateAction = SKAction.run {
            self.forcePhysicsBodySync()
            self.isBookshelfJolting = false  // Re-enable collision detection
        }
        let sequenceAction = SKAction.sequence([delayAction, updateAction])
        self.run(sequenceAction)
        
    }
    
    private func forcePhysicsBodySync() {
        // Don't reset bookshelf if it's in animation or physics mode
        if !bookshelf.hasActions() && bookshelf.physicsBody == nil {
            // Reset bookshelf to original position first
            bookshelf.position = bookshelfOriginalPosition
            // Reset the animation flag for new game
            hasBookshelfAnimated = false
        }
        
        // Reset all shelf positions to their original positions
        for shelf in shelves {
            if let originalPosition = shelfOriginalPositions[shelf] {
                shelf.position = originalPosition
            }
            
            // Reset physics bodies to their original world positions
            for child in shelf.children {
                if let physicsNode = child as? SKSpriteNode, let originalWorldPosition = physicsBodyOriginalPositions[physicsNode] {
                    // Convert from world coordinates back to shelf coordinates
                    let shelfPosition = shelf.convert(originalWorldPosition, from: self)
                    physicsNode.position = shelfPosition
                }
            }
        }
        
        print("📚 PHYSICS: Reset bookshelf, shelf positions, and physics body positions")
    }
    
    
    private func highlightFirstLetterTiles() {
        let expectedWords = gameModel.getExpectedWords()
        var firstLettersNeeded: [Character] = []
        
        // Collect first letter of each word
        for word in expectedWords {
            if let firstChar = word.first {
                let lowercaseFirst = firstChar.lowercased().first!
                firstLettersNeeded.append(lowercaseFirst)
            }
        }
        
        
        // Find and highlight matching tiles (only highlight one tile per needed first letter)
        var highlightedCount = 0
        var remainingLetters = firstLettersNeeded
        
        for tile in tiles {
            // Skip if we've found all needed letters
            if remainingLetters.isEmpty {
                break
            }
            
            // Use the LetterTile's letter property directly
            let tileChar = tile.letter.lowercased().first!
                
                
            // Check if this tile contains a first letter we still need
            if let index = remainingLetters.firstIndex(of: tileChar) {
                highlightTile(tile)
                highlightedCount += 1
                // Remove this letter from remaining list to avoid highlighting duplicates
                remainingLetters.remove(at: index)
            }
        }
        
    }
    
    private func highlightTile(_ tile: LetterTile) {
        // Change the front face color to blue for LetterTile objects
        tile.highlightFrontFace()
    }
    
    private func triggerQuakeWithDuration(_ duration: TimeInterval) {
        // Manually trigger quake effect for debugging
        
        // Cancel any existing quake end action
        if quakeEndAction != nil {
            removeAction(forKey: "quakeEnd")
            removeAction(forKey: "shelfShaking")
            removeAction(forKey: "shelfWiggling")
        }
        
        if quakeState == .none {
            // Start new quake
            self.quakeState = .normal
            startShelfShaking()
        } else {
            // Extend existing quake
        }
        
        // Reset to normal after specified duration
        let resetAction = SKAction.run {
            self.stopShelfShaking()
            self.quakeState = .none
            self.quakeEndAction = nil
        }
        let waitAction = SKAction.wait(forDuration: duration)
        let sequence = SKAction.sequence([waitAction, resetAction])
        quakeEndAction = sequence
        run(sequence, withKey: "quakeEnd")
    }
    
    
    private func startShelfShaking() {
        print("📳 Starting violent shelf shaking and wiggling animation")
        
        // Create violent shaking motion for the bookshelf
        let shakeIntensity: CGFloat = 12.0  // Even stronger shaking
        let shakeDuration: TimeInterval = 0.04  // Very fast shaking
        
        let shakeLeft = SKAction.moveBy(x: -shakeIntensity, y: 0, duration: shakeDuration)
        let shakeRight = SKAction.moveBy(x: shakeIntensity * 2, y: 0, duration: shakeDuration)
        let shakeUp = SKAction.moveBy(x: 0, y: shakeIntensity, duration: shakeDuration)
        let shakeDown = SKAction.moveBy(x: 0, y: -shakeIntensity * 2, duration: shakeDuration)
        let shakeDiagonal1 = SKAction.moveBy(x: shakeIntensity, y: shakeIntensity, duration: shakeDuration)
        let shakeDiagonal2 = SKAction.moveBy(x: -shakeIntensity * 2, y: -shakeIntensity * 2, duration: shakeDuration)
        let returnToCenter = SKAction.moveBy(x: shakeIntensity, y: shakeIntensity, duration: shakeDuration)
        
        let shakeSequence = SKAction.sequence([shakeLeft, shakeRight, shakeUp, shakeDown, shakeDiagonal1, shakeDiagonal2, returnToCenter])
        let repeatShaking = SKAction.repeatForever(shakeSequence)
        
        // Create wiggling rotation motion
        let wiggleIntensity: CGFloat = 0.15  // Rotation in radians (about 8.6 degrees)
        let wiggleDuration: TimeInterval = 0.06
        
        let wiggleLeft = SKAction.rotate(byAngle: -wiggleIntensity, duration: wiggleDuration)
        let wiggleRight = SKAction.rotate(byAngle: wiggleIntensity * 2, duration: wiggleDuration)
        let wiggleCenter = SKAction.rotate(byAngle: -wiggleIntensity, duration: wiggleDuration)
        
        let wiggleSequence = SKAction.sequence([wiggleLeft, wiggleRight, wiggleCenter])
        let repeatWiggling = SKAction.repeatForever(wiggleSequence)
        
        // Apply shaking to bookshelf for visual effect
        bookshelf.run(repeatShaking, withKey: "shelfShaking")
        bookshelf.run(repeatWiggling, withKey: "shelfWiggling")
        
        // Apply random forces to tiles to simulate earthquake effect
        let applyQuakeForces = SKAction.run {
            for tile in self.tiles {
                guard let physicsBody = tile.physicsBody else { continue }
                
                // Apply random forces in all directions (50% reduced violence)
                let forceX = CGFloat.random(in: -25...25)
                let forceY = CGFloat.random(in: -15...40) // Bias upward for dramatic effect
                let force = CGVector(dx: forceX, dy: forceY)
                
                // Apply random impulse to make tiles shake moderately
                let impulseX = CGFloat.random(in: -1...1)
                let impulseY = CGFloat.random(in: -0.5...1.5)
                let impulse = CGVector(dx: impulseX, dy: impulseY)
                
                physicsBody.applyForce(force)
                physicsBody.applyImpulse(impulse)
                
                // Add some random angular velocity for spinning (50% reduced)
                let angularImpulse = CGFloat.random(in: -0.25...0.25)
                physicsBody.applyAngularImpulse(angularImpulse)
            }
        }
        
        // Repeat force application every 0.1 seconds during quake
        let forceInterval = SKAction.wait(forDuration: 0.1)
        let forceSequence = SKAction.sequence([applyQuakeForces, forceInterval])
        let repeatForces = SKAction.repeatForever(forceSequence)
        
        run(repeatForces, withKey: "quakeForces")
    }
    
    private func stopShelfShaking() {
        print("📳 Stopping shelf shaking and wiggling animation")
        
        bookshelf.removeAction(forKey: "shelfShaking")
        bookshelf.removeAction(forKey: "shelfWiggling")
        
        // Stop applying forces to tiles
        removeAction(forKey: "quakeForces")
        
        // Smoothly return bookshelf to original position and rotation
        let returnToOriginalPosition = SKAction.move(to: bookshelfOriginalPosition, duration: 0.3)
        let returnToOriginalRotation = SKAction.rotate(toAngle: 0, duration: 0.3)
        
        returnToOriginalPosition.timingMode = .easeOut
        returnToOriginalRotation.timingMode = .easeOut
        
        // Run both animations simultaneously
        let returnGroup = SKAction.group([returnToOriginalPosition, returnToOriginalRotation])
        bookshelf.run(returnGroup)
    }
    
    private func startSuperShelfShaking() {
        print("📳 Starting SUPER VIOLENT shelf shaking and wiggling animation")
        
        // Create violent shaking motion for the bookshelf
        let shakeIntensity: CGFloat = 24.0  // Double intensity
        let shakeDuration: TimeInterval = 0.03  // Even faster
        
        let shakeLeft = SKAction.moveBy(x: -shakeIntensity, y: 0, duration: shakeDuration)
        let shakeRight = SKAction.moveBy(x: shakeIntensity * 2, y: 0, duration: shakeDuration)
        let shakeUp = SKAction.moveBy(x: 0, y: shakeIntensity, duration: shakeDuration)
        let shakeDown = SKAction.moveBy(x: 0, y: -shakeIntensity * 2, duration: shakeDuration)
        let shakeDiagonal1 = SKAction.moveBy(x: shakeIntensity, y: shakeIntensity, duration: shakeDuration)
        let shakeDiagonal2 = SKAction.moveBy(x: -shakeIntensity * 2, y: -shakeIntensity * 2, duration: shakeDuration)
        let returnToCenter = SKAction.moveBy(x: shakeIntensity, y: shakeIntensity, duration: shakeDuration)
        
        let shakeSequence = SKAction.sequence([shakeLeft, shakeRight, shakeUp, shakeDown, shakeDiagonal1, shakeDiagonal2, returnToCenter])
        let repeatShaking = SKAction.repeatForever(shakeSequence)
        
        // Create wiggling rotation motion
        let wiggleIntensity: CGFloat = 0.30  // Double intensity
        let wiggleDuration: TimeInterval = 0.05
        
        let wiggleLeft = SKAction.rotate(byAngle: -wiggleIntensity, duration: wiggleDuration)
        let wiggleRight = SKAction.rotate(byAngle: wiggleIntensity * 2, duration: wiggleDuration)
        let wiggleCenter = SKAction.rotate(byAngle: -wiggleIntensity, duration: wiggleDuration)
        
        let wiggleSequence = SKAction.sequence([wiggleLeft, wiggleRight, wiggleCenter])
        let repeatWiggling = SKAction.repeatForever(wiggleSequence)
        
        // Apply shaking to bookshelf for visual effect
        bookshelf.run(repeatShaking, withKey: "shelfShaking")
        bookshelf.run(repeatWiggling, withKey: "shelfWiggling")
    }
    
    override func update(_ currentTime: TimeInterval) {
        // Track FPS
        frameCount += 1
        if lastFPSUpdateTime == 0 {
            lastFPSUpdateTime = currentTime
        }
        
        // Update FPS every second
        if currentTime - lastFPSUpdateTime >= 1.0 {
            currentFPS = Double(frameCount) / (currentTime - lastFPSUpdateTime)
            frameCount = 0
            lastFPSUpdateTime = currentTime
        }
        
        // Check for tiles that have left the screen and respawn them
        for tile in allRespawnableTiles {
            let margin: CGFloat = 100  // Buffer zone outside screen
            let topMargin: CGFloat = 0   // No margin for top - respawn immediately when above screen
            
            // Check all boundaries with zero tolerance for top boundary
            let isOutOfBounds = tile.position.x < -margin || 
                               tile.position.x > size.width + margin || 
                               tile.position.y < -margin || 
                               tile.position.y > size.height + topMargin  // Respawn immediately when above screen
            
            if isOutOfBounds {
                // Get tile description for logging
                let tileDescription: String
                if let letterTile = tile as? LetterTile {
                    tileDescription = "letter '\(letterTile.letter)'"
                } else if tile is ScoreTile {
                    tileDescription = "score tile"
                } else if tile is MessageTile {
                    tileDescription = "message tile"
                } else if tile is LanguageTile {
                    tileDescription = "language tile"
                } else {
                    tileDescription = "tile"
                }
                
                print("🚨 RESPAWN: \(tileDescription) was out of bounds at (\(tile.position.x), \(tile.position.y)) - screen size: (\(size.width), \(size.height))")
                
                // Respawn tile in center area with some randomness
                let randomX = CGFloat.random(in: size.width * 0.3...size.width * 0.7)
                let randomY = CGFloat.random(in: size.height * 0.4...size.height * 0.6)
                tile.position = CGPoint(x: randomX, y: randomY)
                
                // Reset physics properties
                tile.physicsBody?.velocity = CGVector.zero
                tile.physicsBody?.angularVelocity = 0
                tile.zRotation = CGFloat.random(in: -0.3...0.3)
                
                print("✅ RESPAWN: \(tileDescription) respawned at center: \(tile.position)")
            }
        }
        
        // Update visual appearance for letter tiles only
        for tile in tiles {
            tile.updateVisualForRotation()
        }
    }
    
    func resetGame() {
        print("🔄 Scene resetGame() called")
        
        // Performance monitoring - record tile system performance
        let tileResetStartTime = CACurrentMediaTime()
        print("🧪 PERFORMANCE: Tile reset started at \(tileResetStartTime) with \(tiles.count) existing tiles")
        
        
        // Scene reset debug logging removed to reduce API calls
        
        // Clear any existing celebration or game state
        celebrationText = ""
        
        // Clear hint effects when starting new game
        clearAllHints()
        
        // COMPREHENSIVE CLEANUP: Remove ALL tiles from scene
        // This catches any tiles that might not be tracked in our arrays
        print("🗑️ Starting comprehensive tile cleanup...")
        
        // Method 1: Remove tracked tiles from arrays
        print("🗑️ Clearing \(tiles.count) existing letter tiles")
        for tile in tiles {
            // Clear physics body to stop any ongoing physics simulation
            tile.physicsBody = nil
            tile.removeFromParent()
        }
        tiles.removeAll()
        
        print("🗑️ Clearing \(messageTiles.count) existing message tiles")
        for messageTile in messageTiles {
            messageTile.removeFromParent()
        }
        messageTiles.removeAll()
        
        print("🗑️ Clearing \(themeTiles.count) existing theme tiles")
        for themeTile in themeTiles {
            themeTile.removeFromParent()
        }
        themeTiles.removeAll()
        
        // Method 2: Remove score and language tiles specifically
        if let scoreT = scoreTile {
            print("🗑️ Removing existing score tile")
            scoreT.removeFromParent()
            scoreTile = nil
        }
        
        if let langT = languageTile {
            print("🗑️ Removing existing language tile")
            langT.removeFromParent()
            languageTile = nil
        }
        
        // Method 3: Scan entire scene for any remaining tile nodes and remove them
        print("🗑️ Scanning scene for any remaining tile nodes...")
        print("🗑️ Total scene children before cleanup: \(children.count)")
        var removedCount = 0
        var childrenToRemove: [SKNode] = []
        
        for child in children {
            // Remove any LetterTile, ScoreTile, LanguageTile, or MessageTile that might have been missed
            if child is LetterTile || child is ScoreTile || child is LanguageTile || child is MessageTile {
                print("🗑️ Found orphaned tile of type \(type(of: child)), removing...")
                // Clear physics body to stop any ongoing physics simulation
                (child as? SKSpriteNode)?.physicsBody = nil
                childrenToRemove.append(child)
                removedCount += 1
            }
        }
        
        // Remove all found tiles
        for child in childrenToRemove {
            child.removeFromParent()
        }
        
        print("🗑️ Removed \(removedCount) orphaned tiles from scene")
        print("🗑️ Total scene children after cleanup: \(children.count)")
        
        // Scene cleanup debug logging removed to reduce API calls
        
        // Stop any ongoing physics effects
        removeAction(forKey: "quakeForces")
        quakeState = .none
        
        // Reset bookshelf position and rotation in case quake was active
        // BUT don't interfere if bookshelf drop animation is in progress
        if !bookshelf.hasActions() || bookshelf.physicsBody == nil {
            bookshelf.removeAllActions()
            bookshelf.position = bookshelfOriginalPosition
            bookshelf.zRotation = 0
        }
        
        // Check if we're in "no phrases" state
        print("🔍 resetGame: gameState = \(gameModel.gameState), scrambledLetters.count = \(gameModel.scrambledLetters.count)")
        if gameModel.gameState == .noPhrasesAvailable {
            print("📋 NO_PHRASES: Detected in resetGame - spawning information tile")
            let noPhrasesMessage = "No more phrases. Try again later."
            spawnMessageTile(message: noPhrasesMessage)
            print("✅ NO_PHRASES: Information tile spawned in resetGame")
            return
        }
        
        // Create new tiles with current game model data (don't call startNewGame again)
        createTiles()
        
        // Spawn MessageTile if there's a custom phrase
        if !gameModel.customPhraseInfo.isEmpty {
            spawnMessageTile(message: gameModel.customPhraseInfo)
        }
        
        print("✅ Scene reset complete - \(tiles.count) new tiles created")
        
        // Performance monitoring - record completion
        let tileResetEndTime = CACurrentMediaTime()
        print("🧪 PERFORMANCE: Tile reset completed at \(tileResetEndTime) with \(tiles.count) new tiles")
        
        
        // Scene reset complete debug logging removed to reduce API calls
    }
    
    
    private func checkSolution() {
        // Skip checking if game is already completed
        if gameModel.gameState == .completed {
            return
        }
        
        // Get all words from the current sentence
        let targetWords = gameModel.currentSentence.components(separatedBy: " ")
        
        // Minimal debug logging to avoid performance issues
        print("Checking solution for: \(gameModel.currentSentence)")
        
        // Group tiles by their vertical level (shelf or floor)
        let tileGroups = groupTilesByLevel(tiles: tiles)
        var allFoundWords: [String] = []
        
        // Check each level independently for complete words
        for (levelName, levelTiles) in tileGroups {
            print("📍 Checking \(levelName) with \(levelTiles.count) tiles")
            
            // CRITICAL: Only use tiles from THIS level to form words
            var levelFoundWords: [String] = []
            var usedTiles = Set<LetterTile>()
            
            // For each target word, see if we can form it COMPLETELY using ONLY tiles from this level
            for targetWord in targetWords {
                let targetLetters = Array(targetWord.uppercased())
                
                // Check if we have ALL required letters available on this level first
                let requiredLetters = targetLetters
                let availableTilesForThisWord = levelTiles.filter { !usedTiles.contains($0) }
                
                // Count required vs available letters
                var requiredCounts: [Character: Int] = [:]
                for letter in requiredLetters {
                    requiredCounts[letter, default: 0] += 1
                }
                
                var availableCounts: [Character: Int] = [:]
                for tile in availableTilesForThisWord {
                    let letter = Character(tile.letter.uppercased())
                    availableCounts[letter, default: 0] += 1
                }
                
                // Check if we have enough of each required letter
                var canFormCompleteWord = true
                for (letter, requiredCount) in requiredCounts {
                    let availableCount = availableCounts[letter, default: 0]
                    if availableCount < requiredCount {
                        print("❌ CANNOT FORM '\(targetWord)' on \(levelName) - need \(requiredCount) '\(letter)', have \(availableCount)")
                        canFormCompleteWord = false
                        break
                    }
                }
                
                if !canFormCompleteWord {
                    continue
                }
                
                // Now try to form the word using only tiles from this level
                if let bestCombination = findBestTileCombination(for: targetLetters, from: levelTiles, excluding: usedTiles) {
                    
                    // CRITICAL: Verify the combination has exactly the right number of letters
                    if bestCombination.count != targetLetters.count {
                        print("❌ REJECTED '\(targetWord)' - wrong number of tiles: got \(bestCombination.count), need \(targetLetters.count)")
                        continue
                    }
                    
                    // Double-check: verify ALL tiles in the combination are from this level
                    let allTilesFromThisLevel = bestCombination.allSatisfy { tile in
                        levelTiles.contains(tile)
                    }
                    
                    if !allTilesFromThisLevel {
                        print("❌ REJECTED '\(targetWord)' - contains tiles from other levels")
                        continue
                    }
                    
                    // Verify the combination spells the EXACT complete word when arranged left-to-right
                    let sortedTiles = bestCombination.sorted { $0.position.x < $1.position.x }
                    let formedWord = sortedTiles.map { $0.letter }.joined().uppercased()
                    let targetWordUpper = targetWord.uppercased()
                    
                    // CRITICAL: Check that the formed word is EXACTLY the target word
                    // This prevents "ON" from being accepted as "ONE" or "EJO" from being accepted as "JOB"
                    let isExactMatch = formedWord == targetWordUpper && 
                                     formedWord.count == targetWordUpper.count &&
                                     bestCombination.count == targetLetters.count
                    
                    if isExactMatch {
                        levelFoundWords.append(targetWord)
                        // Mark these tiles as used on this level
                        for tile in bestCombination {
                            usedTiles.insert(tile)
                        }
                        
                        // Additional debug: show exact tiles used
                        let tileDetails = sortedTiles.map { "\($0.letter)@(\(Int($0.position.x)),\(Int($0.position.y)))" }.joined(separator: ",")
                        print("✅ FORMED complete word '\(targetWord)' on \(levelName) using: \(tileDetails)")
                        print("✅ Formed word: '\(formedWord)' matches target: '\(targetWordUpper)' exactly")
                    } else {
                        let tileDetails = sortedTiles.map { "\($0.letter)@(\(Int($0.position.x)),\(Int($0.position.y)))" }.joined(separator: ",")
                        print("❌ REJECTED '\(targetWord)' on \(levelName)")
                        print("   Tiles: \(tileDetails)")
                        print("   Formed: '\(formedWord)' (len=\(formedWord.count))")
                        print("   Target: '\(targetWordUpper)' (len=\(targetWordUpper.count))")
                        print("   Tile count: got \(bestCombination.count), need \(targetLetters.count)")
                    }
                } else {
                    print("❌ ALGORITHM FAILED to form '\(targetWord)' on \(levelName) despite having sufficient tiles")
                }
            }
            
            allFoundWords.append(contentsOf: levelFoundWords)
            print("📍 \(levelName) final words: \(levelFoundWords.joined(separator: ", "))")
        }
        
        // CRITICAL DEBUG: Show exactly what was found
        print("🔍 FINAL ANALYSIS:")
        print("   Target words: \(targetWords)")
        print("   Found words: \(allFoundWords)")
        print("   Found count: \(allFoundWords.count), Target count: \(targetWords.count)")
        
        // Check for victory: all target words must be found in correct order
        let foundWordsUpper = allFoundWords.map { $0.uppercased() }
        let targetWordsUpper = targetWords.map { $0.uppercased() }
        let hasAllWords = allFoundWords.count == targetWords.count
        let hasCorrectWords = foundWordsUpper == targetWordsUpper  // Order matters!
        
        print("   Has all words: \(hasAllWords)")
        print("   Has correct words: \(hasCorrectWords)")
        print("   Found order: \(foundWordsUpper)")
        print("   Target order: \(targetWordsUpper)")
        
        let isComplete = hasAllWords && hasCorrectWords
        
        if isComplete {
            print("🎉 VICTORY TRIGGERED!")
            if !celebrationText.contains("🎉") { // Only celebrate once
                // IMMEDIATELY drop shelves to the floor when victory is achieved
                animateShelvesToFloor()
                
                gameModel.completeGame() // Calculate score immediately
                // Trigger celebration on next run loop to ensure score is updated
                DispatchQueue.main.async {
                    self.triggerCelebration() // Celebrate with updated score
                }
            }
            celebrationText = "🎉 VICTORY! All words complete: \(allFoundWords.joined(separator: " + "))"
        } else {
            print("❌ NO VICTORY - Requirements not met")
            let expectedWords = targetWords.joined(separator: ", ")
            let currentWords = allFoundWords.isEmpty ? "None" : allFoundWords.joined(separator: ", ")
            celebrationText = "Words: \(allFoundWords.count)/\(targetWords.count) complete\nExpected: \(expectedWords)\nFound: \(currentWords)"
        }
        
        print("Celebration: \(celebrationText)")
    }
    
    private func groupTilesByLevel(tiles: [LetterTile]) -> [(String, [LetterTile])] {
        let yTolerance: CGFloat = 30  // Max Y difference to be considered same horizontal level
        
        // Group tiles by their actual Y position (horizontal rows)
        var yGroups: [Int: [LetterTile]] = [:]
        
        for tile in tiles {
            let roundedY = Int(round(tile.position.y / yTolerance)) * Int(yTolerance)
            yGroups[roundedY, default: []].append(tile)
        }
        
        // Get target words to check if single tiles can form complete words
        let targetWords = gameModel.currentSentence.split(separator: " ").map { String($0) }
        
        // Keep groups that have multiple tiles (companions) OR single tiles that form complete words
        var validLevels: [(String, [LetterTile])] = []
        
        for (yLevel, tilesAtLevel) in yGroups {
            if tilesAtLevel.count >= 2 {
                // Multiple tiles at this Y level - they can form words together
                let levelName = "Level_Y\(yLevel)"
                validLevels.append((levelName, tilesAtLevel))
                
                let tileDetails = tilesAtLevel.map { "\($0.letter)@(\(Int($0.position.x)),\(Int($0.position.y)))" }.joined(separator: ",")
                print("✅ Valid level \(levelName): \(tileDetails)")
            } else {
                // Single tile at this Y level - check if it can form a complete word by itself
                let lonelyTile = tilesAtLevel[0]
                let singleLetter = lonelyTile.letter.uppercased()
                
                // Check if this single letter matches any target word
                let canFormCompleteWord = targetWords.contains { word in
                    word.uppercased() == singleLetter
                }
                
                if canFormCompleteWord {
                    let levelName = "Level_Y\(yLevel)"
                    validLevels.append((levelName, tilesAtLevel))
                    print("✅ Valid single tile '\(singleLetter)' at Y=\(Int(lonelyTile.position.y)) - forms complete word")
                } else {
                    print("❌ EXCLUDED lonely tile '\(lonelyTile.letter)' at Y=\(Int(lonelyTile.position.y)) - no companions and doesn't form complete word")
                }
            }
        }
        
        // Sort levels by Y position (top to bottom)
        return validLevels.sorted { level1, level2 in
            let level1AvgY = level1.1.map { $0.position.y }.reduce(0, +) / CGFloat(level1.1.count)
            let level2AvgY = level2.1.map { $0.position.y }.reduce(0, +) / CGFloat(level2.1.count)
            return level1AvgY > level2AvgY // Higher Y first
        }
    }
    
    private func findBestTileCombination(for targetLetters: [Character], from allTiles: [LetterTile], excluding usedTiles: Set<LetterTile>) -> [LetterTile]? {
        // Filter out already used tiles
        let availableTiles = allTiles.filter { !usedTiles.contains($0) }
        let targetWord = String(targetLetters).uppercased()
        
        print("🔍 ATTEMPTING to form '\(targetWord)' from \(availableTiles.count) available tiles")
        
        // Count how many of each letter we need
        var letterCounts: [Character: Int] = [:]
        for letter in targetLetters {
            let upperLetter = Character(String(letter).uppercased())
            letterCounts[upperLetter, default: 0] += 1
        }
        
        // Get all tiles grouped by letter type
        var tilesByLetter: [Character: [LetterTile]] = [:]
        for tile in availableTiles {
            let letter = Character(tile.letter.uppercased())
            tilesByLetter[letter, default: []].append(tile)
        }
        
        // Check if we have enough tiles for each required letter
        for (letter, requiredCount) in letterCounts {
            let availableCount = tilesByLetter[letter]?.count ?? 0
            if availableCount < requiredCount {
                print("❌ Not enough '\(letter)' tiles. Need: \(requiredCount), Available: \(availableCount)")
                return nil
            }
        }
        
        // CRITICAL FIX: Try all possible combinations and ONLY accept ones that spell the word correctly
        let allCombinations = generateTileCombinations(for: targetLetters, from: tilesByLetter)
        print("🔍 Generated \(allCombinations.count) possible combinations for '\(targetWord)'")
        
        // Test each combination to see if it spells the target word when arranged left-to-right
        for (index, combination) in allCombinations.enumerated() {
            let sortedTiles = combination.sorted { $0.position.x < $1.position.x }
            let formedWord = sortedTiles.map { $0.letter }.joined().uppercased()
            
            // Show detailed testing for each combination
            let tilePositions = sortedTiles.map { "\($0.letter)@X\(Int($0.position.x))" }.joined(separator: ",")
            print("🔍 Combination \(index + 1): [\(tilePositions)] → '\(formedWord)'")
            
            // STRICT VALIDATION: Must spell exactly the target word
            if formedWord == targetWord && combination.count == targetLetters.count {
                print("✅ PERFECT MATCH! '\(formedWord)' == '\(targetWord)'")
                return sortedTiles
            } else {
                let reason = formedWord != targetWord ? "wrong spelling" : "wrong count"
                print("❌ REJECTED: '\(formedWord)' ≠ '\(targetWord)' (\(reason))")
            }
        }
        
        print("❌ NO VALID COMBINATION found for '\(targetWord)' from \(allCombinations.count) attempts")
        
        // Additional debug: show what tiles we actually have
        let availableLetters = availableTiles.map { "\($0.letter)@X\(Int($0.position.x))" }.sorted()
        print("❌ Available tiles were: \(availableLetters.joined(separator: ","))")
        
        return nil
    }
    
    private func generateTileCombinations(for targetLetters: [Character], from tilesByLetter: [Character: [LetterTile]]) -> [[LetterTile]] {
        // Create a recursive function to generate all possible combinations
        func generateCombinations(remainingLetters: [Character], currentCombination: [LetterTile], usedTiles: Set<LetterTile>) -> [[LetterTile]] {
            // Base case: no more letters to assign
            if remainingLetters.isEmpty {
                return [currentCombination]
            }
            
            let nextLetter = remainingLetters[0]
            let remainingAfterNext = Array(remainingLetters.dropFirst())
            
            // Get all available tiles for this letter
            let candidateTiles = tilesByLetter[nextLetter] ?? []
            let availableTiles = candidateTiles.filter { !usedTiles.contains($0) }
            
            var results: [[LetterTile]] = []
            
            // Try each available tile for this letter position
            for tile in availableTiles {
                var newCombination = currentCombination
                newCombination.append(tile)
                
                var newUsedTiles = usedTiles
                newUsedTiles.insert(tile)
                
                // Recursively generate combinations for remaining letters
                let subCombinations = generateCombinations(
                    remainingLetters: remainingAfterNext,
                    currentCombination: newCombination,
                    usedTiles: newUsedTiles
                )
                
                results.append(contentsOf: subCombinations)
            }
            
            return results
        }
        
        return generateCombinations(remainingLetters: targetLetters, currentCombination: [], usedTiles: Set())
    }
    
    func triggerCelebration() {
        print("🎊 Starting enhanced celebration sequence!")
        
        // Preserve emoji tiles during celebration so effects can trigger later
        disableImmediateEmojiEffects = true
        DebugLogger.shared.ui("🎭 CELEBRATION: Enabled tile preservation for celebration sequence")
        
        // Clear old celebration text - no more text displays
        celebrationText = ""
        
        // Start the cinematic celebration sequence
        let celebrationSequence = SKAction.sequence([
            // Phase 1: Drop celebration tiles, awesome message, and start fireworks immediately
            SKAction.run { [weak self] in
                DebugLogger.shared.ui("🎬 PHASE 1: Starting celebration sequence")
                self?.dropCelebrationTiles()
                self?.dropAwesomeTile()
                self?.createRocketFireworks()
            },
            
            // Wait 1.5 seconds before fade to black
            SKAction.wait(forDuration: 1.5),
            
            // Phase 2: Fade to black (1.0 seconds)
            SKAction.run { [weak self] in
                DebugLogger.shared.ui("🎬 PHASE 2: Creating fade to black overlay")
                self?.createFadeToBlackOverlay()
            },
            SKAction.wait(forDuration: 1.0),
            
            // Phase 3: Trigger new discovery effects DURING darkness for dramatic glow-through effect
            SKAction.run { [weak self] in
                DebugLogger.shared.ui("🎬 PHASE 3: Triggering new discovery effects during darkness")
                self?.triggerNewDiscoveryEffects()
            },
            SKAction.wait(forDuration: 2.0), // Let effects play in darkness
            
            // Phase 4: Start new game with dramatic bookshelf drop (2.0 seconds)
            SKAction.run { [weak self] in
                self?.startNewGameWithBookshelfDrop()
            },
            SKAction.wait(forDuration: 2.0),
            
            // Phase 5: Remove overlay (1.5 seconds)
            SKAction.run { [weak self] in
                DebugLogger.shared.ui("🎬 PHASE 5: Removing fade overlay")
                self?.removeFadeOverlay()
            },
            SKAction.wait(forDuration: 1.0), // Wait for delayed effects to complete
            SKAction.run { [weak self] in
                self?.cleanupCelebrationTiles() // Cleanup after effects are done
            }
        ])
        
        run(celebrationSequence, withKey: "celebrationSequence")
    }
    
    private func startNewGame() {
        // Clear hint effects when starting new game
        clearAllHints()
        
        // Reset game model to get new sentence
        // GameModel.startNewGame will automatically call resetGame() through messageTileSpawner
        Task {
            await gameModel.startNewGame(isUserInitiated: true)
            // No need to call resetGame() here - it's already called by GameModel.startNewGame()
        }
    }
    
    private var fadeOverlay: SKSpriteNode?
    
    private func createFadeToBlackOverlay() {
        // Remove existing overlay if any
        fadeOverlay?.removeFromParent()
        
        // Create full-screen black overlay
        fadeOverlay = SKSpriteNode(color: .black, size: size)
        fadeOverlay?.position = CGPoint(x: size.width / 2, y: size.height / 2)
        fadeOverlay?.zPosition = 200
        fadeOverlay?.alpha = 0
        
        addChild(fadeOverlay!)
        
        // Animate fade to black
        let fadeIn = SKAction.fadeAlpha(to: 0.85, duration: 0.8)
        fadeOverlay?.run(fadeIn)
        
        print("🌑 Fade to black overlay created")
    }
    
    private func triggerNewDiscoveryEffects() {
        // Trigger effects DURING darkness for newly discovered emojis to glow through
        print("🌑🎆 TRIGGERING NEW DISCOVERY EFFECTS DURING DARKNESS for \(newlyDroppedEmojiTiles.count) tiles")
        DebugLogger.shared.ui("🌑🎆 TRIGGERING NEW DISCOVERY EFFECTS DURING DARKNESS for \(newlyDroppedEmojiTiles.count) tiles")
        
        if newlyDroppedEmojiTiles.isEmpty {
            print("❌ NO EMOJI TILES TO TRIGGER EFFECTS ON!")
            DebugLogger.shared.ui("❌ NO EMOJI TILES TO TRIGGER EFFECTS ON!")
        } else {
            // Only trigger effects for newly discovered emojis, not ones already in collection
            let newDiscoveryTiles = newlyDroppedEmojiTiles.filter { $0.name == "new_discovery_emoji" }
            
            if newDiscoveryTiles.isEmpty {
                print("🔍 No new discoveries found - skipping effects (have \(newlyDroppedEmojiTiles.count) total tiles, 0 new)")
                DebugLogger.shared.ui("🔍 No new discoveries found - skipping effects (have \(newlyDroppedEmojiTiles.count) total tiles, 0 new)")
            } else {
                print("🌟💫 Triggering GLOW-THROUGH effects for \(newDiscoveryTiles.count) NEW discoveries (out of \(newlyDroppedEmojiTiles.count) total)")
                DebugLogger.shared.ui("🌟💫 Triggering GLOW-THROUGH effects for \(newDiscoveryTiles.count) NEW discoveries (out of \(newlyDroppedEmojiTiles.count) total)")
                
                for (index, emojiTile) in newDiscoveryTiles.enumerated() {
                    print("🎯💫 NEW DISCOVERY GLOW EFFECT \(index + 1)/\(newDiscoveryTiles.count): \(emojiTile.emoji) (\(emojiTile.rarity?.displayName ?? "unknown"))")
                    DebugLogger.shared.ui("🎯💫 NEW DISCOVERY GLOW EFFECT \(index + 1)/\(newDiscoveryTiles.count): \(emojiTile.emoji) (\(emojiTile.rarity?.displayName ?? "unknown"))")
                    // Reset the effects flag so effects can trigger
                    emojiTile.resetEffectsFlag()
                    emojiTile.triggerDropEffects(gameModel: gameModel)
                }
            }
        }
        
        print("🌑✨ New discovery effects triggered during darkness")
    }
    
    private func removeFadeOverlay() {
        guard let overlay = fadeOverlay else { return }
        
        let fadeOut = SKAction.fadeOut(withDuration: 0.8)
        let remove = SKAction.removeFromParent()
        let sequence = SKAction.sequence([fadeOut, remove])
        
        overlay.run(sequence) { [weak self] in
            self?.fadeOverlay = nil
        }
        
        print("🌕 Fade overlay started fading")
    }
    
    
    private func createRocketFireworks() {
        print("🚀 Creating realistic rocket fireworks display!")
        
        // Create 6 rocket fireworks with realistic flight and explosion
        for i in 0..<6 {
            let delay = Double(i) * 0.5 // Stagger rockets every 0.5 seconds
            
            let rocketAction = SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak self] in
                    self?.launchSingleRocket()
                }
            ])
            
            run(rocketAction)
        }
    }
    
    private func launchSingleRocket() {
        // Launch position at bottom of screen
        let launchX = CGFloat.random(in: size.width * 0.2...size.width * 0.8)
        let launchY = CGFloat(20)
        
        // Create rocket trail
        let rocket = SKShapeNode(circleOfRadius: 3)
        rocket.fillColor = .white
        rocket.strokeColor = .yellow
        rocket.lineWidth = 2
        rocket.position = CGPoint(x: launchX, y: launchY)
        rocket.zPosition = 250
        
        addChild(rocket)
        
        // Rocket flies up
        let explosionY = CGFloat.random(in: size.height * 0.6...size.height * 0.9)
        let flyUp = SKAction.moveTo(y: explosionY, duration: 1.2)
        flyUp.timingMode = .easeOut
        
        // Create explosion at peak
        let explode = SKAction.run { [weak self] in
            self?.createExplosion(at: CGPoint(x: launchX, y: explosionY))
            rocket.removeFromParent()
        }
        
        let rocketSequence = SKAction.sequence([flyUp, explode])
        rocket.run(rocketSequence)
    }
    
    private func createExplosion(at position: CGPoint) {
        // Create 12-16 explosion particles radiating outward
        let particleCount = Int.random(in: 12...16)
        let colors: [UIColor] = [.systemRed, .systemBlue, .systemGreen, .systemYellow, 
                               .systemOrange, .systemPurple, .systemPink, .cyan, 
                               .magenta, .white, .systemTeal, .systemIndigo]
        
        for i in 0..<particleCount {
            let particle = SKShapeNode(circleOfRadius: CGFloat.random(in: 4...8))
            particle.fillColor = colors.randomElement() ?? .white
            particle.strokeColor = .white
            particle.lineWidth = 2
            particle.position = position
            particle.zPosition = 250
            
            addChild(particle)
            
            // Random direction for explosion particles
            let angle = (Double(i) / Double(particleCount)) * 2 * Double.pi
            let distance = CGFloat.random(in: 60...120)
            let endX = position.x + cos(angle) * distance
            let endY = position.y + sin(angle) * distance
            
            // Particle animation: shoot out, fade, and fall
            let shootOut = SKAction.move(to: CGPoint(x: endX, y: endY), duration: 0.8)
            let fadeOut = SKAction.fadeOut(withDuration: 1.5)
            let gravity = SKAction.moveBy(x: 0, y: -100, duration: 1.5)
            let remove = SKAction.removeFromParent()
            
            let particleSequence = SKAction.sequence([
                SKAction.group([shootOut, fadeOut, gravity]),
                remove
            ])
            
            particle.run(particleSequence)
        }
    }
    
    private func dropCelebrationTiles() {
        DebugLogger.shared.ui("🎉 Starting celebration with phrase emojis!")
        print("🎉 DEBUG: dropCelebrationTiles() called!")
        
        // Get celebration emojis from the current phrase
        guard let currentPhrase = gameModel.currentCustomPhrase else {
            DebugLogger.shared.error("❌ No current phrase available for emoji drop")
            print("❌ DEBUG: No current phrase - falling back to basic emojis")
            displayFallbackEmojis()
            return
        }
        
        let celebrationEmojis = currentPhrase.celebrationEmojis
        
        if celebrationEmojis.isEmpty {
            DebugLogger.shared.ui("⚠️ No celebration emojis in phrase - falling back to basic emojis")
            print("⚠️ DEBUG: No celebration emojis in phrase")
            displayFallbackEmojis()
            return
        }
        
        DebugLogger.shared.ui("🎲 Using \(celebrationEmojis.count) celebration emojis from phrase: \(celebrationEmojis.map(\.emojiCharacter).joined(separator: ", "))")
        print("🎲 DEBUG: Using \(celebrationEmojis.count) celebration emojis from phrase: \(celebrationEmojis.map(\.emojiCharacter).joined(separator: ", "))")
        
        // Display the phrase's celebration emojis directly
        displayPhraseCelebrationEmojis(emojis: celebrationEmojis)
    }
    
    private func displayPhraseCelebrationEmojis(emojis: [EmojiCatalogItem]) {
        DebugLogger.shared.ui("🎲 Displaying \(emojis.count) phrase celebration emojis")
        
        // Create and drop emoji tiles for each celebration emoji
        for (index, emojiData) in emojis.enumerated() {
            // Only mark as new discovery if player hasn't collected this emoji before
            // For now, simulate proper discovery logic - in real game this comes from server
            let isNewDiscovery = !hasPlayerCollectedEmoji(emojiData.emojiCharacter)
            createAndDropEmojiTile(
                emoji: emojiData.emojiCharacter,
                index: index,
                isNewDiscovery: isNewDiscovery,
                rarity: emojiData.rarity
            )
        }
    }
    
    private func displayDroppedEmojis(dropResult: EmojiDropResult) {
        DebugLogger.shared.ui("🎲 Displaying \(dropResult.droppedEmojis.count) dropped emojis")
        
        let emojisToDisplay = dropResult.droppedEmojis.map { $0.emojiCharacter }
        
        for (index, emoji) in emojisToDisplay.enumerated() {
            createAndDropEmojiTile(
                emoji: emoji, 
                index: index, 
                isNewDiscovery: dropResult.newDiscoveries.contains { $0.emojiCharacter == emoji },
                rarity: dropResult.droppedEmojis.first { $0.emojiCharacter == emoji }?.rarity
            )
        }
        
        // Show points earned notification
        if dropResult.pointsEarned > 0 {
            showPointsEarnedNotification(points: dropResult.pointsEarned)
        }
        
        // Log new discoveries
        if !dropResult.newDiscoveries.isEmpty {
            let newEmojiNames = dropResult.newDiscoveries.map { "\($0.emojiCharacter) (\($0.rarity.displayName))" }
            DebugLogger.shared.game("🆕 New emoji discoveries: \(newEmojiNames)")
        }
    }
    
    private func createAndDropEmojiTile(emoji: String, index: Int, isNewDiscovery: Bool, rarity: EmojiRarity?) {
        // Create emoji tile with same size as regular tiles
        let baseTileSize: CGFloat = 40
        let tileSize = CGSize(width: baseTileSize * PhysicsGameScene.componentScaleFactor, 
                            height: baseTileSize * PhysicsGameScene.componentScaleFactor)
        let emojiTile = EmojiIconTile(emoji: emoji, rarity: rarity, size: tileSize)
        
        // Mark tiles based on rarity and discovery status
        if isNewDiscovery {
            emojiTile.name = "new_discovery_emoji"
            DebugLogger.shared.ui("🌟 NEW DISCOVERY: \(emoji) (\(rarity?.displayName ?? "unknown") rarity)")
            // Add glow effect to new discovery tiles
            emojiTile.addNewlyDroppedGlowEffect()
        } else if rarity?.triggersGlobalDrop == true {
            emojiTile.name = "rare_collectable_emoji"
        } else {
            emojiTile.name = "collectable_emoji"
        }
        
        // Position above screen for rain effect (same as letter tiles)
        let spawnY = size.height * 0.9  // High above visible area
        let spawnWidth = size.width * 0.4  // Center clustering like letter tiles
        let randomX = CGFloat.random(in: -spawnWidth/2...spawnWidth/2)
        let baseX = size.width / 2 + randomX
        let randomYOffset = CGFloat.random(in: -20...20)
        emojiTile.position = CGPoint(x: baseX, y: spawnY + randomYOffset)
        
        // Add random rotation for visual variety (like letter tiles)
        emojiTile.zRotation = CGFloat.random(in: -0.3...0.3)
        
        // Set z-position based on rarity - only rare emojis need to be in front of overlay
        if let rarity = rarity {
            switch rarity {
            case .legendary, .mythic, .epic:
                emojiTile.zPosition = 1000 // In front of dark overlay for sparkle effects
            case .rare, .uncommon, .common:
                emojiTile.zPosition = 100 // Normal position behind overlay
            }
        } else {
            emojiTile.zPosition = 100 // Default position for emojis without rarity
        }
        
        // Add sparkle effect for all rare emojis (Epic and above)
        addSparkleEffect(to: emojiTile, rarity: rarity)
        
        addChild(emojiTile)
        
        // Track this as a newly dropped emoji tile from current game
        newlyDroppedEmojiTiles.append(emojiTile)
        let rarityName = rarity?.displayName ?? "no rarity"
        DebugLogger.shared.ui("📍 TRACK: Added \(emoji) (\(rarityName)) to newly dropped tiles (total: \(newlyDroppedEmojiTiles.count))")
        
        // Skip immediate effects during celebration - they will be triggered when darkness lifts
        DebugLogger.shared.ui("🚫 IMMEDIATE EFFECTS: Skipping immediate emoji effects - will trigger when darkness lifts")
        
        // Add to tiles array for cleanup
        (allRespawnableTiles as? NSMutableArray)?.add(emojiTile)
        
        let delay = SKAction.wait(forDuration: Double(index) * 0.2)
        let giveInitialVelocity = SKAction.run {
            emojiTile.physicsBody?.velocity = CGVector(dx: 0, dy: -200)
            emojiTile.physicsBody?.applyImpulse(CGVector(dx: 0, dy: -100))
        }
        let dropAction = SKAction.sequence([delay, giveInitialVelocity])
        emojiTile.run(dropAction)
    }
    
    private func addSparkleEffect(to emojiTile: EmojiIconTile, rarity: EmojiRarity?) {
        // Add intense glow effect for ALL emojis that cuts through dark backgrounds
        if let rarity = rarity {
            // Add glow effect for all rarities - each with unique color and intensity
            let shouldSparkle: Bool
            let glowConfig: (scale: CGFloat, duration: TimeInterval, glowRadius: CGFloat, glowColor: UIColor)
            
            switch rarity {
            case .legendary:
                shouldSparkle = true
                glowConfig = (scale: 1.6, duration: 0.3, glowRadius: 25.0, glowColor: UIColor.systemYellow)
            case .mythic:
                shouldSparkle = true
                glowConfig = (scale: 1.5, duration: 0.4, glowRadius: 20.0, glowColor: UIColor.systemPurple)
            case .epic:
                shouldSparkle = true
                glowConfig = (scale: 1.4, duration: 0.5, glowRadius: 15.0, glowColor: UIColor.systemBlue)
            case .rare:
                shouldSparkle = true
                glowConfig = (scale: 1.3, duration: 0.6, glowRadius: 12.0, glowColor: UIColor.systemRed)
            case .uncommon:
                shouldSparkle = true
                glowConfig = (scale: 1.2, duration: 0.7, glowRadius: 10.0, glowColor: UIColor.systemOrange)
            case .common:
                shouldSparkle = true
                glowConfig = (scale: 1.1, duration: 0.8, glowRadius: 8.0, glowColor: UIColor.white)
            }
            
            if shouldSparkle {
                // Create ultra-bright glow that blasts through dark overlays
                let glowNode = SKShapeNode(circleOfRadius: glowConfig.glowRadius)
                glowNode.fillColor = glowConfig.glowColor
                glowNode.strokeColor = glowConfig.glowColor.withAlphaComponent(0.8)
                glowNode.lineWidth = 3.0
                glowNode.alpha = 1.0 // Start at full brightness
                glowNode.blendMode = .screen // Screen blend mode for maximum brightness
                glowNode.zPosition = -1 // Behind emoji but will inherit parent's high z-position
                
                // Add multiple glow layers for ultra-intensity
                let outerGlow = SKShapeNode(circleOfRadius: glowConfig.glowRadius * 1.5)
                outerGlow.fillColor = glowConfig.glowColor.withAlphaComponent(0.3)
                outerGlow.strokeColor = UIColor.clear
                outerGlow.alpha = 0.8
                outerGlow.blendMode = .screen
                outerGlow.zPosition = -2 // Behind main glow, will inherit parent's high z-position
                
                // Position glows as child nodes (safe approach)
                emojiTile.addChild(glowNode)
                emojiTile.addChild(outerGlow)
                
                // Create finite pulsing effect (not infinite)
                let glowPulse = SKAction.sequence([
                    SKAction.group([
                        SKAction.scale(to: glowConfig.scale, duration: glowConfig.duration),
                        SKAction.fadeAlpha(to: 1.0, duration: glowConfig.duration) // Maximum brightness
                    ]),
                    SKAction.group([
                        SKAction.scale(to: 1.0, duration: glowConfig.duration),
                        SKAction.fadeAlpha(to: 0.7, duration: glowConfig.duration) // Still very bright
                    ])
                ])
                
                // Ultra-bright glow node pulsing
                let glowNodePulse = SKAction.sequence([
                    SKAction.fadeAlpha(to: 1.0, duration: glowConfig.duration), // Full brightness
                    SKAction.fadeAlpha(to: 0.6, duration: glowConfig.duration)  // Bright minimum
                ])
                
                // Outer glow subtle pulsing
                let outerGlowPulse = SKAction.sequence([
                    SKAction.fadeAlpha(to: 1.0, duration: glowConfig.duration * 1.2),
                    SKAction.fadeAlpha(to: 0.4, duration: glowConfig.duration * 1.2)
                ])
                
                // Run pulsing for exactly 10 seconds, then stop
                let pulseCount = Int(10.0 / (glowConfig.duration * 2)) // Calculate exact pulse count
                let finiteGlowPulse = SKAction.repeat(glowPulse, count: pulseCount)
                let finiteGlowNodePulse = SKAction.repeat(glowNodePulse, count: pulseCount)
                let finiteOuterPulse = SKAction.repeat(outerGlowPulse, count: Int(10.0 / (glowConfig.duration * 2.4)))
                
                // Run finite effects
                emojiTile.run(finiteGlowPulse)
                glowNode.run(finiteGlowNodePulse)
                outerGlow.run(finiteOuterPulse)
                
                // Clean up after 10 seconds - remove all glow effects
                let cleanup = SKAction.sequence([
                    SKAction.wait(forDuration: 10.5), // Wait slightly longer than pulses
                    SKAction.group([
                        SKAction.scale(to: 1.0, duration: 0.5), // Return to normal size
                        SKAction.fadeAlpha(to: 1.0, duration: 0.5), // Return to normal opacity
                        SKAction.run { 
                            glowNode.removeFromParent()
                            outerGlow.removeFromParent()
                        }
                    ])
                ])
                
                emojiTile.run(cleanup)
            }
        }
    }
    
    private func showPointsEarnedNotification(points: Int) {
        // Create points notification label
        let pointsLabel = SKLabelNode(text: "+\(points) pts")
        pointsLabel.fontName = "AvenirNext-Bold"
        pointsLabel.fontSize = 24
        pointsLabel.fontColor = UIColor.systemYellow
        pointsLabel.position = CGPoint(x: size.width / 2, y: size.height - 100)
        pointsLabel.zPosition = 200
        
        addChild(pointsLabel)
        
        // Animate points notification
        let moveUp = SKAction.moveBy(x: 0, y: 50, duration: 1.0)
        let fadeOut = SKAction.fadeOut(withDuration: 1.0)
        let remove = SKAction.removeFromParent()
        let pointsSequence = SKAction.sequence([
            SKAction.group([moveUp, fadeOut]),
            remove
        ])
        
        pointsLabel.run(pointsSequence)
    }
    
    private func showGlobalDropAnnouncement(message: String) {
        // Create global drop announcement
        let announcementLabel = SKLabelNode(text: message)
        announcementLabel.fontName = "AvenirNext-Bold"
        announcementLabel.fontSize = 20
        announcementLabel.fontColor = UIColor.systemGreen
        announcementLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        announcementLabel.zPosition = 300
        
        addChild(announcementLabel)
        
        // Animate announcement
        let scaleIn = SKAction.scale(to: 1.0, duration: 0.5)
        announcementLabel.setScale(0.1)
        let wait = SKAction.wait(forDuration: 3.0)
        let fadeOut = SKAction.fadeOut(withDuration: 0.5)
        let remove = SKAction.removeFromParent()
        let announcementSequence = SKAction.sequence([scaleIn, wait, fadeOut, remove])
        
        announcementLabel.run(announcementSequence)
        
        DebugLogger.shared.game("🌍 Global drop announcement: \(message)")
    }
    
    private func displayFallbackEmojis() {
        // Fallback to basic celebration emojis if API fails
        let fallbackEmojis = ["🎉", "🎊", "✨"]
        print("🎉 DEBUG: Displaying \(fallbackEmojis.count) fallback emojis: \(fallbackEmojis)")
        
        for (index, emoji) in fallbackEmojis.enumerated() {
            // Only mark as new discovery if player hasn't collected this emoji before
            let isNewDiscovery = !hasPlayerCollectedEmoji(emoji)
            createAndDropEmojiTile(emoji: emoji, index: index, isNewDiscovery: isNewDiscovery, rarity: .common)
            print("🎉 DEBUG: Created fallback emoji tile: \(emoji) at index \(index)")
        }
    }
    
    private func hasPlayerCollectedEmoji(_ emoji: String) -> Bool {
        // Check if this emoji already exists as a collectible tile on the board
        for child in children {
            if let emojiTile = child as? EmojiIconTile {
                if emojiTile.emoji == emoji && 
                   (emojiTile.name == "collectable_emoji" || emojiTile.name == "rare_collectable_emoji") {
                    DebugLogger.shared.ui("🔍 DISCOVERY CHECK: \(emoji) already collected (found on board)")
                    return true
                }
            }
        }
        DebugLogger.shared.ui("🆕 DISCOVERY CHECK: \(emoji) is a new discovery!")
        return false
    }
    
    private func dropAwesomeTile() {
        print("🔥 Dropping congratulatory information tile!")
        
        let randomMessage = PhysicsGameScene.congratulatoryMessages.randomElement() ?? "Congratulations!"
        
        // Create congratulatory information tile
        let awesomeTile = MessageTile(message: randomMessage, sceneSize: size)
        
        // Position at top of visible screen center for testing
        let startY = size.height - 100
        awesomeTile.position = CGPoint(x: size.width / 2, y: startY)
        awesomeTile.zPosition = 100
        
        print("🔥 Created '\(randomMessage)' tile at position (\(size.width / 2), \(startY)), screen height: \(size.height)")
        print("🔥 Awesome tile physics body: \(String(describing: awesomeTile.physicsBody))")
        
        addChild(awesomeTile)
        
        // Add to tiles array
        (allRespawnableTiles as? NSMutableArray)?.add(awesomeTile)
        
        // Give it a strong initial downward velocity
        awesomeTile.physicsBody?.velocity = CGVector(dx: 0, dy: -200)
        awesomeTile.physicsBody?.applyImpulse(CGVector(dx: 0, dy: -100))
    }
    
    private func startNewGameWithBookshelfDrop() {
        print("📚 Starting new game after bookshelf drop!")
        
        // Just start the new game - bookshelf has already been animated
        Task {
            await gameModel.startNewGame(isUserInitiated: true)
        }
    }
    
    
    func animateShelvesToFloor() {
        // Look for the bookshelf node - try different possible names
        var mainBookshelf: SKNode?
        
        // Try common bookshelf names
        let possibleNames = ["bookshelf", "Bookshelf", "bookShelf", "shelf"]
        for name in possibleNames {
            if let found = childNode(withName: name) {
                mainBookshelf = found
                break
            }
        }
        
        // If no named bookshelf found, look for the node that contains shelves
        if mainBookshelf == nil {
            if !shelves.isEmpty, let firstShelf = shelves.first, let parent = firstShelf.parent {
                mainBookshelf = parent
            }
        }
        
        // If still nothing, look for a node with many children (likely the bookshelf container)
        if mainBookshelf == nil {
            mainBookshelf = children.first { node in
                node.children.count >= 4  // Bookshelf should have multiple parts
            }
        }
        
        if let bookshelf = mainBookshelf {
            animateCompleteBookshelf(bookshelf)
        } else {
            // Fallback to shelf-only animation
            animateShelvesOnly()
        }
    }
    
    private func animateShelvesOnly() {
        guard !shelves.isEmpty else { return }
        
        // Random angle
        let maxAngle = CGFloat.pi / 6  // 30 degrees
        let fallAngle = Bool.random() ? 
            CGFloat.random(in: 0...maxAngle) :
            CGFloat.random(in: -maxAngle...0)
        
        // Apply same rotation and physics to all shelves
        for shelf in shelves {
            shelf.zRotation = fallAngle
            shelf.physicsBody?.angularVelocity = fallAngle * 0.5
            
            let pushDirection: CGFloat = fallAngle > 0 ? 1 : -1
            shelf.physicsBody?.velocity = CGVector(dx: pushDirection * 30, dy: -100)
        }
    }
    
    private func animateCompleteBookshelf(_ bookshelf: SKNode) {
        // Random fall angle: 0-30 degrees left or right
        let maxAngle = CGFloat.pi / 6  // 30 degrees
        let fallAngle = Bool.random() ? 
            CGFloat.random(in: 0...maxAngle) :     // Right tilt
            CGFloat.random(in: -maxAngle...0)      // Left tilt
        
        // Store original position (this is the "floor" level)
        let originalPosition = bookshelf.position
        let floorY = originalPosition.y  // Hit floor at original level
        
        // Step 1: Fade out quickly
        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        
        bookshelf.run(fadeOut) {
            // Step 2: Move to sky and set rotation
            bookshelf.position = CGPoint(x: originalPosition.x, y: self.size.height + 300)
            bookshelf.zRotation = fallAngle  // Set rotation BEFORE falling
            bookshelf.alpha = 1.0  // Make visible again
            
            // Step 3: Fall straight down to floor level (SKAction)
            let fallToFloor = SKAction.move(to: CGPoint(x: originalPosition.x, y: floorY), duration: 1.2)
            fallToFloor.timingMode = .easeIn
            
            bookshelf.run(fallToFloor) {
                // Step 4: Enable physics for realistic heavy bookshelf behavior
                let bookshelfSize = CGSize(width: 300, height: 400)
                bookshelf.physicsBody = SKPhysicsBody(rectangleOf: bookshelfSize)
                bookshelf.physicsBody?.isDynamic = true
                bookshelf.physicsBody?.affectedByGravity = true
                
                // Use wall category to avoid conflicts with existing physics
                bookshelf.physicsBody?.categoryBitMask = PhysicsCategories.wall
                bookshelf.physicsBody?.collisionBitMask = PhysicsCategories.floor
                bookshelf.physicsBody?.contactTestBitMask = 0
                
                // Bookshelf physics properties
                bookshelf.physicsBody?.mass = 10.0
                bookshelf.physicsBody?.restitution = 0.3
                bookshelf.physicsBody?.friction = 0.8
                bookshelf.physicsBody?.angularDamping = 0.2
                bookshelf.physicsBody?.linearDamping = 0.2
                
                // Impact velocity for bounce effect
                let impactSpeed: CGFloat = 150
                let sideImpact = fallAngle * 50
                let impactVelocity = CGVector(dx: sideImpact, dy: -impactSpeed)
                bookshelf.physicsBody?.velocity = impactVelocity
                bookshelf.physicsBody?.angularVelocity = fallAngle * 1.5
                
                // Remove physics after settling to restore normal game physics
                let settleAction = SKAction.sequence([
                    SKAction.wait(forDuration: 3.0),
                    SKAction.run {
                        bookshelf.physicsBody = nil
                    }
                ])
                bookshelf.run(settleAction, withKey: "settle")
            }
        }
    }
    
    private func cleanupCelebrationTiles() {
        DebugLogger.shared.ui("🧹 Cleaning up celebration tiles!")
        
        // CLEANUP PHASE: Just clean up tiles (effects already triggered in Phase 3 during darkness)
        DebugLogger.shared.ui("🧹 CLEANUP PHASE: Cleaning up \(newlyDroppedEmojiTiles.count) tiles (effects already triggered during darkness)")
        DebugLogger.shared.ui("🔍 DEBUG: cleanupCelebrationTiles() called - cleaning up after effects")
        
        // Reset for next game
        newlyDroppedEmojiTiles.removeAll()
        disableImmediateEmojiEffects = false
        DebugLogger.shared.ui("🔄 RESET: Cleared newly dropped tiles list and re-enabled immediate effects")
        
        // Reset effects flags on all emoji tiles for the next round
        children.forEach { node in
            if let emojiTile = node as? EmojiIconTile {
                emojiTile.resetEffectsFlag()
            }
        }
        DebugLogger.shared.ui("🔄 RESET: Reset effects flags on all emoji tiles for next round")
        
        // Remove common emoji tiles but keep rare collectibles
        children.forEach { node in
            if let emojiTile = node as? EmojiIconTile {
                // Handle different types of emoji tiles
                if emojiTile.name == "collectable_emoji" || emojiTile.name == "rare_collectable_emoji" {
                    DebugLogger.shared.ui("🌟 Keeping collectible emoji to persist between games: \(emojiTile.emoji)")
                    // Keep ALL collectible emojis from new system - they persist between games
                } else if emojiTile.name == "new_discovery_emoji" {
                    DebugLogger.shared.ui("🌟 Converting new discovery to regular collectible: \(emojiTile.emoji)")
                    // Change name so it won't glow in subsequent games
                    emojiTile.name = emojiTile.rarity?.triggersGlobalDrop == true ? "rare_collectable_emoji" : "collectable_emoji"
                    DebugLogger.shared.ui("✅ Converted to: \(emojiTile.name ?? "unknown")")
                } else if emojiTile.name == "core_celebration_emoji" {
                    // Legacy cleanup for old system
                    DebugLogger.shared.ui("🗑️ Removing legacy celebration emoji: \(emojiTile.emoji)")
                    let fadeOut = SKAction.fadeOut(withDuration: 0.5)
                    let remove = SKAction.removeFromParent()
                    let cleanup = SKAction.sequence([fadeOut, remove])
                    emojiTile.run(cleanup)
                    
                    if let tilesArray = allRespawnableTiles as? NSMutableArray {
                        tilesArray.remove(emojiTile)
                    }
                } else if emojiTile.name == "special_random_celebration_emoji" {
                    DebugLogger.shared.ui("🌟 Keeping legacy special emoji: \(emojiTile.emoji)")
                    // Keep legacy special emojis for backwards compatibility
                }
            }
            if let messageTile = node as? MessageTile {
                // Check if it's a congratulatory message tile
                if PhysicsGameScene.congratulatoryMessages.contains(messageTile.messageText) || messageTile.messageText == "Congratulations!" {
                    let fadeOut = SKAction.fadeOut(withDuration: 0.5)
                    let remove = SKAction.removeFromParent()
                    let cleanup = SKAction.sequence([fadeOut, remove])
                    messageTile.run(cleanup)
                    
                    // Also remove from respawnable tiles array
                    if let tilesArray = allRespawnableTiles as? NSMutableArray {
                        tilesArray.remove(messageTile)
                    }
                }
            }
        }
    }
    
    // MARK: - Emoji Age Management
    
    /// Converts any remaining new_discovery_emoji tiles to collectible status
    /// This must run BEFORE discovery detection to prevent duplicate discoveries
    private func convertNewDiscoveriesToCollectibles() {
        var conversions = 0
        
        for child in children {
            if let emojiTile = child as? EmojiIconTile {
                if emojiTile.name == "new_discovery_emoji" {
                    emojiTile.name = emojiTile.rarity?.triggersGlobalDrop == true ? "rare_collectable_emoji" : "collectable_emoji"
                    conversions += 1
                    DebugLogger.shared.ui("🔄 PRE-CONVERT: \(emojiTile.emoji) converted from new_discovery to \(emojiTile.name ?? "unknown") before discovery check")
                }
            }
        }
        
        if conversions > 0 {
            DebugLogger.shared.ui("🔄 PRE-CONVERT: Converted \(conversions) new_discovery tiles to collectible status for proper discovery detection")
        }
    }
    
    /// Increments the age of all existing emoji tiles by one game
    private func incrementEmojiTileAges() {
        var emojiTilesFound = 0
        var tilesAged = 0
        
        for child in children {
            if let emojiTile = child as? EmojiIconTile {
                emojiTilesFound += 1
                emojiTile.incrementAge()
                tilesAged += 1
            }
        }
        
        DebugLogger.shared.ui("⏰ AGE INCREMENT: Found \(emojiTilesFound) emoji tiles, aged \(tilesAged) tiles by one game")
    }
    
    /// Removes emoji tiles that have reached their maximum age
    private func cleanupOldEmojiTiles() {
        var tilesToRemove: [EmojiIconTile] = []
        var totalEmojiTiles = 0
        
        for child in children {
            if let emojiTile = child as? EmojiIconTile {
                totalEmojiTiles += 1
                if emojiTile.shouldCleanup() {
                    tilesToRemove.append(emojiTile)
                }
            }
        }
        
        DebugLogger.shared.ui("🧹 OLD EMOJI CLEANUP: Found \(totalEmojiTiles) emoji tiles, removing \(tilesToRemove.count) old tiles")
        
        // Remove old tiles with fade animation
        for tile in tilesToRemove {
            DebugLogger.shared.ui("🗑️ REMOVING OLD: \(tile.emoji) (age: \(tile.getCurrentAge()) games)")
            let fadeOut = SKAction.fadeOut(withDuration: 0.5)
            let remove = SKAction.removeFromParent()
            let cleanup = SKAction.sequence([fadeOut, remove])
            tile.run(cleanup)
        }
    }
    
    /// Ages all information tiles by one game
    private func incrementInformationTileAges() {
        var infoTilesFound = 0
        var tilesAged = 0
        
        for child in children {
            if let infoTile = child as? InformationTile {
                infoTilesFound += 1
                infoTile.incrementAge()
                tilesAged += 1
            }
        }
        
        DebugLogger.shared.ui("⏰ INFO AGE INCREMENT: Found \(infoTilesFound) information tiles, aged \(tilesAged) tiles by one game")
    }
    
    /// Removes information tiles that have reached their maximum age
    private func cleanupOldInformationTiles() {
        var tilesToRemove: [InformationTile] = []
        var totalInfoTiles = 0
        
        for child in children {
            if let infoTile = child as? InformationTile {
                totalInfoTiles += 1
                if infoTile.shouldCleanup() {
                    tilesToRemove.append(infoTile)
                }
            }
        }
        
        DebugLogger.shared.ui("🧹 OLD INFO CLEANUP: Found \(totalInfoTiles) information tiles, removing \(tilesToRemove.count) old tiles")
        
        // Remove old tiles with fade animation
        for tile in tilesToRemove {
            DebugLogger.shared.ui("🗑️ REMOVING OLD INFO: \(type(of: tile)) (age: \(tile.getCurrentAge()) games)")
            let fadeOut = SKAction.fadeOut(withDuration: 0.5)
            let remove = SKAction.removeFromParent()
            let cleanup = SKAction.sequence([fadeOut, remove])
            tile.run(cleanup)
        }
    }
    
    
    private func createFireworks() {
        // Keep the old method for backward compatibility, but it's now unused
        createRocketFireworks()
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        print("Touch began at: \(location)")
        
        // Find touched tile using SpriteKit's node detection
        let touchedNodes = nodes(at: location)
        print("Touched nodes: \(touchedNodes.map { type(of: $0) })")
        
        for node in touchedNodes {
            // Check if the node is a tile or contains a tile
            if let tile = node as? LetterTile {
                tile.isBeingDragged = true
                tile.physicsBody?.isDynamic = false
                // Trigger the spinning animation to correct orientation
                tile.touchesBegan(touches, with: event)
                print("Started dragging tile: \(tile.letter)")
                break
            } else if let scoreTile = node as? ScoreTile {
                scoreTile.isBeingDragged = true
                scoreTile.physicsBody?.isDynamic = false
                // Trigger the spinning animation to correct orientation
                scoreTile.touchesBegan(touches, with: event)
                print("Started dragging score tile")
                break
            } else if let languageTile = node as? LanguageTile {
                languageTile.isBeingDragged = true
                languageTile.physicsBody?.isDynamic = false
                // Trigger the spinning animation to correct orientation
                languageTile.touchesBegan(touches, with: event)
                print("Started dragging language tile")
                break
            } else if let messageTile = node as? MessageTile {
                messageTile.isBeingDragged = true
                messageTile.physicsBody?.isDynamic = false
                // Trigger the spinning animation to correct orientation
                messageTile.touchesBegan(touches, with: event)
                print("Started dragging message tile: \(messageTile.messageText)")
                break
            } else if let tile = tiles.first(where: { $0.contains(node) }) {
                tile.isBeingDragged = true
                tile.physicsBody?.isDynamic = false
                // Trigger the spinning animation to correct orientation
                tile.touchesBegan(touches, with: event)
                print("Started dragging tile (contains): \(tile.letter)")
                break
            }
        }
        
        // Alternative: Check direct distance to tiles
        for tile in tiles {
            let distance = sqrt(pow(location.x - tile.position.x, 2) + pow(location.y - tile.position.y, 2))
            if distance < 30 { // Within 30 points of tile center
                tile.isBeingDragged = true
                tile.physicsBody?.isDynamic = false
                print("Started dragging tile (by distance): \(tile.letter)")
                break
            }
        }
        
        // Check direct distance to score tile
        if let scoreTile = scoreTile {
            let distance = sqrt(pow(location.x - scoreTile.position.x, 2) + pow(location.y - scoreTile.position.y, 2))
            if distance < 30 { // Within 30 points of score tile center
                scoreTile.isBeingDragged = true
                scoreTile.physicsBody?.isDynamic = false
                print("Started dragging score tile (by distance)")
            }
        }
        
        // Check direct distance to language tile
        if let languageTile = languageTile {
            let distance = sqrt(pow(location.x - languageTile.position.x, 2) + pow(location.y - languageTile.position.y, 2))
            if distance < 30 { // Within 30 points of language tile center
                languageTile.isBeingDragged = true
                languageTile.physicsBody?.isDynamic = false
                print("Started dragging language tile (by distance)")
            }
        }
        
        // Check direct distance to message tiles
        for messageTile in messageTiles {
            let distance = sqrt(pow(location.x - messageTile.position.x, 2) + pow(location.y - messageTile.position.y, 2))
            if distance < 30 { // Within 30 points of message tile center
                messageTile.isBeingDragged = true
                messageTile.physicsBody?.isDynamic = false
                print("Started dragging message tile (by distance): \(messageTile.messageText)")
                break
            }
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        // Move dragged tile
        if let tile = tiles.first(where: { $0.isBeingDragged }) {
            tile.position = location
        }
        
        // Move dragged score tile
        if let scoreTile = scoreTile, scoreTile.isBeingDragged {
            scoreTile.position = location
        }
        
        // Move dragged language tile
        if let languageTile = languageTile, languageTile.isBeingDragged {
            languageTile.position = location
        }
        
        // Move dragged message tiles
        for messageTile in messageTiles {
            if messageTile.isBeingDragged {
                messageTile.position = location
                break
            }
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let _ = touches.first else { return }
        
        // Release dragged tile with NO velocity - tiles should not slide
        if let tile = tiles.first(where: { $0.isBeingDragged }) {
            tile.isBeingDragged = false
            tile.physicsBody?.isDynamic = true
            
            // Stop all movement immediately - no sliding
            tile.physicsBody?.velocity = CGVector.zero
            tile.physicsBody?.angularVelocity = 0
            
            print("Released tile: \(tile.letter) - stopped immediately")
            
            // Check solution after a brief delay to let physics settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.checkSolution()
            }
        }
        
        // Release dragged score tile
        if let scoreTile = scoreTile, scoreTile.isBeingDragged {
            scoreTile.isBeingDragged = false
            scoreTile.physicsBody?.isDynamic = true
            
            // Stop all movement immediately - no sliding
            scoreTile.physicsBody?.velocity = CGVector.zero
            scoreTile.physicsBody?.angularVelocity = 0
            
            print("Released score tile - stopped immediately")
        }
        
        // Release dragged language tile
        if let languageTile = languageTile, languageTile.isBeingDragged {
            languageTile.isBeingDragged = false
            languageTile.physicsBody?.isDynamic = true
            
            // Stop all movement immediately - no sliding
            languageTile.physicsBody?.velocity = CGVector.zero
            languageTile.physicsBody?.angularVelocity = 0
            
            print("Released language tile - stopped immediately")
        }
        
        // Release dragged message tiles
        for messageTile in messageTiles {
            if messageTile.isBeingDragged {
                messageTile.isBeingDragged = false
                messageTile.physicsBody?.isDynamic = true
                
                // Stop all movement immediately - no sliding
                messageTile.physicsBody?.velocity = CGVector.zero
                messageTile.physicsBody?.angularVelocity = 0
                
                print("Released message tile - stopped immediately: \(messageTile.messageText)")
                break
            }
        }
    }
}

#Preview {
    PhysicsGameView(gameModel: GameModel(), showingGame: .constant(true))
}