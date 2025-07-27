//
//  PhysicsGameView.swift
//  Anagram Game
//
//  Created by Fredrik Säfsten on 2025-07-05.
//

import SwiftUI
import SpriteKit
import CoreMotion

// Total Score Display Component
struct TotalScoreView: View {
    let totalScore: Int
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "trophy.fill")
                .foregroundColor(.yellow)
                .font(.system(size: 12))
            Text("\(totalScore)")
                .foregroundColor(.white)
                .font(.system(size: 14, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.7))
                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
        )
        .onChange(of: totalScore) { oldValue, newValue in
            print("🏆 UI: TotalScoreView updated from \(oldValue) to \(newValue)")
        }
    }
}

// Hint Button Component embedded in PhysicsGameView
struct HintButtonView: View {
    let phraseId: String
    let gameModel: GameModel
    let gameScene: PhysicsGameScene?
    let onHintUsed: (String) -> Void
    
    @State private var hintStatus: HintStatus?
    @State private var scorePreview: ScorePreview?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var level3ClueText: String? = nil
    @StateObject private var networkManager = NetworkManager.shared
    
    var body: some View {
        Group {
            if let clueText = level3ClueText {
                // Show persistent clue text after Level 3 is used
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                    
                    Text("Clue: \(clueText)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.yellow, lineWidth: 2)
                )
                .cornerRadius(20)
            } else {
                // Show hint button when Level 3 hasn't been used yet
                Button(action: useNextHint) {
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                        
                        Text(buttonText)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .disabled(isLoading || !canUseHint)
                .opacity(canUseHint ? 1.0 : 0.6)
            }
        }
        .onAppear {
            loadHintStatus()
        }
        .onChange(of: phraseId) { _, _ in
            level3ClueText = nil // Reset clue text for new phrase
            loadHintStatus()
        }
    }
    
    private var buttonText: String {
        if isLoading {
            return "Loading..."
        }
        
        guard let hintStatus = hintStatus else {
            return "Hint 1"
        }
        
        if !hintStatus.canUseNextHint {
            return "No more hints"
        }
        
        let nextLevel = hintStatus.nextHintLevel ?? 1
        let currentScore = hintStatus.currentScore
        let nextScore = hintStatus.nextHintScore ?? 0
        
        // Calculate point cost (difference between current and next score)
        let pointCost = currentScore - nextScore
        
        return "Hint \(nextLevel) (-\(pointCost) pts)"
    }
    
    private var canUseHint: Bool {
        // Always allow hints - let the server decide availability
        return !isLoading
    }
    
    private func loadHintStatus() {
        Task {
            isLoading = true
            errorMessage = nil
            
            // Handle local phrases differently
            if phraseId.hasPrefix("local-") {
                await MainActor.run {
                    // Get the actual difficulty score from gameModel
                    let actualScore = gameModel.phraseDifficulty
                    
                    // Create a basic hint status for local phrases with actual scoring
                    self.hintStatus = HintStatus(
                        hintsUsed: [],
                        nextHintLevel: 1,
                        hintsRemaining: 3,
                        currentScore: actualScore,
                        nextHintScore: GameModel.applyHintPenalty(baseScore: actualScore, hintsUsed: 1),
                        canUseNextHint: true
                    )
                    self.isLoading = false
                }
            } else {
                do {
                    async let statusTask = networkManager.getHintStatus(phraseId: phraseId)
                    async let previewTask = networkManager.getPhrasePreview(phraseId: phraseId)
                    
                    let status = await statusTask
                    let preview = await previewTask
                    
                    await MainActor.run {
                        self.hintStatus = status
                        self.scorePreview = preview?.phrase.scorePreview
                        
                        // Store difficulty in GameModel for local score calculation
                        if let difficulty = preview?.phrase.difficultyLevel {
                            self.gameModel.phraseDifficulty = difficulty
                        }
                        
                        self.isLoading = false
                    }
                }
            }
        }
    }
    
    private func useNextHint() {
        guard let hintStatus = hintStatus,
              let nextLevel = hintStatus.nextHintLevel else {
            return
        }
        
        Task {
            isLoading = true
            
            if phraseId.hasPrefix("local-") {
                // Generate local hints with proper scene interaction
                let hint = generateLocalHint(level: nextLevel, sentence: gameModel.currentSentence)
                
                await MainActor.run {
                    // For text hints (level 3), store clue text for persistent display
                    // For visual hints (levels 1 & 2), don't show notification
                    if nextLevel == 3 {
                        level3ClueText = hint
                    } else {
                        // Don't show notification for visual hints
                        gameModel.addHint(hint)
                    }
                    
                    // Update hint status for local phrases with proper scoring
                    let actualScore = gameModel.phraseDifficulty
                    let newScore = calculateLocalScore(currentLevel: nextLevel, originalScore: actualScore)
                    let nextHintScore = nextLevel < 3 ? calculateLocalScore(currentLevel: nextLevel + 1, originalScore: actualScore) : nil
                    
                    let updatedStatus = HintStatus(
                        hintsUsed: hintStatus.hintsUsed + [HintStatus.UsedHint(level: nextLevel, usedAt: Date())],
                        nextHintLevel: nextLevel < 3 ? nextLevel + 1 : nil,
                        hintsRemaining: hintStatus.hintsRemaining - 1,
                        currentScore: newScore,
                        nextHintScore: nextHintScore,
                        canUseNextHint: nextLevel < 3
                    )
                    self.hintStatus = updatedStatus
                    
                    // Update score and language tiles when hint is used
                    if let scene = gameScene {
                        scene.updateScoreTile(hintsUsed: updatedStatus.hintsUsed.count)
                        scene.updateLanguageTile()
                    }
                    
                    isLoading = false
                }
            } else {
                // Use server hints for custom phrases
                let hintResponse = await networkManager.useHint(phraseId: phraseId, level: nextLevel)
                
                await MainActor.run {
                    if let response = hintResponse {
                        // Call the appropriate scene method based on hint level
                        if let scene = gameScene {
                            switch nextLevel {
                            case 1:
                                scene.showHint1()
                            case 2:
                                scene.showHint2()
                            case 3:
                                scene.showHint3()
                            default:
                                break
                            }
                        }
                        
                        // For text hints (level 3), store clue text for persistent display
                        // For visual hints (levels 1 & 2), don't show text notification
                        if nextLevel == 3 {
                            level3ClueText = response.hint.content
                            gameModel.addHint(response.hint.content) // Also track hint usage for scoring
                        } else {
                            // Don't show notification for visual hints
                            gameModel.addHint(response.hint.content)
                        }
                        
                        // Update hint status based on response
                        let updatedStatus = HintStatus(
                            hintsUsed: response.hint.hintsRemaining < hintStatus.hintsRemaining ? 
                                hintStatus.hintsUsed + [HintStatus.UsedHint(level: nextLevel, usedAt: Date())] :
                                hintStatus.hintsUsed,
                            nextHintLevel: response.hint.nextHintScore != nil ? nextLevel + 1 : nil,
                            hintsRemaining: response.hint.hintsRemaining,
                            currentScore: response.hint.currentScore,
                            nextHintScore: response.hint.nextHintScore,
                            canUseNextHint: response.hint.canUseNextHint
                        )
                        self.hintStatus = updatedStatus
                        
                        // Update score and language tiles when hint is used
                        if let scene = gameScene {
                            scene.updateScoreTile(hintsUsed: updatedStatus.hintsUsed.count)
                            scene.updateLanguageTile()
                        }
                    } else {
                        errorMessage = "Failed to get hint"
                    }
                    
                    isLoading = false
                }
            }
        }
    }
    
    private func calculateLocalScore(currentLevel: Int, originalScore: Int) -> Int {
        return GameModel.applyHintPenalty(baseScore: originalScore, hintsUsed: currentLevel)
    }
    
    private func generateLocalHint(level: Int, sentence: String) -> String {
        guard let scene = gameScene else {
            return "Game scene not ready"
        }
        
        switch level {
        case 1:
            // Hint 1: Highlight shelves (visual hint)
            scene.showHint1()
            return "Shelves highlighted to show word count"
        case 2:
            // Hint 2: Highlight first letter tiles (visual hint)
            scene.showHint2()
            return "First letter tiles highlighted in blue"
        case 3:
            // Hint 3: Show text hint (use clue from local phrases or generate fallback)
            scene.showHint3()
            return generateLocalTextHint(sentence: sentence)
        default:
            return "No hint available"
        }
    }
    
    private func generateLocalTextHint(sentence: String) -> String {
        // First, try to get the clue from the GameModel
        if let clue = gameModel.getCurrentLocalClue() {
            return clue
        }
        
        // Fallback to generic hint if no clue is available
        let words = sentence.components(separatedBy: " ")
        let wordCount = words.count
        let totalLetters = sentence.replacingOccurrences(of: " ", with: "").count
        
        if wordCount == 1 {
            return "A single word with \(totalLetters) letters"
        } else if wordCount == 2 {
            let firstWordLength = words[0].count
            let secondWordLength = words[1].count
            return "Two words: \(firstWordLength) and \(secondWordLength) letters"
        } else if wordCount == 3 {
            let lengths = words.map { $0.count }
            return "Three words with \(lengths[0]), \(lengths[1]), and \(lengths[2]) letters"
        } else {
            return "\(wordCount) words with \(totalLetters) total letters"
        }
    }
}

// Physics collision categories for better collision detection
struct PhysicsCategories {
    static let tile: UInt32 = 0x1 << 0
    static let shelf: UInt32 = 0x1 << 1
    static let floor: UInt32 = 0x1 << 2
    static let wall: UInt32 = 0x1 << 3
}

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
                    // TOP ROW
                    HStack {
                        // Back to Lobby button - moved to top-left
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
                        .padding(.leading, 20)
                        .padding(.top, 10)
                        
                        Spacer() // Push right elements to the right
                        
                        // Score and Version Stack
                        VStack(spacing: 2) {
                            // Total Score Display
                            TotalScoreView(totalScore: gameModel.playerTotalScore)
                            
                            // Version number - directly below score
                            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                                .font(.caption)
                                .foregroundColor(.red)
                                .fontWeight(.bold)
                                .onTapGesture {
                                    if let scene = gameScene ?? PhysicsGameView.sharedScene {
                                        scene.triggerQuake()
                                    }
                                }
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 10)
                    }
                    
                    // MIDDLE - Game content and overlays
                    // Custom phrase info now handled by MessageTile spawning
                    
                    
                    
                    // Celebration text - Large and visible
                    if !celebrationMessage.isEmpty {
                        Text(celebrationMessage)
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(.yellow)
                            .shadow(color: .red, radius: 8, x: 4, y: 4)
                            .padding(30)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(20)
                            .scaleEffect(2.0)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.white.opacity(0.1))
                            .offset(y: -250)
                            .zIndex(3000)
                    }
                    
                    
                    Spacer() // Push bottom controls down
                    
                    // BOTTOM ROW - Clean layout inside ZStack
                    HStack(alignment: .bottom) {
                        // Bottom-left group: Skip + Send Phrase (stacked, left-aligned)
                        VStack(alignment: .leading, spacing: 10) {
                            // Skip button
                            Button(action: {
                                print("🔥🔥🔥 SKIP BUTTON TAPPED IN UI 🔥🔥🔥")
                                Task {
                                    isSkipping = true
                                    print("🔥 About to call gameModel.skipCurrentGame()")
                                    await gameModel.skipCurrentGame()
                                    print("🔥 Finished calling gameModel.skipCurrentGame()")
                                    // The GameModel.startNewGame() will handle scene updates automatically
                                    // Longer delay to ensure tile creation is fully complete
                                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                                    isSkipping = false
                                }
                            }) {
                                HStack {
                                    if isSkipping {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Loading...")
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
                            .disabled(isSkipping)
                            .opacity(isSkipping ? 0.6 : 1.0)
                            .offset(y: isJolting ? -8 : 0)
                            .animation(.easeInOut(duration: 0.15), value: isJolting)
                            
                            // Send Phrase button
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
                        }
                        .padding(.leading, 20)
                        
                        Spacer() // Push hint button to the right
                        
                        // Bottom-right: Hint button (aligned with Send Phrase button)
                        HintButtonView(phraseId: gameModel.currentPhraseId ?? "local-fallback", gameModel: gameModel, gameScene: gameScene ?? PhysicsGameView.sharedScene) { _ in
                            // No longer used - clue is now displayed persistently
                        }
                        .offset(y: isJolting ? -8 : 0)
                        .animation(.easeInOut(duration: 0.15), value: isJolting)
                        .padding(.trailing, 20)
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
            
            // Delay setup to ensure scene is created first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.setupGame()
            }
        }
        .onDisappear {
            motionManager.stopDeviceMotionUpdates()
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
            
            // Set up celebration callback
            sharedScene.onCelebration = { message in
                DispatchQueue.main.async {
                    self.celebrationMessage = message
                    // Clear after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                        self.celebrationMessage = ""
                    }
                }
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
    }
}

// Protocol for tiles that can be respawned when they go off-screen
protocol RespawnableTile: SKSpriteNode {
    var isBeingDragged: Bool { get set }
    var isSquashed: Bool { get set }
    func getTileMass() -> CGFloat
    func squashTile(intensity: CGFloat, direction: CGVector)
}

class PhysicsGameScene: SKScene, MessageTileSpawner {
    private let gameModel: GameModel
    var motionManager: CMMotionManager?
    var onCelebration: ((String) -> Void)?
    var onJolt: (() -> Void)?
    
    private var bookshelf: SKNode!
    private var bookshelfOriginalPosition: CGPoint = CGPoint.zero
    private var shelfOriginalPositions: [SKNode: CGPoint] = [:]
    private var physicsBodyOriginalPositions: [SKSpriteNode: CGPoint] = [:]
    private var isBookshelfJolting: Bool = false
    private var floor: SKNode!
    private var tiles: [LetterTile] = []
    private var scoreTile: ScoreTile?
    private var languageTile: LanguageTile?
    
    // Debug text area
    private var debugTextNode: SKLabelNode?
    private var debugBackground: SKShapeNode?
    private var debugMessages: [String] = []
    private let maxDebugMessages = 8
    private var messageTiles: [MessageTile] = []
    
    // Unified collection for respawn tracking
    private var allRespawnableTiles: [RespawnableTile] {
        var allTiles: [RespawnableTile] = []
        allTiles.append(contentsOf: tiles)
        allTiles.append(contentsOf: messageTiles)
        if let scoreTile = scoreTile { allTiles.append(scoreTile) }
        if let languageTile = languageTile { allTiles.append(languageTile) }
        return allTiles
    }
    private var shelves: [SKNode] = []  // Track individual shelves for hint system
    var celebrationText: String = ""

    private enum QuakeState { case none, normal, superQuake }
    private var quakeState: QuakeState = .none
    private var quakeEndAction: SKAction?
    
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
        Task {
            let debugMessage = "SCENE_CONNECTED: PhysicsGameScene connected as messageTileSpawner"
            guard let url = URL(string: "http://127.0.0.1:8080/api/debug/log") else { return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let logData = [
                "message": debugMessage,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "playerId": "scene-connection"
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: logData)
                request.httpBody = jsonData
                let _ = try await URLSession.shared.data(for: request)
            } catch {
                print("Scene connection debug logging failed: \(error)")
            }
        }
        
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
        floor.position = CGPoint(x: size.width / 2, y: size.height * 0.15 + 50)
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
        bookshelfOriginalPosition = CGPoint(x: size.width / 2, y: size.height * 0.4 + 70)
        bookshelf.position = bookshelfOriginalPosition
        addChild(bookshelf)
        
        let shelfWidth: CGFloat = size.width * 0.675  // Reduced by 10% from 0.75 to 0.675
        let shelfHeight: CGFloat = 374  // Increased by 56% total (240 * 1.3 * 1.2)
        let shelfDepth: CGFloat = 50
        
        // Create bookshelf frame structure
        createBookshelfFrame(width: shelfWidth, height: shelfHeight, depth: shelfDepth)
        
        // Clear shelves array for clean setup
        shelves.removeAll()
        
        // Create multiple shelves with proper wood grain appearance
        for i in 0..<4 {
            let shelfY = CGFloat(-140 + (i * 103))  // Increased spacing by 10% from 94 to 103
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
        
        // Create tiles for current sentence
        let letters = gameModel.scrambledLetters
        let tileSize = CGSize(width: 40, height: 40)
        
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
        
        // Create score tile - rectangular and falls down like other tiles
        let scoreTileSize = CGSize(width: 100, height: 40)  // Wider to fit 3-digit numbers + " pts"
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
        
        // Spawn debug tile showing phrase source (after cleanup, persists with score tile)
        let debugMessage = "Source: \(gameModel.debugPhraseSource)"
        spawnMessageTile(message: debugMessage)
        print("🐛 Spawned debug tile in resetGame: \(debugMessage)")
        
        // Create language tile - same size as letter tiles (40x40)
        let languageTileSize = CGSize(width: 40, height: 40)  // Same as letter tiles
        let currentLanguage = getCurrentPhraseLanguage()
        languageTile = LanguageTile(size: languageTileSize, language: currentLanguage)
        
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
        return GameModel.applyHintPenalty(baseScore: gameModel.phraseDifficulty, hintsUsed: actualHintsUsed)
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
            await sendDebugToServer("SCORE_TILE_UPDATE: phrase='\(gameModel.currentSentence)' displayed_difficulty=\(difficulty) actual_difficulty=\(actualDifficulty) current_score=\(currentScore)")
        }
        
        // Special logging for 100-point bugs
        if difficulty == 100 {
            print("🔍 DEBUG: BUG_100_POINTS: '\(gameModel.currentSentence)' showing 100pts but should be \(actualDifficulty)")
            Task {
                await sendDebugToServer("BUG_100_POINTS: '\(gameModel.currentSentence)' showing 100pts but should be \(actualDifficulty)")
            }
        }
    }
    
    func updateLanguageTile() {
        let newLanguage = getCurrentPhraseLanguage()
        languageTile?.updateFlag(language: newLanguage)
        print("Language tile updated to: \(newLanguage)")
    }
    
    // Send debug message to server
    private func sendDebugToServer(_ message: String) async {
        guard let url = URL(string: "\(AppConfig.baseURL)/api/debug/log") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let logData = [
            "message": message,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "playerId": gameModel.playerId ?? "unknown"
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: logData)
            request.httpBody = jsonData
            let _ = try await URLSession.shared.data(for: request)
        } catch {
            print("Debug logging failed: \(error)")
        }
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
    
    func triggerQuickQuake() {
        triggerQuakeWithDuration(0.5)
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
        let shelfWidth: CGFloat = size.width * 0.675 - 20  // Match actual shelf width
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
        for i in 0..<min(wordCount, shelves.count) {
            lightUpShelf(shelves[i], wordIndex: i)
        }
        
        // Apply jolt effect when hint is used
        joltPlayingField()
    }
    
    func showHint2() {
        // Hint 2: Highlight first letter tiles
        // Only clear tile hints, preserve shelf highlights from Hint 1
        clearTileHints()
        highlightFirstLetterTiles()
        
        // Apply jolt effect when hint is used
        joltPlayingField()
    }
    
    func showHint3() {
        // Hint 3: Don't clear tile highlights - preserve blue highlighting from Hint 2
        // Only show text hint, maintain all visual hints from previous levels
        
        // Apply jolt effect when hint is used
        joltPlayingField()
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
        
        print("📚 BOOKSHELF: Applied jolt animation with position reset")
    }
    
    private func forcePhysicsBodySync() {
        // Reset bookshelf to original position first
        bookshelf.position = bookshelfOriginalPosition
        
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
        
        print("🔍 HINT2: Expected words: \(expectedWords)")
        print("🔍 HINT2: Looking for first letters: \(firstLettersNeeded)")
        print("🔍 HINT2: Total tiles available: \(tiles.count)")
        
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
                
                print("🔍 HINT2: Checking tile with letter: '\(tileChar)'")
                
            // Check if this tile contains a first letter we still need
            if let index = remainingLetters.firstIndex(of: tileChar) {
                print("✅ HINT2: Highlighting tile with letter: '\(tileChar)'")
                highlightTile(tile)
                highlightedCount += 1
                // Remove this letter from remaining list to avoid highlighting duplicates
                remainingLetters.remove(at: index)
            }
        }
        
        print("🔍 HINT2: Successfully highlighted \(highlightedCount) tiles")
        print("🔍 HINT2: Still need letters: \(remainingLetters)")
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
        let originalPosition = CGPoint(x: size.width / 2, y: size.height * 0.4 + 70)
        let returnToOriginalPosition = SKAction.move(to: originalPosition, duration: 0.3)
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
        
        // Add server debug logging - create a simple debug endpoint call
        Task {
            let debugMessage = "SCENE_RESET_CALLED: PhysicsGameScene.resetGame() started"
            guard let url = URL(string: "http://127.0.0.1:8080/api/debug/log") else { return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let logData = [
                "message": debugMessage,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "playerId": "scene-debug"
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: logData)
                request.httpBody = jsonData
                let _ = try await URLSession.shared.data(for: request)
            } catch {
                print("Scene debug logging failed: \(error)")
            }
        }
        
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
            tile.removeFromParent()
        }
        tiles.removeAll()
        
        print("🗑️ Clearing \(messageTiles.count) existing message tiles")
        for messageTile in messageTiles {
            messageTile.removeFromParent()
        }
        messageTiles.removeAll()
        
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
        
        // Debug: Send tile cleanup details to server
        Task {
            let debugMessage = "SCENE_CLEANUP: Removed \(removedCount) orphaned tiles, scene now has \(children.count) children"
            guard let url = URL(string: "http://127.0.0.1:8080/api/debug/log") else { return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let logData = [
                "message": debugMessage,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "playerId": "scene-cleanup"
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: logData)
                request.httpBody = jsonData
                let _ = try await URLSession.shared.data(for: request)
            } catch {
                print("Scene cleanup debug logging failed: \(error)")
            }
        }
        
        // Stop any ongoing physics effects
        removeAction(forKey: "quakeForces")
        quakeState = .none
        
        // Reset bookshelf position and rotation in case quake was active
        bookshelf.removeAllActions()
        let originalPosition = CGPoint(x: size.width / 2, y: size.height * 0.4 + 70)
        bookshelf.position = originalPosition
        bookshelf.zRotation = 0
        
        // Create new tiles with current game model data (don't call startNewGame again)
        createTiles()
        
        // Spawn MessageTile if there's a custom phrase
        if !gameModel.customPhraseInfo.isEmpty {
            spawnMessageTile(message: gameModel.customPhraseInfo)
        }
        
        print("✅ Scene reset complete - \(tiles.count) new tiles created")
        
        // Notify that scene reset is completely finished
        Task {
            let debugMessage = "SCENE_RESET_COMPLETE: Scene reset and tile creation finished, \(tiles.count) tiles created"
            guard let url = URL(string: "http://127.0.0.1:8080/api/debug/log") else { return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let logData = [
                "message": debugMessage,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "playerId": "scene-complete"
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: logData)
                request.httpBody = jsonData
                let _ = try await URLSession.shared.data(for: request)
            } catch {
                print("Scene complete debug logging failed: \(error)")
            }
        }
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
    
    private func triggerCelebration() {
        // Random congratulatory messages
        let messages = [
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
        
        let randomMessage = messages.randomElement() ?? "Congratulations!"
        print("🎊 DEBUG: gameModel.currentScore = \(gameModel.currentScore)")
        print("🎊 DEBUG: gameModel.phraseDifficulty = \(gameModel.phraseDifficulty)")
        print("🎊 DEBUG: gameModel.hintsUsed = \(gameModel.hintsUsed)")
        let scoreText = gameModel.currentScore > 0 ? "\n\(gameModel.currentScore) points!" : ""
        let fullMessage = "\(randomMessage)\(scoreText)"
        print("🎉 \(fullMessage)")
        
        // Show celebration message on screen
        celebrationText = "🎉 \(fullMessage)"
        print("🎊 CELEBRATION TEXT SET: '\(celebrationText)'")
        print("🎊 CELEBRATION TEXT EMPTY? \(celebrationText.isEmpty)")
        
        // Trigger SwiftUI celebration display
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onCelebration?(fullMessage)
            print("🎊 TRIGGERED SWIFTUI CELEBRATION: '\(fullMessage)'")
        }
        
        // Create fireworks effect
        createFireworks()
        
        // Automatically start the next game after a delay
        let startNewGameAction = SKAction.sequence([
            SKAction.wait(forDuration: 4.0), // Allow time for celebration
            SKAction.run { [weak self] in
                self?.startNewGame()
            }
        ])
        run(startNewGameAction)
        
        // Play celebration sound effect (if we had audio)
        // AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) // Haptic feedback
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
    
    private func createFireworks() {
        print("🎆 Creating fireworks!")
        
        for i in 0..<6 {
            // Create simple colored circles as fireworks instead of particle systems
            let firework = SKShapeNode(circleOfRadius: 8)
            
            // Random position across screen
            let randomX = CGFloat.random(in: size.width * 0.2...size.width * 0.8)
            let randomY = CGFloat.random(in: size.height * 0.6...size.height * 0.9)
            firework.position = CGPoint(x: randomX, y: randomY)
            
            // Random bright colors
            let colors: [UIColor] = [.red, .blue, .green, .yellow, .orange, .purple, .cyan, .magenta]
            firework.fillColor = colors.randomElement() ?? .yellow
            firework.strokeColor = .white
            firework.lineWidth = 2
            firework.zPosition = 100
            
            addChild(firework)
            
            // Animate the firework: scale up, fade out, and remove
            let scaleUp = SKAction.scale(to: 3.0, duration: 0.5)
            let fadeOut = SKAction.fadeOut(withDuration: 1.0)
            let remove = SKAction.removeFromParent()
            let sequence = SKAction.sequence([
                SKAction.wait(forDuration: Double(i) * 0.2), // Stagger the fireworks
                SKAction.group([scaleUp, fadeOut]),
                remove
            ])
            
            firework.run(sequence)
            print("🎆 Added firework \(i) at position \(firework.position)")
        }
        
        // Add some sparkle effects around the screen
        for i in 0..<12 {
            let sparkle = SKShapeNode(circleOfRadius: 3)
            sparkle.position = CGPoint(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height)
            )
            sparkle.fillColor = .white
            sparkle.alpha = 0.8
            sparkle.zPosition = 99
            
            addChild(sparkle)
            
            let twinkle = SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.3),
                SKAction.fadeIn(withDuration: 0.3)
            ])
            let repeatAction = SKAction.repeat(twinkle, count: 3)
            let remove = SKAction.removeFromParent()
            
            sparkle.run(SKAction.sequence([
                SKAction.wait(forDuration: Double(i) * 0.1),
                repeatAction,
                remove
            ]))
        }
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
                print("Started dragging tile: \(tile.letter)")
                break
            } else if let scoreTile = node as? ScoreTile {
                scoreTile.isBeingDragged = true
                scoreTile.physicsBody?.isDynamic = false
                print("Started dragging score tile")
                break
            } else if let languageTile = node as? LanguageTile {
                languageTile.isBeingDragged = true
                languageTile.physicsBody?.isDynamic = false
                print("Started dragging language tile")
                break
            } else if let messageTile = node as? MessageTile {
                messageTile.isBeingDragged = true
                messageTile.physicsBody?.isDynamic = false
                print("Started dragging message tile: \(messageTile.messageText)")
                break
            } else if let tile = tiles.first(where: { $0.contains(node) }) {
                tile.isBeingDragged = true
                tile.physicsBody?.isDynamic = false
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

class LetterTile: SKSpriteNode, RespawnableTile {
    let letter: String
    var isBeingDragged = false
    private var frontFace: SKShapeNode?
    private var originalFrontColor: UIColor = .systemYellow
    var isSquashed = false
    private var originalScale: CGFloat = 1.0
    
    // Weight based on tile dimensions (width * height)
    private func getMassForTile() -> CGFloat {
        let tileArea = size.width * size.height
        // Base mass proportional to area (40x40 = 1600, so base mass = 1600/1600 = 1.0)
        return tileArea / 1600.0
    }
    
    
    init(letter: String, size: CGSize) {
        self.letter = letter.uppercased()
        
        super.init(texture: nil, color: .clear, size: size)
        
        let tileWidth = size.width
        let tileHeight = size.height
        let depth: CGFloat = 6
        
        
        // Create the main tile body (top surface) - lighter yellow for top lighting
        let topFace = SKShapeNode()
        let topPath = CGMutablePath()
        topPath.move(to: CGPoint(x: -tileWidth / 2, y: tileHeight / 2))
        topPath.addLine(to: CGPoint(x: tileWidth / 2, y: tileHeight / 2))
        topPath.addLine(to: CGPoint(x: tileWidth / 2 + depth, y: tileHeight / 2 + depth))
        topPath.addLine(to: CGPoint(x: -tileWidth / 2 + depth, y: tileHeight / 2 + depth))
        topPath.closeSubpath()
        topFace.path = topPath
        topFace.fillColor = UIColor(red: 1.0, green: 1.0, blue: 0.8, alpha: 1.0)  // Very bright almost white yellow
        topFace.strokeColor = .black
        topFace.lineWidth = 2
        topFace.zPosition = -0.1  // Put tile roofs in background
        addChild(topFace)
        
        // Create the front face (main visible surface)
        let frontFace = SKShapeNode()
        let frontPath = CGMutablePath()
        frontPath.move(to: CGPoint(x: -tileWidth / 2, y: -tileHeight / 2))
        frontPath.addLine(to: CGPoint(x: tileWidth / 2, y: -tileHeight / 2))
        frontPath.addLine(to: CGPoint(x: tileWidth / 2, y: tileHeight / 2))
        frontPath.addLine(to: CGPoint(x: -tileWidth / 2, y: tileHeight / 2))
        frontPath.closeSubpath()
        frontFace.path = frontPath
        frontFace.fillColor = .systemYellow
        frontFace.strokeColor = .black
        frontFace.lineWidth = 2
        frontFace.zPosition = 0.1
        self.frontFace = frontFace  // Store reference for hint system
        addChild(frontFace)
        
        // Create the right face (shadow side - darker)
        let rightFace = SKShapeNode()
        let rightPath = CGMutablePath()
        rightPath.move(to: CGPoint(x: tileWidth / 2, y: tileHeight / 2))
        rightPath.addLine(to: CGPoint(x: tileWidth / 2, y: -tileHeight / 2))
        rightPath.addLine(to: CGPoint(x: tileWidth / 2 + depth, y: -tileHeight / 2 + depth))
        rightPath.addLine(to: CGPoint(x: tileWidth / 2 + depth, y: tileHeight / 2 + depth))
        rightPath.closeSubpath()
        rightFace.path = rightPath
        rightFace.fillColor = UIColor(red: 0.2, green: 0.1, blue: 0.0, alpha: 1.0)  // Very dark shadow side
        rightFace.strokeColor = UIColor(red: 0.1, green: 0.05, blue: 0.0, alpha: 1.0)
        rightFace.lineWidth = 2
        rightFace.zPosition = 0.0
        addChild(rightFace)
        
        // Create 3D embossed letter on the front face
        createEmbossedLetter(on: frontFace, letter: self.letter, tileSize: size)
        
        // Physics body accounting for 3D depth so tiles can rest on their sides
        let physicsSize = CGSize(width: size.width + depth, height: size.height + depth)
        physicsBody = SKPhysicsBody(rectangleOf: physicsSize)
        physicsBody?.isDynamic = true
        physicsBody?.friction = 1.0  // Maximum friction
        physicsBody?.restitution = 0.0  // No bouncing at all
        physicsBody?.mass = getMassForTile()  // Dimension-based weight
        physicsBody?.linearDamping = 0.99  // Maximum damping - stops movement immediately
        physicsBody?.angularDamping = 0.99  // Maximum angular damping - stops rotation immediately
        physicsBody?.affectedByGravity = true  // Explicitly enable gravity
        
        // Improved collision detection categories
        physicsBody?.categoryBitMask = PhysicsCategories.tile
        physicsBody?.contactTestBitMask = PhysicsCategories.tile | PhysicsCategories.shelf | PhysicsCategories.floor
        physicsBody?.collisionBitMask = PhysicsCategories.tile | PhysicsCategories.shelf | PhysicsCategories.floor
        
        // Prevent tiles from getting stuck together
        physicsBody?.allowsRotation = true
        physicsBody?.density = 1.0
        
        // Set z-position based on Y coordinate for proper stacking (will be updated dynamically)
        zPosition = 50
    }
    
    func updateVisualForRotation() {
        // Adjust the visual offset of 3D faces based on rotation to appear properly resting
        let rotation = zRotation
        let depth: CGFloat = 6
        
        // Calculate offset to make the tile appear to rest on its actual contact point
        let offsetX = sin(rotation) * depth * 0.5
        let offsetY = -abs(cos(rotation)) * depth * 0.3  // Always slightly down to appear resting
        
        // Apply offset to all child nodes (the 3D faces)
        for child in children {
            if child is SKShapeNode {
                // Reset to original position then apply rotation-based offset
                child.position = CGPoint(x: offsetX, y: offsetY)
            } else if child is SKLabelNode {
                // Keep letter centered but also apply offset
                child.position = CGPoint(x: offsetX, y: offsetY)
            }
        }
    }
    
    private func createEmbossedLetter(on surface: SKShapeNode, letter: String, tileSize: CGSize) {
        // Create main letter with good contrast
        let letterLabel = SKLabelNode(text: letter)
        letterLabel.fontSize = 24
        letterLabel.fontName = "HelveticaNeue-Bold"
        letterLabel.fontColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)  // Dark text
        letterLabel.verticalAlignmentMode = .center
        letterLabel.horizontalAlignmentMode = .center
        letterLabel.position = CGPoint(x: 0, y: 0)
        letterLabel.zPosition = 10.0 // Much higher z-position to ensure visibility
        
        // Add letter to the main tile node instead of just the surface
        // This ensures it's always visible regardless of shape rendering issues
        self.addChild(letterLabel)
        
        // Debug weight labels disabled
    }
    
    // Hint system methods
    func highlightFrontFace() {
        frontFace?.fillColor = .systemBlue
    }
    
    func restoreFrontFace() {
        frontFace?.fillColor = originalFrontColor
    }
    
    // Directional squashing animation based on collision direction
    func squashTile(intensity: CGFloat = 1.0, direction: CGVector = CGVector(dx: 0, dy: -1)) {
        guard !isSquashed else { return }
        
        isSquashed = true
        originalScale = 1.0  // Always use 1.0 as the original scale
        
        // Calculate squashing based on collision direction
        let absDirectionX = abs(direction.dx)
        let absDirectionY = abs(direction.dy)
        
        // Determine primary squashing axis based on collision direction
        let squashFactor = 0.2 + (intensity * 0.3)  // Base squash: 0.2 to 0.5
        let stretchFactor = 0.1 + (intensity * 0.2)  // Base stretch: 0.1 to 0.3
        
        var scaleX: CGFloat = 1.0
        var scaleY: CGFloat = 1.0
        
        // Vertical impact (from above/below) - squash vertically, stretch horizontally
        if absDirectionY > absDirectionX {
            scaleY = 1.0 - squashFactor  // Compress vertically
            scaleX = 1.0 + stretchFactor  // Stretch horizontally
        }
        // Horizontal impact (from sides) - squash horizontally, stretch vertically
        else {
            scaleX = 1.0 - squashFactor  // Compress horizontally
            scaleY = 1.0 + stretchFactor  // Stretch vertically
        }
        
        // Debug info will be handled by the collision handler
        
        // Quick compression animation with automatic restore
        let squashAction = SKAction.group([
            SKAction.scaleX(to: scaleX, duration: 0.1),
            SKAction.scaleY(to: scaleY, duration: 0.1)
        ])
        
        let restoreAction = SKAction.group([
            SKAction.scaleX(to: 1.0, duration: 0.15),
            SKAction.scaleY(to: 1.0, duration: 0.15)
        ])
        
        let sequence = SKAction.sequence([squashAction, SKAction.wait(forDuration: 0.2), restoreAction])
        
        run(sequence) {
            // Reset squashed state after animation completes
            self.isSquashed = false
        }
    }
    
    // Bounce back animation with elastic effect
    func unsquashTile() {
        guard isSquashed else { return }
        
        isSquashed = false
        
        // Elastic bounce back with slight overshoot
        let restoreAction = SKAction.group([
            SKAction.scaleX(to: originalScale * 1.05, duration: 0.15),
            SKAction.scaleY(to: originalScale * 1.05, duration: 0.15)
        ])
        
        let settleAction = SKAction.group([
            SKAction.scaleX(to: originalScale, duration: 0.15),
            SKAction.scaleY(to: originalScale, duration: 0.15)
        ])
        
        let bounceSequence = SKAction.sequence([restoreAction, settleAction])
        run(bounceSequence)
    }
    
    // Get the mass of this tile for collision calculations
    func getTileMass() -> CGFloat {
        return physicsBody?.mass ?? getMassForTile()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension PhysicsGameScene: SKPhysicsContactDelegate {
    func didBegin(_ contact: SKPhysicsContact) {
        let bodyA = contact.bodyA
        let bodyB = contact.bodyB
        
        // Check for tile-on-tile vertical collisions (any RespawnableTile)
        if let tileA = bodyA.node as? RespawnableTile,
           let tileB = bodyB.node as? RespawnableTile {
            
            handleTileCollision(tileA: tileA, tileB: tileB, contact: contact)
        }
        
        // Check for tile-shelf collisions for jolting effects
        if (bodyA.categoryBitMask == PhysicsCategories.tile && bodyB.categoryBitMask == PhysicsCategories.shelf) ||
           (bodyA.categoryBitMask == PhysicsCategories.shelf && bodyB.categoryBitMask == PhysicsCategories.tile) {
            
            let tile = bodyA.categoryBitMask == PhysicsCategories.tile ? bodyA.node as? RespawnableTile : bodyB.node as? RespawnableTile
            handleShelfCollision(tile: tile, contact: contact)
        }
        
        // Handle word formation (existing logic would go here)
    }
    
    private func calculateCollisionDirection(upperTile: RespawnableTile, lowerTile: RespawnableTile, contact: SKPhysicsContact) -> CGVector {
        // Get collision normal (direction of impact)
        let collisionNormal = contact.contactNormal
        
        // Consider tile rotation - if tile is rotated, adjust the collision direction
        let tileRotation = lowerTile.zRotation
        
        // Calculate the collision direction relative to the tile's orientation
        let cos = cosf(Float(tileRotation))
        let sin = sinf(Float(tileRotation))
        
        // Rotate the collision normal by the tile's rotation to get local collision direction
        let localX = collisionNormal.dx * CGFloat(cos) + collisionNormal.dy * CGFloat(sin)
        let localY = -collisionNormal.dx * CGFloat(sin) + collisionNormal.dy * CGFloat(cos)
        
        // Normalize and return the local collision direction
        let magnitude = sqrt(localX * localX + localY * localY)
        if magnitude > 0 {
            return CGVector(dx: localX / magnitude, dy: localY / magnitude)
        }
        
        // Default to vertical collision if calculation fails
        return CGVector(dx: 0, dy: -1)
    }
    
    private func handleTileCollision(tileA: RespawnableTile, tileB: RespawnableTile, contact: SKPhysicsContact) {
        // Determine which tile is above and which is below based on vertical position
        let upperTile = tileA.position.y > tileB.position.y ? tileA : tileB
        let lowerTile = tileA.position.y > tileB.position.y ? tileB : tileA
        
        // Check if this is a vertical collision (falling tile landing on another)
        let verticalVelocity = upperTile.physicsBody?.velocity.dy ?? 0
        let upperMass = upperTile.getTileMass()
        let lowerMass = lowerTile.getTileMass()
        
        // Additional checks to prevent squashing loops
        let yPositionDiff = upperTile.position.y - lowerTile.position.y
        let isProperVerticalImpact = yPositionDiff > 20  // Upper tile must be significantly above
        let isUpperTileFalling = verticalVelocity < -15  // Higher threshold for genuine falling
        
        // Check if lower tile is already squashed (prevent loops)
        let isLowerTileSquashed = lowerTile.isSquashed
        
        // Debug: Show all tile collisions with detailed weight info
        let upperTileDesc = (upperTile as? LetterTile)?.letter ?? "SCORE"
        let lowerTileDesc = (lowerTile as? LetterTile)?.letter ?? "SCORE"
        addDebugMessage("COLLISION: \(upperTileDesc) (\(upperMass)) -> \(lowerTileDesc) (\(lowerMass)) vel: \(String(format: "%.1f", verticalVelocity))")
        
        // Only trigger squashing for proper vertical impacts from above
        if isProperVerticalImpact && isUpperTileFalling && !isLowerTileSquashed {
            // Heavy tile landing on light tile = squashing effect
            if upperMass > lowerMass {
                let weightDifference = max(upperMass - lowerMass, 0.1) // Minimum intensity of 0.1
                let intensity = min(weightDifference / 0.5, 1.0) // Scale for new mass ranges
                
                // Debug: Show detailed squashing calculation
                addDebugMessage("WEIGHT DIFF: \(String(format: "%.2f", weightDifference)), intensity: \(String(format: "%.2f", intensity))")
                addDebugMessage("🔥 SQUASH TRIGGERED!")
                showDebugMessage("SQUASH! \(upperTileDesc) -> \(lowerTileDesc)", at: upperTile.position)
                
                // Calculate collision direction for directional squashing
                let collisionDirection = calculateCollisionDirection(upperTile: upperTile, lowerTile: lowerTile, contact: contact)
                
                // Debug: Show collision direction and tile rotation
                addDebugMessage("DIR: dx=\(String(format: "%.2f", collisionDirection.dx)), dy=\(String(format: "%.2f", collisionDirection.dy))")
                addDebugMessage("TILE ROT: \(String(format: "%.2f", lowerTile.zRotation)) rad")
                
                // Squash the lower tile with direction
                lowerTile.squashTile(intensity: intensity, direction: collisionDirection)
                
                // Play squash sound effect
                playSquashSound(intensity: intensity)
                
                // Squashing animation includes auto-restore, no need for separate unsquash call
            } else {
                addDebugMessage("NO SQUASH: \(upperMass) < \(lowerMass) (not heavy enough)")
            }
        } else {
            addDebugMessage("NO SQUASH: vel \(String(format: "%.1f", verticalVelocity)) >= -3 (too slow)")
        }
    }
    
    private func handleShelfCollision(tile: RespawnableTile?, contact: SKPhysicsContact) {
        guard let tile = tile else { return }
        
        // Skip collision handling if bookshelf is currently jolting
        if isBookshelfJolting {
            return
        }
        
        // Calculate impact force based on mass and velocity
        let velocity = tile.physicsBody?.velocity.dy ?? 0
        let mass = tile.getTileMass()
        let impactForce = abs(velocity) * mass
        
        // Much more sensitive to heavy tiles - lower thresholds for score tiles
        let forceThreshold: CGFloat = mass > 2.0 ? 22.46 : 67.39  // Increased by 30% (17.28→22.46, 51.84→67.39)
        
        // Trigger shelf jolting for heavy impacts
        if impactForce > forceThreshold {
            let intensity = min(impactForce / 30, 1.0)  // More dramatic jolting
            
            // Debug: Show shelf impact info
            let tileDesc = (tile as? LetterTile)?.letter ?? "SCORE"
            addDebugMessage("⚡ SHELF: \(tileDesc) (\(String(format: "%.1f", mass))) force: \(String(format: "%.1f", impactForce))")
            showDebugMessage("SHELF JOLT! \(tileDesc)", at: tile.position)
            
            // Use the same dramatic jolting effect as hints
            joltPlayingField()
            
            // Play impact sound effect
            playImpactSound(intensity: intensity)
            
            // Dramatically reduce tile velocity to prevent continuous jolting
            if let physicsBody = tile.physicsBody {
                let dampingFactor: CGFloat = 0.1  // Reduce velocity to 10% of original
                physicsBody.velocity = CGVector(dx: physicsBody.velocity.dx * dampingFactor, 
                                              dy: physicsBody.velocity.dy * dampingFactor)
                
                // Also reduce angular velocity to prevent spinning
                physicsBody.angularVelocity *= dampingFactor
            }
        }
    }
    
    private func triggerShelfJolt(nearPosition: CGPoint, intensity: CGFloat) {
        // Find the nearest shelf to the impact position
        var closestShelf: SKNode?
        var closestDistance: CGFloat = CGFloat.infinity
        
        for shelf in shelves {
            let distance = abs(shelf.position.y - nearPosition.y)
            if distance < closestDistance {
                closestDistance = distance
                closestShelf = shelf
            }
        }
        
        guard let shelf = closestShelf, closestDistance < 100 else { return }
        
        // Create shelf vibration effect - much more dramatic for heavy tiles
        let joltIntensity = intensity * 15.0  // More dramatic jolting
        let joltDuration = 0.4 + (intensity * 0.4)  // Much longer jolts for harder impacts
        
        // Create rapid oscillation effect
        let _ = SKAction.moveBy(x: -joltIntensity, y: 0, duration: 0.02)
        let _ = SKAction.moveBy(x: joltIntensity * 2, y: 0, duration: 0.04)
        let _ = SKAction.moveBy(x: -joltIntensity, y: 0, duration: 0.02)
        
        // Create a sequence of jolts with diminishing intensity
        var joltSequence: [SKAction] = []
        let joltCycles = Int(joltDuration / 0.08)  // Number of oscillations
        
        for i in 0..<joltCycles {
            let diminish = CGFloat(joltCycles - i) / CGFloat(joltCycles)  // Decay effect
            let currentJoltLeft = SKAction.moveBy(x: -joltIntensity * diminish, y: 0, duration: 0.02)
            let currentJoltRight = SKAction.moveBy(x: joltIntensity * 2 * diminish, y: 0, duration: 0.04)
            let currentJoltCenter = SKAction.moveBy(x: -joltIntensity * diminish, y: 0, duration: 0.02)
            
            joltSequence.append(contentsOf: [currentJoltLeft, currentJoltRight, currentJoltCenter])
        }
        
        // Run the jolting animation
        let fullJoltSequence = SKAction.sequence(joltSequence)
        shelf.run(fullJoltSequence)
        
        // Create ripple effect on nearby tiles for heavy impacts
        if intensity > 0.5 {  // Only for significant impacts
            createShelfRippleEffect(impactPosition: nearPosition, intensity: intensity)
        }
        
        // Create ripple effect on adjacent tiles
        triggerRippleEffect(nearPosition: nearPosition, intensity: intensity)
    }
    
    private func createShelfRippleEffect(impactPosition: CGPoint, intensity: CGFloat) {
        // Find tiles near the impact position on the shelf
        let rippleRadius: CGFloat = 100.0 + (intensity * 50.0)  // Wider ripple for heavier impacts
        
        for tile in tiles {
            let distance = sqrt(pow(tile.position.x - impactPosition.x, 2) + pow(tile.position.y - impactPosition.y, 2))
            
            if distance < rippleRadius {
                // Calculate ripple intensity based on distance (closer = stronger)
                let rippleIntensity = intensity * (1.0 - distance / rippleRadius)
                
                // Apply a brief impulse to the tile
                let impulseX = CGFloat.random(in: -rippleIntensity...rippleIntensity) * 20.0
                let impulseY = CGFloat.random(in: 0...rippleIntensity) * 10.0
                
                tile.physicsBody?.applyImpulse(CGVector(dx: impulseX, dy: impulseY))
                
                // Small bounce animation
                let bounceScale = 1.0 + (rippleIntensity * 0.1)
                let bounceAction = SKAction.sequence([
                    SKAction.scale(to: bounceScale, duration: 0.1),
                    SKAction.scale(to: 1.0, duration: 0.1)
                ])
                tile.run(bounceAction)
            }
        }
    }
    
    private func triggerRippleEffect(nearPosition: CGPoint, intensity: CGFloat) {
        // Find tiles near the impact position
        let rippleRadius: CGFloat = 100 + (intensity * 50)  // Larger ripples for harder impacts
        
        for tile in tiles {
            // All tiles in the tiles array are LetterTile type
            
            let distance = sqrt(pow(tile.position.x - nearPosition.x, 2) + pow(tile.position.y - nearPosition.y, 2))
            
            if distance < rippleRadius && distance > 0 {
                // Calculate ripple force based on distance and intensity
                let rippleForce = intensity * 200 * (1 - distance / rippleRadius)
                
                // Apply radial force away from impact
                let angle = atan2(tile.position.y - nearPosition.y, tile.position.x - nearPosition.x)
                let forceX = cos(angle) * rippleForce
                let forceY = sin(angle) * rippleForce
                
                // Apply impulse to tiles
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(distance / rippleRadius) * 0.1) {
                    tile.physicsBody?.applyImpulse(CGVector(dx: forceX, dy: forceY))
                }
            }
        }
    }
    
    // MARK: - Sound Effects
    private func playSquashSound(intensity: CGFloat) {
        // Play a soft squish sound with volume based on intensity
        let _ = "squish"  // Would need to add sound file to bundle
        let _ = Float(0.3 + intensity * 0.4)  // Volume range: 0.3 to 0.7
        
        // For now, use system sounds or haptic feedback
        if intensity > 0.7 {
            // Heavy squash - strong haptic
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()
        } else {
            // Light squash - light haptic
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }
        
        // Could add: run(SKAction.playSoundFileNamed(soundName, waitForCompletion: false))
    }
    
    private func playImpactSound(intensity: CGFloat) {
        // Play a wooden impact sound with volume based on intensity
        let _ = "wood_impact"  // Would need to add sound file to bundle
        let _ = Float(0.4 + intensity * 0.5)  // Volume range: 0.4 to 0.9
        
        // For now, use system sounds or haptic feedback
        if intensity > 0.8 {
            // Heavy impact - strong haptic
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred(intensity: intensity)
        } else if intensity > 0.5 {
            // Medium impact - medium haptic
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred(intensity: intensity)
        } else {
            // Light impact - light haptic
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred(intensity: intensity)
        }
        
        // Could add: run(SKAction.playSoundFileNamed(soundName, waitForCompletion: false))
    }
    
    // Debug: Show visual feedback for physics events
    private func showDebugMessage(_ message: String, at position: CGPoint) {
        // Debug messages disabled
        return
    }
}

// Base class for information tiles (ScoreTile, MessageTile, LanguageTile) with consistent green color scheme
class InformationTile: SKSpriteNode, RespawnableTile {
    // Standard font sizes for all information tiles
    static let primaryFontSize: CGFloat = 18
    static let secondaryFontSize: CGFloat = 12
    static let primaryLineHeight: CGFloat = 22
    
    private var frontFace: SKShapeNode?
    var isBeingDragged = false
    var isSquashed = false
    
    init(size: CGSize) {
        super.init(texture: nil, color: .clear, size: size)
        setupTileGeometry(size: size)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // Get the mass of this tile for collision calculations
    func getTileMass() -> CGFloat {
        return physicsBody?.mass ?? {
            let tileArea = size.width * size.height
            return tileArea / 1600.0
        }()
    }
    
    // Squashing animation for information tiles
    func squashTile(intensity: CGFloat = 1.0, direction: CGVector = CGVector(dx: 0, dy: -1)) {
        guard !isSquashed else { return }  // Prevent multiple squashing
        
        isSquashed = true
        
        // Information tiles can be squashed similar to letter tiles
        let absDirectionX = abs(direction.dx)
        let absDirectionY = abs(direction.dy)
        
        let squashFactor = 0.2 + (intensity * 0.3)
        let stretchFactor = 0.1 + (intensity * 0.2)
        
        var scaleX: CGFloat = 1.0
        var scaleY: CGFloat = 1.0
        
        if absDirectionY > absDirectionX {
            scaleY = 1.0 - squashFactor
            scaleX = 1.0 + stretchFactor
        } else {
            scaleX = 1.0 - squashFactor
            scaleY = 1.0 + stretchFactor
        }
        
        let squashAction = SKAction.group([
            SKAction.scaleX(to: scaleX, duration: 0.1),
            SKAction.scaleY(to: scaleY, duration: 0.1)
        ])
        
        let restoreAction = SKAction.group([
            SKAction.scaleX(to: 1.0, duration: 0.15),
            SKAction.scaleY(to: 1.0, duration: 0.15)
        ])
        
        let sequence = SKAction.sequence([squashAction, SKAction.wait(forDuration: 0.2), restoreAction])
        run(sequence) {
            // Reset squashed state after animation completes
            self.isSquashed = false
        }
    }
    
    private func setupTileGeometry(size: CGSize) {
        let tileWidth = size.width
        let tileHeight = size.height
        let depth: CGFloat = 6
        
        // Create the main tile body (top surface) - light green for information tiles
        let topFace = SKShapeNode()
        let topPath = CGMutablePath()
        topPath.move(to: CGPoint(x: -tileWidth / 2, y: tileHeight / 2))
        topPath.addLine(to: CGPoint(x: tileWidth / 2, y: tileHeight / 2))
        topPath.addLine(to: CGPoint(x: tileWidth / 2 + depth, y: tileHeight / 2 + depth))
        topPath.addLine(to: CGPoint(x: -tileWidth / 2 + depth, y: tileHeight / 2 + depth))
        topPath.closeSubpath()
        topFace.path = topPath
        topFace.fillColor = UIColor(red: 0.3, green: 1.0, blue: 0.3, alpha: 1.0)  // Light green
        topFace.strokeColor = .black
        topFace.lineWidth = 2
        topFace.zPosition = -0.1
        addChild(topFace)
        
        // Create the front face (main visible surface) - medium green
        let frontFaceShape = SKShapeNode()
        let frontPath = CGMutablePath()
        frontPath.move(to: CGPoint(x: -tileWidth / 2, y: -tileHeight / 2))
        frontPath.addLine(to: CGPoint(x: tileWidth / 2, y: -tileHeight / 2))
        frontPath.addLine(to: CGPoint(x: tileWidth / 2, y: tileHeight / 2))
        frontPath.addLine(to: CGPoint(x: -tileWidth / 2, y: tileHeight / 2))
        frontPath.closeSubpath()
        frontFaceShape.path = frontPath
        frontFaceShape.fillColor = UIColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0)  // Medium green
        frontFaceShape.strokeColor = .black
        frontFaceShape.lineWidth = 2
        frontFaceShape.zPosition = 0.1
        frontFace = frontFaceShape
        addChild(frontFaceShape)
        
        // Create the right face (shadow side - darker green)
        let rightFace = SKShapeNode()
        let rightPath = CGMutablePath()
        rightPath.move(to: CGPoint(x: tileWidth / 2, y: tileHeight / 2))
        rightPath.addLine(to: CGPoint(x: tileWidth / 2, y: -tileHeight / 2))
        rightPath.addLine(to: CGPoint(x: tileWidth / 2 + depth, y: -tileHeight / 2 + depth))
        rightPath.addLine(to: CGPoint(x: tileWidth / 2 + depth, y: tileHeight / 2 + depth))
        rightPath.closeSubpath()
        rightFace.path = rightPath
        rightFace.fillColor = UIColor(red: 0.1, green: 0.6, blue: 0.1, alpha: 1.0)  // Dark green shadow
        rightFace.strokeColor = UIColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0)
        rightFace.lineWidth = 2
        rightFace.zPosition = 0.0
        addChild(rightFace)
    }
}

class ScoreTile: InformationTile {
    private var scoreLabel: SKLabelNode?
    private var difficultyLabel: SKLabelNode?
    
    override init(size: CGSize) {
        super.init(size: size)
        
        // Create score label (top line)
        scoreLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        scoreLabel?.fontSize = InformationTile.primaryFontSize
        scoreLabel?.fontColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        scoreLabel?.verticalAlignmentMode = .center
        scoreLabel?.horizontalAlignmentMode = .center
        scoreLabel?.position = CGPoint(x: 0, y: 8)
        scoreLabel?.zPosition = 10.0
        addChild(scoreLabel!)
        
        // Create difficulty label (bottom line)
        difficultyLabel = SKLabelNode(fontNamed: "Arial")
        difficultyLabel?.fontSize = InformationTile.secondaryFontSize
        difficultyLabel?.fontColor = UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0)
        difficultyLabel?.verticalAlignmentMode = .center
        difficultyLabel?.horizontalAlignmentMode = .center
        difficultyLabel?.position = CGPoint(x: 0, y: -8)
        difficultyLabel?.zPosition = 10.0
        addChild(difficultyLabel!)
        
        // Set z-position to match other tiles
        zPosition = 50
        
        setupPhysics()
    }
    
    func updateScore(_ score: Int, difficulty: Int? = nil) {
        scoreLabel?.text = "\(score) pts"
        
        if let difficulty = difficulty {
            let level = getDifficultyLevel(for: difficulty)
            difficultyLabel?.text = "\(level) (\(difficulty))"
        }
    }
    
    private func getDifficultyLevel(for score: Int) -> String {
        switch score {
        case 0..<20:
            return "Very Easy"
        case 20..<40:
            return "Easy"
        case 40..<60:
            return "Medium"
        case 60..<80:
            return "Hard"
        default:
            return "Very Hard"
        }
    }
    
    private func setupPhysics() {
        // Create physics body
        physicsBody = SKPhysicsBody(rectangleOf: size)
        physicsBody?.isDynamic = true
        // Double the weight of a normal tile based on dimensions
        let tileArea = size.width * size.height
        physicsBody?.mass = (tileArea / 1600.0) * 2.0  // Double weight for score tiles
        physicsBody?.friction = 0.6
        physicsBody?.restitution = 0.3
        physicsBody?.linearDamping = 0.95
        physicsBody?.angularDamping = 0.99
        physicsBody?.affectedByGravity = true
        
        // Collision detection
        physicsBody?.categoryBitMask = PhysicsCategories.tile
        physicsBody?.contactTestBitMask = PhysicsCategories.tile | PhysicsCategories.shelf | PhysicsCategories.floor
        physicsBody?.collisionBitMask = PhysicsCategories.tile | PhysicsCategories.shelf | PhysicsCategories.floor
        
        physicsBody?.allowsRotation = true
        physicsBody?.density = 0.8
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class MessageTile: InformationTile {
    private var messageLabels: [SKLabelNode] = []
    
    var messageText: String {
        return messageLabels.first?.text ?? ""
    }
    
    // Maximum width for notification tiles (80% of shelf width)
    private static func calculateMaxTileWidth(sceneSize: CGSize) -> CGFloat {
        let shelfWidth = sceneSize.width * 0.675 - 20  // Actual shelf width
        return shelfWidth * 0.8
    }
    
    // Helper function to wrap text into lines that fit within maxWidth
    private static func wrapText(_ text: String, maxWidth: CGFloat, fontSize: CGFloat) -> [String] {
        let words = text.components(separatedBy: " ")
        var lines: [String] = []
        var currentLine = ""
        
        let tempLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        tempLabel.fontSize = fontSize
        
        for word in words {
            let testLine = currentLine.isEmpty ? word : "\(currentLine) \(word)"
            tempLabel.text = testLine
            
            if tempLabel.frame.width <= maxWidth {
                currentLine = testLine
            } else {
                if !currentLine.isEmpty {
                    lines.append(currentLine)
                    currentLine = word
                } else {
                    // Single word is too long, add it anyway
                    lines.append(word)
                }
            }
        }
        
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        
        return lines.isEmpty ? [text] : lines
    }
    
    init(message: String, sceneSize: CGSize) {
        // Calculate optimal tile size with text wrapping
        let fontSize = InformationTile.primaryFontSize
        let lineHeight = InformationTile.primaryLineHeight
        let padding: CGFloat = 20
        let minWidth: CGFloat = 80
        
        // Calculate single line width first
        let tempLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        tempLabel.fontSize = fontSize
        tempLabel.text = message
        let singleLineWidth = tempLabel.frame.width
        
        // Calculate 80% of shelf width as maximum allowed width
        let maxAllowedWidth = MessageTile.calculateMaxTileWidth(sceneSize: sceneSize)
        let actualMaxWidth = min(singleLineWidth + padding, maxAllowedWidth)
        let wrappedLines = MessageTile.wrapText(message, maxWidth: actualMaxWidth - padding, fontSize: fontSize)
        
        // Calculate final dimensions
        let tileWidth = max(min(singleLineWidth + padding, actualMaxWidth), minWidth)
        let tileHeight = CGFloat(wrappedLines.count) * lineHeight + padding
        let calculatedSize = CGSize(width: tileWidth, height: max(tileHeight, 40))  // Minimum 40 height
        
        super.init(size: calculatedSize)
        
        // Create message labels for each line
        for (index, line) in wrappedLines.enumerated() {
            let label = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
            label.fontSize = fontSize
            label.fontColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.zPosition = 10.0
            label.text = line
            
            // Position labels vertically
            let yOffset = CGFloat(wrappedLines.count - 1 - index) * lineHeight - CGFloat(wrappedLines.count - 1) * lineHeight / 2
            label.position = CGPoint(x: 0, y: yOffset)
            
            messageLabels.append(label)
            addChild(label)
        }
        
        // Set z-position to match other tiles
        zPosition = 50
        
        setupPhysics()
    }
    
    private func setupPhysics() {
        // Create physics body - same as ScoreTile
        physicsBody = SKPhysicsBody(rectangleOf: size)
        physicsBody?.isDynamic = true
        physicsBody?.mass = 0.5  // Significantly heavier than letter tiles
        physicsBody?.friction = 0.6
        physicsBody?.restitution = 0.3
        physicsBody?.linearDamping = 0.95
        physicsBody?.angularDamping = 0.99
        physicsBody?.affectedByGravity = true
        
        // Collision detection
        physicsBody?.categoryBitMask = PhysicsCategories.tile
        physicsBody?.contactTestBitMask = PhysicsCategories.tile | PhysicsCategories.shelf | PhysicsCategories.floor
        physicsBody?.collisionBitMask = PhysicsCategories.tile | PhysicsCategories.shelf | PhysicsCategories.floor
        
        physicsBody?.allowsRotation = true
        physicsBody?.density = 0.8
    }
    
    // Touch handling for dragging
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        isBeingDragged = true
        physicsBody?.velocity = CGVector.zero
        physicsBody?.angularVelocity = 0
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isBeingDragged, let touch = touches.first else { return }
        let location = touch.location(in: parent!)
        position = location
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isBeingDragged = false
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isBeingDragged = false
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class LanguageTile: InformationTile {
    private var flagImageNode: SKSpriteNode?
    var currentLanguage: String = "en"
    
    init(size: CGSize, language: String = "en") {
        super.init(size: size)
        self.currentLanguage = language
        
        // Add flag image on front face
        updateFlag(language: language)
        
        // Set up physics body
        setupPhysics()
        
        // Set z-position for proper layering
        zPosition = 50
    }
    
    private func setupPhysics() {
        physicsBody = SKPhysicsBody(rectangleOf: size)
        physicsBody?.isDynamic = true
        physicsBody?.affectedByGravity = true
        physicsBody?.mass = 0.5  // Significantly heavier than letter tiles
        physicsBody?.friction = 0.6
        physicsBody?.restitution = 0.3
        physicsBody?.linearDamping = 0.95
        physicsBody?.angularDamping = 0.99
        
        physicsBody?.categoryBitMask = PhysicsCategories.tile
        physicsBody?.contactTestBitMask = PhysicsCategories.tile | PhysicsCategories.shelf | PhysicsCategories.floor
        physicsBody?.collisionBitMask = PhysicsCategories.tile | PhysicsCategories.shelf | PhysicsCategories.floor
        
        physicsBody?.allowsRotation = true
        physicsBody?.density = 0.8
    }
    
    func updateFlag(language: String) {
        currentLanguage = language
        
        // Remove existing flag image
        flagImageNode?.removeFromParent()
        
        // Determine flag image name
        let flagImageName = language == "sv" ? "flag_sweden" : "flag_england"
        
        // Create flag image node
        let flagTexture = SKTexture(imageNamed: flagImageName)
        let flagNode = SKSpriteNode(texture: flagTexture)
        
        // Scale flag to fit nicely on the tile (about 70% of tile size)
        let flagSize = CGSize(width: size.width * 0.7, height: size.height * 0.7)
        flagNode.size = flagSize
        flagNode.position = CGPoint(x: 0, y: 0)  // Center on front face
        flagNode.zPosition = 0.2  // Above front face
        
        // Add flag to tile
        flagImageNode = flagNode
        addChild(flagNode)
    }
    
    // Touch handling for dragging
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        isBeingDragged = true
        physicsBody?.velocity = CGVector.zero
        physicsBody?.angularVelocity = 0
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isBeingDragged, let touch = touches.first else { return }
        let location = touch.location(in: parent!)
        position = location
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isBeingDragged = false
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isBeingDragged = false
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct SpriteKitView: UIViewRepresentable {
    let scene: SKScene
    
    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.presentScene(scene)
        view.ignoresSiblingOrder = true
        view.showsFPS = false
        view.showsNodeCount = false
        return view
    }
    
    func updateUIView(_ uiView: SKView, context: Context) {
        // Update if needed
    }
}

#Preview {
    PhysicsGameView(gameModel: GameModel(), showingGame: .constant(true))
}