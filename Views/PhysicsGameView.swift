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
                    // Create a basic hint status for local phrases with simple scoring
                    self.hintStatus = HintStatus(
                        hintsUsed: [],
                        nextHintLevel: 1,
                        hintsRemaining: 3,
                        currentScore: 100, // Default score for local phrases
                        nextHintScore: 90, // 90% for hint 1
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
                    let newScore = calculateLocalScore(currentLevel: nextLevel, originalScore: 100)
                    let nextHintScore = nextLevel < 3 ? calculateLocalScore(currentLevel: nextLevel + 1, originalScore: 100) : nil
                    
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
                        scene.updateScoreTile()
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
                            scene.updateScoreTile()
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
        switch currentLevel {
        case 1:
            return Int(round(Double(originalScore) * 0.9)) // 90% for hint 1
        case 2:
            return Int(round(Double(originalScore) * 0.7)) // 70% for hint 2  
        case 3:
            return Int(round(Double(originalScore) * 0.5)) // 50% for hint 3
        default:
            return originalScore
        }
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
            // Hint 3: Show text hint (generate meaningful hint for local phrases)
            scene.showHint3()
            return generateLocalTextHint(sentence: sentence)
        default:
            return "No hint available"
        }
    }
    
    private func generateLocalTextHint(sentence: String) -> String {
        let words = sentence.components(separatedBy: " ")
        let wordCount = words.count
        
        // Generate meaningful hints based on content analysis
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
                        Spacer() // Push everything to the right
                        
                        // Top-right group: Lobby button + Version number
                        HStack(spacing: 15) {
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
                            
                            // Version number
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
                    HStack {
                        // Bottom-left group: Skip + Send Phrase (stacked)
                        VStack(spacing: 10) {
                            // Skip button
                            Button(action: {
                                Task {
                                    isSkipping = true
                                    await gameModel.skipCurrentGame()
                                    // CRITICAL: Reset the scene after model updates
                                    if let scene = gameScene ?? PhysicsGameView.sharedScene {
                                        scene.resetGame()
                                    }
                                    // Brief delay to show loading completed
                                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
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
                        }
                        .padding(.leading, 20)
                        
                        Spacer() // Push hint button to the right
                        
                        // Bottom-right: Hint button (standalone)
                        HintButtonView(phraseId: gameModel.currentPhraseId ?? "local-fallback", gameModel: gameModel, gameScene: gameScene ?? PhysicsGameView.sharedScene) { _ in
                            // No longer used - clue is now displayed persistently
                        }
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

class PhysicsGameScene: SKScene, MessageTileSpawner {
    private let gameModel: GameModel
    var motionManager: CMMotionManager?
    var onCelebration: ((String) -> Void)?
    
    private var bookshelf: SKNode!
    private var floor: SKNode!
    private var tiles: [LetterTile] = []
    private var scoreTile: ScoreTile?
    private var languageTile: LanguageTile?
    private var messageTiles: [MessageTile] = []
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
        
        // Connect this scene as the message tile spawner
        gameModel.messageTileSpawner = self
        
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
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
        physicsWorld.contactDelegate = self
        
        // Create world boundaries
        let boundary = SKPhysicsBody(edgeLoopFrom: self.frame)
        boundary.friction = 0.1  // Lower friction on screen edges
        boundary.restitution = 0.4  // Higher bounce off screen edges
        physicsBody = boundary
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
        bookshelf.position = CGPoint(x: size.width / 2, y: size.height * 0.4 + 70)
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
            scoreTile.updateScore(calculateCurrentScore())
            
            let delayAction = SKAction.wait(forDuration: 1.0)  // Wait 1 second after tiles
            let addAction = SKAction.run { [weak self] in
                self?.addChild(scoreTile)
                print("Score tile spawned with score: \(self?.calculateCurrentScore() ?? 0)")
            }
            
            run(SKAction.sequence([delayAction, addAction]))
        }
        
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
    
    private func calculateCurrentScore() -> Int {
        guard gameModel.phraseDifficulty > 0 else { return 0 }
        
        var score = gameModel.phraseDifficulty
        
        if gameModel.hintsUsed >= 1 { score = Int(round(Double(gameModel.phraseDifficulty) * 0.90)) }
        if gameModel.hintsUsed >= 2 { score = Int(round(Double(gameModel.phraseDifficulty) * 0.70)) }
        if gameModel.hintsUsed >= 3 { score = Int(round(Double(gameModel.phraseDifficulty) * 0.50)) }
        
        return score
    }
    
    private func getCurrentPhraseLanguage() -> String {
        return gameModel.currentCustomPhrase?.language ?? "en"
    }
    
    func updateScoreTile() {
        scoreTile?.updateScore(calculateCurrentScore())
        print("Score tile updated to: \(calculateCurrentScore())")
    }
    
    func updateLanguageTile() {
        let newLanguage = getCurrentPhraseLanguage()
        languageTile?.updateFlag(language: newLanguage)
        print("Language tile updated to: \(newLanguage)")
    }
    
    func spawnMessageTile(message: String) {
        // Create new message tile - width calculated based on text length
        let newMessageTile = MessageTile(message: message)
        
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
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)

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
        
        // Softer, more subtle color palette
        let hintColors: [UIColor] = [
            UIColor(red: 1.0, green: 0.9, blue: 0.7, alpha: 1.0),   // Warm cream (1st word)
            UIColor(red: 0.8, green: 1.0, blue: 0.8, alpha: 1.0),   // Soft mint (2nd word)
            UIColor(red: 0.8, green: 0.9, blue: 1.0, alpha: 1.0),   // Light sky blue (3rd word)
            UIColor(red: 0.95, green: 0.8, blue: 1.0, alpha: 1.0)   // Lavender (4th word)
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
        topGlow.fillColor = hintColor.withAlphaComponent(0.4)  // More prominent
        topGlow.strokeColor = hintColor.withAlphaComponent(0.7)
        topGlow.lineWidth = 2
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
        frontGlow.fillColor = hintColor.withAlphaComponent(0.35)  // More prominent
        frontGlow.strokeColor = hintColor.withAlphaComponent(0.6)
        frontGlow.lineWidth = 2
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
        rightGlow.fillColor = hintColor.withAlphaComponent(0.25)  // More prominent
        rightGlow.strokeColor = hintColor.withAlphaComponent(0.5)
        rightGlow.lineWidth = 2
        rightGlow.zPosition = 3
        
        // Add all glow elements to container
        glowContainer.addChild(frontGlow)
        glowContainer.addChild(rightGlow)
        glowContainer.addChild(topGlow)
        
        // First: 2-second pulsating intro for attention
        let pulseBright = SKAction.fadeAlpha(to: 1.0, duration: 0.3)
        let pulseDim = SKAction.fadeAlpha(to: 0.4, duration: 0.3)
        let pulseSequence = SKAction.sequence([pulseBright, pulseDim])
        let pulsatingIntro = SKAction.repeat(pulseSequence, count: 3)  // 3 pulses = ~1.8 seconds
        
        // Then: settle into gentle breathing
        let breatheOut = SKAction.fadeAlpha(to: 0.6, duration: 2.0)
        let breatheIn = SKAction.fadeAlpha(to: 0.8, duration: 2.0)
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
    }
    
    func showHint2() {
        // Hint 2: Highlight first letter tiles
        // Only clear tile hints, preserve shelf highlights from Hint 1
        clearTileHints()
        highlightFirstLetterTiles()
    }
    
    func showHint3() {
        // Hint 3: Don't clear tile highlights - preserve blue highlighting from Hint 2
        // Only show text hint, maintain all visual hints from previous levels
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
        // --- Universal Tile Respawn Logic ---
        
        // Combine all tiles into a single array for processing
        let allTiles: [SKSpriteNode] = tiles + [scoreTile, languageTile].compactMap { $0 } + messageTiles
        
        for tile in allTiles {
            let margin: CGFloat = 100.0  // Buffer zone for tiles completely off-screen

            // Condition 1: Tile is far off-screen
            let isFarOffscreen = tile.position.x < -margin ||
                                 tile.position.x > size.width + margin ||
                                 tile.position.y < -margin ||
                                 tile.position.y > size.height + margin

            // Condition 2: Tile is stuck near an edge
            let edgeThreshold: CGFloat = 30.0
            let velocityThresholdSq: CGFloat = 15.0 * 15.0

            let isNearEdge = tile.position.x < edgeThreshold ||
                             tile.position.x > size.width - edgeThreshold ||
                             tile.position.y < edgeThreshold ||
                             tile.position.y > size.height - edgeThreshold
            
            var isStuck = false
            if isNearEdge {
                if let velocity = tile.physicsBody?.velocity {
                    let speedSq = velocity.dx * velocity.dx + velocity.dy * velocity.dy
                    if speedSq < velocityThresholdSq {
                        isStuck = true
                    }
                }
            }

            // Respawn if either condition is met
            if isFarOffscreen || isStuck {
                let randomX = CGFloat.random(in: size.width * 0.3...size.width * 0.7)
                let randomY = CGFloat.random(in: size.height * 0.4...size.height * 0.6)
                tile.position = CGPoint(x: randomX, y: randomY)
                
                tile.physicsBody?.velocity = CGVector.zero
                tile.physicsBody?.angularVelocity = 0
                tile.zRotation = CGFloat.random(in: -0.3...0.3)
                
                // Use a generic description for logging
                let tileName = (tile as? LetterTile)?.letter ?? tile.name ?? "Unnamed Tile"
                
                if isStuck {
                    print("Respawned STUCK tile '\(tileName)' at (\(Int(randomX)), \(Int(randomY)))")
                } else {
                    print("Respawned OFF-SCREEN tile '\(tileName)' at (\(Int(randomX)), \(Int(randomY)))")
                }
            }
            
            // Adjust visual appearance for LetterTiles
            if let letterTile = tile as? LetterTile {
                letterTile.updateVisualForRotation()
            }
        }
    }
    
    func resetGame() {
        print("🔄 Scene resetGame() called")
        
        // Clear any existing celebration or game state
        celebrationText = ""
        
        // Clear hint effects when starting new game
        clearAllHints()
        
        // CRITICAL: Clear all existing tiles immediately
        print("🗑️ Clearing \(tiles.count) existing tiles")
        for tile in tiles {
            tile.removeFromParent()
        }
        tiles.removeAll()
        
        // Clear existing message tiles
        print("🗑️ Clearing \(messageTiles.count) existing message tiles")
        for messageTile in messageTiles {
            messageTile.removeFromParent()
        }
        messageTiles.removeAll()
        
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
                triggerCelebration() // Celebrate with score
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
        Task {
            await gameModel.startNewGame(isUserInitiated: true)
            
            // Reset scene using the improved resetGame method
            resetGame()
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

class LetterTile: SKSpriteNode {
    let letter: String
    var isBeingDragged = false
    private var frontFace: SKShapeNode?
    private var originalFrontColor: UIColor = .systemYellow
    
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
        physicsBody?.mass = 0.2  // Heavy tiles
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
        letterLabel.fontName = "Arial-Bold"
        letterLabel.fontColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)  // Dark text
        letterLabel.verticalAlignmentMode = .center
        letterLabel.horizontalAlignmentMode = .center
        letterLabel.position = CGPoint(x: 0, y: 0)
        letterLabel.zPosition = 10.0 // Much higher z-position to ensure visibility
        
        // Add letter to the main tile node instead of just the surface
        // This ensures it's always visible regardless of shape rendering issues
        self.addChild(letterLabel)
    }
    
    // Hint system methods
    func highlightFrontFace() {
        frontFace?.fillColor = .systemBlue
    }
    
    func restoreFrontFace() {
        frontFace?.fillColor = originalFrontColor
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension PhysicsGameScene: SKPhysicsContactDelegate {
    func didBegin(_ contact: SKPhysicsContact) {
        // Handle tile collisions and word formation
    }
}

class ScoreTile: SKSpriteNode {
    private var frontFace: SKShapeNode?
    private var scoreLabel: SKLabelNode?
    var isBeingDragged = false
    
    init(size: CGSize) {
        super.init(texture: nil, color: .clear, size: size)
        
        let tileWidth = size.width
        let tileHeight = size.height
        let depth: CGFloat = 6
        
        // Create the main tile body (top surface) - lighter gold for top lighting (like LetterTile)
        let topFace = SKShapeNode()
        let topPath = CGMutablePath()
        topPath.move(to: CGPoint(x: -tileWidth / 2, y: tileHeight / 2))
        topPath.addLine(to: CGPoint(x: tileWidth / 2, y: tileHeight / 2))
        topPath.addLine(to: CGPoint(x: tileWidth / 2 + depth, y: tileHeight / 2 + depth))
        topPath.addLine(to: CGPoint(x: -tileWidth / 2 + depth, y: tileHeight / 2 + depth))
        topPath.closeSubpath()
        topFace.path = topPath
        topFace.fillColor = UIColor(red: 1.0, green: 0.9, blue: 0.2, alpha: 1.0)  // Very bright gold
        topFace.strokeColor = .black
        topFace.lineWidth = 2
        topFace.zPosition = -0.1  // Put tile roofs in background
        addChild(topFace)
        
        // Create the front face (main visible surface) - like LetterTile
        let frontFaceShape = SKShapeNode()
        let frontPath = CGMutablePath()
        frontPath.move(to: CGPoint(x: -tileWidth / 2, y: -tileHeight / 2))
        frontPath.addLine(to: CGPoint(x: tileWidth / 2, y: -tileHeight / 2))
        frontPath.addLine(to: CGPoint(x: tileWidth / 2, y: tileHeight / 2))
        frontPath.addLine(to: CGPoint(x: -tileWidth / 2, y: tileHeight / 2))
        frontPath.closeSubpath()
        frontFaceShape.path = frontPath
        frontFaceShape.fillColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)  // Gold color
        frontFaceShape.strokeColor = .black
        frontFaceShape.lineWidth = 2
        frontFaceShape.zPosition = 0.1
        frontFace = frontFaceShape  // Store reference
        addChild(frontFaceShape)
        
        // Create the right face (shadow side - darker) - like LetterTile
        let rightFace = SKShapeNode()
        let rightPath = CGMutablePath()
        rightPath.move(to: CGPoint(x: tileWidth / 2, y: tileHeight / 2))
        rightPath.addLine(to: CGPoint(x: tileWidth / 2, y: -tileHeight / 2))
        rightPath.addLine(to: CGPoint(x: tileWidth / 2 + depth, y: -tileHeight / 2 + depth))
        rightPath.addLine(to: CGPoint(x: tileWidth / 2 + depth, y: tileHeight / 2 + depth))
        rightPath.closeSubpath()
        rightFace.path = rightPath
        rightFace.fillColor = UIColor(red: 0.6, green: 0.5, blue: 0.0, alpha: 1.0)  // Dark gold shadow side
        rightFace.strokeColor = UIColor(red: 0.4, green: 0.3, blue: 0.0, alpha: 1.0)
        rightFace.lineWidth = 2
        rightFace.zPosition = 0.0
        addChild(rightFace)
        
        // Create score label
        scoreLabel = SKLabelNode(fontNamed: "Arial-Bold")
        scoreLabel?.fontSize = 24
        scoreLabel?.fontColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)  // Dark text like letter tiles
        scoreLabel?.verticalAlignmentMode = .center
        scoreLabel?.horizontalAlignmentMode = .center
        scoreLabel?.zPosition = 10.0  // Same as letter tiles
        addChild(scoreLabel!)
        
        // Set z-position to match letter tiles
        zPosition = 50
        
        setupPhysics()
    }
    
    func updateScore(_ score: Int) {
        scoreLabel?.text = "\(score) pts"
    }
    
    private func setupPhysics() {
        // Create physics body
        physicsBody = SKPhysicsBody(rectangleOf: size)
        physicsBody?.isDynamic = true
        physicsBody?.mass = 0.1  // Lighter than letter tiles
        physicsBody?.friction = 0.6
        physicsBody?.restitution = 0.3  // Bouncy
        physicsBody?.linearDamping = 0.95
        physicsBody?.angularDamping = 0.99
        physicsBody?.affectedByGravity = true
        
        // Collision detection
        physicsBody?.categoryBitMask = PhysicsCategories.tile
        physicsBody?.contactTestBitMask = PhysicsCategories.tile | PhysicsCategories.shelf | PhysicsCategories.floor
        physicsBody?.collisionBitMask = PhysicsCategories.tile | PhysicsCategories.shelf | PhysicsCategories.floor
        
        physicsBody?.allowsRotation = true
        physicsBody?.density = 0.8  // Lighter than letter tiles
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class MessageTile: SKSpriteNode {
    private var frontFace: SKShapeNode?
    private var messageLabel: SKLabelNode?
    var isBeingDragged = false
    
    var messageText: String {
        return messageLabel?.text ?? ""
    }
    
    init(message: String) {
        // Calculate tile width based on text length - similar to other tiles
        let tempLabel = SKLabelNode(fontNamed: "Arial-Bold")
        tempLabel.fontSize = 24
        tempLabel.text = message
        let textWidth = tempLabel.frame.width
        
        // Add padding and ensure minimum width
        let tileWidth = max(textWidth + 20, 80)  // Minimum 80 pixels width
        let tileHeight: CGFloat = 40  // Standard tile height
        let calculatedSize = CGSize(width: tileWidth, height: tileHeight)
        
        super.init(texture: nil, color: .clear, size: calculatedSize)
        
        let depth: CGFloat = 6
        
        // Create the main tile body (top surface) - light blue for message tiles
        let topFace = SKShapeNode()
        let topPath = CGMutablePath()
        topPath.move(to: CGPoint(x: -tileWidth / 2, y: tileHeight / 2))
        topPath.addLine(to: CGPoint(x: tileWidth / 2, y: tileHeight / 2))
        topPath.addLine(to: CGPoint(x: tileWidth / 2 + depth, y: tileHeight / 2 + depth))
        topPath.addLine(to: CGPoint(x: -tileWidth / 2 + depth, y: tileHeight / 2 + depth))
        topPath.closeSubpath()
        topFace.path = topPath
        topFace.fillColor = UIColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1.0)  // Light blue
        topFace.strokeColor = .black
        topFace.lineWidth = 2
        topFace.zPosition = -0.1
        addChild(topFace)
        
        // Create the front face (main visible surface) - medium blue
        let frontFaceShape = SKShapeNode()
        let frontPath = CGMutablePath()
        frontPath.move(to: CGPoint(x: -tileWidth / 2, y: -tileHeight / 2))
        frontPath.addLine(to: CGPoint(x: tileWidth / 2, y: -tileHeight / 2))
        frontPath.addLine(to: CGPoint(x: tileWidth / 2, y: tileHeight / 2))
        frontPath.addLine(to: CGPoint(x: -tileWidth / 2, y: tileHeight / 2))
        frontPath.closeSubpath()
        frontFaceShape.path = frontPath
        frontFaceShape.fillColor = UIColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0)  // Medium blue
        frontFaceShape.strokeColor = .black
        frontFaceShape.lineWidth = 2
        frontFaceShape.zPosition = 0.1
        frontFace = frontFaceShape
        addChild(frontFaceShape)
        
        // Create the right face (shadow side - darker blue)
        let rightFace = SKShapeNode()
        let rightPath = CGMutablePath()
        rightPath.move(to: CGPoint(x: tileWidth / 2, y: tileHeight / 2))
        rightPath.addLine(to: CGPoint(x: tileWidth / 2, y: -tileHeight / 2))
        rightPath.addLine(to: CGPoint(x: tileWidth / 2 + depth, y: -tileHeight / 2 + depth))
        rightPath.addLine(to: CGPoint(x: tileWidth / 2 + depth, y: tileHeight / 2 + depth))
        rightPath.closeSubpath()
        rightFace.path = rightPath
        rightFace.fillColor = UIColor(red: 0.1, green: 0.4, blue: 0.7, alpha: 1.0)  // Dark blue shadow
        rightFace.strokeColor = UIColor(red: 0.0, green: 0.3, blue: 0.6, alpha: 1.0)
        rightFace.lineWidth = 2
        rightFace.zPosition = 0.0
        addChild(rightFace)
        
        // Create message label - same style as other tiles
        messageLabel = SKLabelNode(fontNamed: "Arial-Bold")
        messageLabel?.fontSize = 24  // Same as other tiles
        messageLabel?.fontColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)  // Dark text like other tiles
        messageLabel?.verticalAlignmentMode = .center
        messageLabel?.horizontalAlignmentMode = .center
        messageLabel?.zPosition = 10.0
        messageLabel?.text = message
        addChild(messageLabel!)
        
        // Set z-position to match other tiles
        zPosition = 50
        
        setupPhysics()
    }
    
    private func setupPhysics() {
        // Create physics body - same as ScoreTile
        physicsBody = SKPhysicsBody(rectangleOf: size)
        physicsBody?.isDynamic = true
        physicsBody?.mass = 0.1  // Same as ScoreTile
        physicsBody?.friction = 0.6
        physicsBody?.restitution = 0.3  // Bouncy
        physicsBody?.linearDamping = 0.95
        physicsBody?.angularDamping = 0.99
        physicsBody?.affectedByGravity = true
        
        // Collision detection
        physicsBody?.categoryBitMask = PhysicsCategories.tile
        physicsBody?.contactTestBitMask = PhysicsCategories.tile | PhysicsCategories.shelf | PhysicsCategories.floor
        physicsBody?.collisionBitMask = PhysicsCategories.tile | PhysicsCategories.shelf | PhysicsCategories.floor
        
        physicsBody?.allowsRotation = true
        physicsBody?.density = 0.8  // Same as ScoreTile
    }
    
    // Touch handling for dragging (same pattern as ScoreTile and LanguageTile)
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

class LanguageTile: SKSpriteNode {
    private var frontFace: SKShapeNode?
    private var flagImageNode: SKSpriteNode?
    var isBeingDragged = false
    var currentLanguage: String = "en"
    
    init(size: CGSize, language: String = "en") {
        super.init(texture: nil, color: .clear, size: size)
        self.currentLanguage = language
        
        let tileWidth = size.width
        let tileHeight = size.height
        let depth: CGFloat = 6
        
        // Create the main tile body (top surface) - blue theme for language
        let topFace = SKShapeNode()
        let topPath = CGMutablePath()
        topPath.move(to: CGPoint(x: -tileWidth / 2, y: tileHeight / 2))
        topPath.addLine(to: CGPoint(x: tileWidth / 2, y: tileHeight / 2))
        topPath.addLine(to: CGPoint(x: tileWidth / 2 + depth, y: tileHeight / 2 + depth))
        topPath.addLine(to: CGPoint(x: -tileWidth / 2 + depth, y: tileHeight / 2 + depth))
        topPath.closeSubpath()
        topFace.path = topPath
        topFace.fillColor = UIColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1.0)  // Light blue
        topFace.strokeColor = .black
        topFace.lineWidth = 2
        topFace.zPosition = -0.1  // Put tile roofs in background
        addChild(topFace)
        
        // Create the front face (main visible surface) - blue theme
        let frontFaceShape = SKShapeNode()
        let frontPath = CGMutablePath()
        frontPath.move(to: CGPoint(x: -tileWidth / 2, y: -tileHeight / 2))
        frontPath.addLine(to: CGPoint(x: tileWidth / 2, y: -tileHeight / 2))
        frontPath.addLine(to: CGPoint(x: tileWidth / 2, y: tileHeight / 2))
        frontPath.addLine(to: CGPoint(x: -tileWidth / 2, y: tileHeight / 2))
        frontPath.closeSubpath()
        frontFaceShape.path = frontPath
        frontFaceShape.fillColor = UIColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0)  // Medium blue
        frontFaceShape.strokeColor = .black
        frontFaceShape.lineWidth = 2
        frontFaceShape.zPosition = 0.1
        frontFace = frontFaceShape  // Store reference
        addChild(frontFaceShape)
        
        // Create the right face (shadow side - darker blue)
        let rightFace = SKShapeNode()
        let rightPath = CGMutablePath()
        rightPath.move(to: CGPoint(x: tileWidth / 2, y: tileHeight / 2))
        rightPath.addLine(to: CGPoint(x: tileWidth / 2, y: -tileHeight / 2))
        rightPath.addLine(to: CGPoint(x: tileWidth / 2 + depth, y: -tileHeight / 2 + depth))
        rightPath.addLine(to: CGPoint(x: tileWidth / 2 + depth, y: tileHeight / 2 + depth))
        rightPath.closeSubpath()
        rightFace.path = rightPath
        rightFace.fillColor = UIColor(red: 0.1, green: 0.4, blue: 0.7, alpha: 1.0)  // Dark blue shadow
        rightFace.strokeColor = .black
        rightFace.lineWidth = 2
        rightFace.zPosition = 0.0
        addChild(rightFace)
        
        // Add flag image on front face
        updateFlag(language: language)
        
        // Set up physics body (same as letter tiles for consistency)
        physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: tileWidth, height: tileHeight))
        physicsBody?.isDynamic = true
        physicsBody?.affectedByGravity = true
        physicsBody?.mass = 0.1  // Same as ScoreTile
        physicsBody?.friction = 0.6
        physicsBody?.restitution = 0.3
        physicsBody?.linearDamping = 0.95
        physicsBody?.angularDamping = 0.99
        
        physicsBody?.categoryBitMask = PhysicsCategories.tile
        physicsBody?.contactTestBitMask = PhysicsCategories.tile | PhysicsCategories.shelf | PhysicsCategories.floor
        physicsBody?.collisionBitMask = PhysicsCategories.tile | PhysicsCategories.shelf | PhysicsCategories.floor
        
        physicsBody?.allowsRotation = true
        physicsBody?.density = 0.8  // Same as ScoreTile
        
        // Set z-position for proper layering
        zPosition = 50  // Same as letter tiles
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
    
    // Touch handling for dragging (same pattern as ScoreTile)
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