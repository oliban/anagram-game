//
//  PhysicsGameView.swift
//  Anagram Game
//
//  Created by Fredrik Säfsten on 2025-07-05.
//

import SwiftUI
import SpriteKit
import CoreMotion

// Physics collision categories for better collision detection
struct PhysicsCategories {
    static let tile: UInt32 = 0x1 << 0
    static let shelf: UInt32 = 0x1 << 1
    static let floor: UInt32 = 0x1 << 2
    static let wall: UInt32 = 0x1 << 3
}

struct PhysicsGameView: View {
    @State private var gameModel = GameModel()
    @State private var motionManager = CMMotionManager()
    @State private var gameScene: PhysicsGameScene?
    @State private var celebrationMessage = ""
    @State private var phraseNotificationMessage = ""
    @State private var isSkipping = false
    @StateObject private var networkManager = NetworkManager.shared
    
    // Static reference to avoid SwiftUI state issues
    private static var sharedScene: PhysicsGameScene?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // SpriteKit scene for physics
                SpriteKitView(scene: getOrCreateScene(size: geometry.size))
                    .ignoresSafeArea()
                
                // SwiftUI overlay for UI elements
                VStack {
                    // Custom phrase attribution (top center)
                    if !gameModel.customPhraseInfo.isEmpty {
                        Text(gameModel.customPhraseInfo)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.8))
                            .cornerRadius(12)
                            .shadow(radius: 4)
                            .padding(.top, 50)
                    }
                    
                    HStack {
                        Spacer()
                        
                        VStack {
                            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                                .onAppear {
                                    print("📱 INFO DICT DEBUG: \(Bundle.main.infoDictionary ?? [:])")
                                    print("📱 VERSION DEBUG: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "NOT FOUND")")
                                }
                                .font(.caption)
                                .foregroundColor(.red)
                                .fontWeight(.bold)
                                .onTapGesture {
                                    if let scene = gameScene ?? PhysicsGameView.sharedScene {
                                        scene.triggerQuake()
                                    }
                                }
                            
                            if let lastPhrase = networkManager.lastReceivedPhrase {
                                Text("LAST RECEIVED:")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                    .fontWeight(.bold)
                                    .padding(.top, 4)
                                
                                Text(lastPhrase.content)
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(4)
                                    .padding(.horizontal, 4)
                                
                                Text("from \(lastPhrase.senderName)")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                    .italic()
                            } else {
                                Text("NEXT:")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                    .fontWeight(.bold)
                                    .padding(.top, 4)
                                
                                Text("(server phrase)")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(4)
                                    .padding(.horizontal, 4)
                            }
                            
                        }
                        .padding()
                    }
                    
                    
                    Spacer()
                    
                    // Skip button - Bottom left
                    HStack {
                        VStack {
                            Spacer()
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
                            .padding(.bottom, 50)
                            .padding(.leading, 20)
                        }
                        Spacer()
                    }
                    
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
                    
                    // Phrase notification toast
                    if !phraseNotificationMessage.isEmpty {
                        VStack {
                            Text(phraseNotificationMessage)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.green.opacity(0.9))
                                .cornerRadius(25)
                                .shadow(radius: 6)
                                .transition(.scale.combined(with: .opacity))
                            
                            Spacer()
                        }
                        .padding(.top, 120)
                        .zIndex(2000)
                    }
                    
                }
            }
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
        .onChange(of: networkManager.lastReceivedPhrase) { oldValue, newValue in
            if let newPhrase = newValue, newPhrase != oldValue {
                withAnimation(.spring()) {
                    phraseNotificationMessage = "New phrase from \(newPhrase.senderName)!"
                }
                
                // Clear notification after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation(.easeOut) {
                        phraseNotificationMessage = ""
                    }
                }
            }
        }
    }
    
    private func getOrCreateScene(size: CGSize) -> PhysicsGameScene {
        if let existingScene = PhysicsGameView.sharedScene {
            print("♻️ Reusing shared scene")
            return existingScene
        }
        
        print("🚀 Creating SINGLE scene with size: \(size)")
        let newScene = PhysicsGameScene(gameModel: gameModel, size: size)
        
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

class PhysicsGameScene: SKScene {
    private let gameModel: GameModel
    var motionManager: CMMotionManager?
    var onCelebration: ((String) -> Void)?
    
    private var bookshelf: SKNode!
    private var floor: SKNode!
    private var tiles: [LetterTile] = []
    private var shelves: [SKNode] = []  // Track individual shelves for hint system
    var celebrationText: String = ""

    private enum QuakeState { case none, normal, superQuake }
    private var quakeState: QuakeState = .none
    private var quakeEndAction: SKAction?
    
    init(gameModel: GameModel, size: CGSize) {
        self.gameModel = gameModel
        super.init(size: size)
        
        setupPhysicsWorld()
        setupEnvironment()
        
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
        floor.position = CGPoint(x: size.width / 2, y: size.height * 0.15)
        addChild(floor)
        
        // Floor with isometric perspective
        let floorShape = SKShapeNode()
        let floorPath = CGMutablePath()
        let floorWidth: CGFloat = size.width * 0.9
        let floorDepth: CGFloat = 200
        
        // Create diamond-shaped floor for isometric view
        floorPath.move(to: CGPoint(x: 0, y: floorDepth / 2))
        floorPath.addLine(to: CGPoint(x: floorWidth / 2, y: 0))
        floorPath.addLine(to: CGPoint(x: 0, y: -floorDepth / 2))
        floorPath.addLine(to: CGPoint(x: -floorWidth / 2, y: 0))
        floorPath.closeSubpath()
        
        floorShape.path = floorPath
        floorShape.fillColor = .darkGray
        floorShape.strokeColor = .black
        floorShape.lineWidth = 2
        floor.addChild(floorShape)
        
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
        bookshelf.position = CGPoint(x: size.width / 2, y: size.height * 0.4 + 50)
        addChild(bookshelf)
        
        let shelfWidth: CGFloat = size.width * 0.75  // Reduced from 0.85 to 0.75 (10% less wide)
        let shelfHeight: CGFloat = 374  // Increased by 56% total (240 * 1.3 * 1.2)
        let shelfDepth: CGFloat = 50
        
        // Create bookshelf frame structure
        createBookshelfFrame(width: shelfWidth, height: shelfHeight, depth: shelfDepth)
        
        // Clear shelves array for clean setup
        shelves.removeAll()
        
        // Create multiple shelves with proper wood grain appearance
        for i in 0..<4 {
            let shelfY = CGFloat(-140 + (i * 94))  // Increased spacing by 56% total (-90*1.56, 60*1.56)
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
        let shelfWidth: CGFloat = size.width * 0.75 - 20  // Match actual shelf width
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
        for shelf in shelves {
            // Remove the glow container which contains all glow elements
            shelf.childNode(withName: "hint_glow")?.removeFromParent()
        }
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
        let originalPosition = CGPoint(x: size.width / 2, y: size.height * 0.4 + 50)
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
        for tile in tiles {
            let margin: CGFloat = 100  // Buffer zone outside screen
            if tile.position.x < -margin || 
               tile.position.x > size.width + margin || 
               tile.position.y < -margin || 
               tile.position.y > size.height + margin {
                // Respawn tile in center area with some randomness
                let randomX = CGFloat.random(in: size.width * 0.3...size.width * 0.7)
                let randomY = CGFloat.random(in: size.height * 0.4...size.height * 0.6)
                tile.position = CGPoint(x: randomX, y: randomY)
                
                // Reset physics properties
                tile.physicsBody?.velocity = CGVector.zero
                tile.physicsBody?.angularVelocity = 0
                tile.zRotation = CGFloat.random(in: -0.3...0.3)
                
                print("Respawned tile '\(tile.letter)' at center: \(tile.position)")
            }
            
            // Adjust visual appearance based on rotation to look like proper resting
            tile.updateVisualForRotation()
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
        
        // Stop any ongoing physics effects
        removeAction(forKey: "quakeForces")
        quakeState = .none
        
        // Reset bookshelf position and rotation in case quake was active
        bookshelf.removeAllActions()
        let originalPosition = CGPoint(x: size.width / 2, y: size.height * 0.4 + 50)
        bookshelf.position = originalPosition
        bookshelf.zRotation = 0
        
        // Create new tiles with current game model data (don't call startNewGame again)
        createTiles()
        
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
                triggerCelebration()
                gameModel.completeGame() // Mark game as completed
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
        print("🎉 \(randomMessage)")
        
        // Show celebration message on screen
        celebrationText = "🎉 \(randomMessage)"
        print("🎊 CELEBRATION TEXT SET: '\(celebrationText)'")
        print("🎊 CELEBRATION TEXT EMPTY? \(celebrationText.isEmpty)")
        
        // Trigger SwiftUI celebration display
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onCelebration?(randomMessage)
            print("🎊 TRIGGERED SWIFTUI CELEBRATION: '\(randomMessage)'")
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
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        // Move dragged tile
        if let tile = tiles.first(where: { $0.isBeingDragged }) {
            tile.position = location
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
    }
}

class LetterTile: SKSpriteNode {
    let letter: String
    var isBeingDragged = false
    
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
        letterLabel.zPosition = 0.3 // Above all tile faces but within reasonable range
        
        surface.addChild(letterLabel)
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