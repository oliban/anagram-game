//
//  EmojiIconTile.swift
//  Anagram Game
//
//  Emoji icon tiles for displaying emoji content
//

import SwiftUI
import SpriteKit

class EmojiIconTile: IconTile {
    let emoji: String
    let rarity: EmojiRarity?
    private var hasTriggeredEffects = false
    
    // Age tracking with rarity-based lifecycle
    private var gamesAge: Int = 0
    
    /// Returns the maximum age for this emoji tile based on its rarity
    override var maxAge: Int {
        guard let rarity = rarity else { return 3 } // Default for unknown rarity
        
        switch rarity {
        case .common: return 3        // 3 games
        case .uncommon: return 5      // 5 games  
        case .rare: return 8          // 8 games
        case .epic: return 15         // 15 games
        case .mythic: return 30       // 30 games
        case .legendary: return -1    // Forever (never cleanup)
        }
    }
    
    // Override tileColorScheme to use rarity-based colors
    override var tileColorScheme: TileColorScheme {
        if let rarity = rarity {
            return TileColorScheme.from(rarity: rarity)
        }
        return .common // Default to common if no rarity specified
    }
    
    init(emoji: String, rarity: EmojiRarity? = nil, size: CGSize = CGSize(width: 60, height: 60)) {
        self.emoji = emoji
        self.rarity = rarity
        super.init(size: size)
        setupEmojiDisplay(emoji)
        // Don't add glow automatically - will be added only to newly dropped tiles
        
        // Enable user interaction specifically for emoji tiles (needed for dragging)
        isUserInteractionEnabled = true
    }
    
    // Reset the effects flag so effects can be triggered again
    func resetEffectsFlag() {
        hasTriggeredEffects = false
        DebugLogger.shared.ui("🔄 RESET: Effects flag reset for \(emoji)")
    }
    
    // MARK: - Age Management
    
    /// Increments the age of this emoji tile by one game
    override func incrementAge() {
        gamesAge += 1
        let rarityName = rarity?.displayName ?? "unknown"
        let maxAgeDisplay = maxAge == -1 ? "Forever" : "\(maxAge)"
        DebugLogger.shared.ui("⏰ AGE: \(emoji) (\(rarityName)) is now \(gamesAge) games old (max: \(maxAgeDisplay))")
    }
    
    /// Returns true if this emoji tile should be cleaned up
    override func shouldCleanup() -> Bool {
        let rarityName = rarity?.displayName ?? "unknown"
        
        // Legendary tiles never get cleaned up
        if maxAge == -1 {
            DebugLogger.shared.ui("👑 CLEANUP CHECK: \(emoji) (\(rarityName)) is LEGENDARY - NEVER CLEANUP (age: \(gamesAge))")
            return false
        }
        
        let shouldClean = gamesAge >= maxAge
        if shouldClean {
            DebugLogger.shared.ui("🧹 CLEANUP CHECK: \(emoji) (\(rarityName)) is \(gamesAge) games old - SHOULD BE CLEANED (max: \(maxAge))")
        } else {
            DebugLogger.shared.ui("⏳ CLEANUP CHECK: \(emoji) (\(rarityName)) is \(gamesAge) games old - keeping (needs \(maxAge - gamesAge) more games)")
        }
        return shouldClean
    }
    
    /// Returns the current age of this emoji tile
    override func getCurrentAge() -> Int {
        return gamesAge
    }
    
    // Call this method when the tile is added to the scene to trigger effects
    func triggerDropEffects(gameModel: GameModel? = nil) {
        DebugLogger.shared.ui("🔍 EFFECT DEBUG: triggerDropEffects called for \(emoji)")
        DebugLogger.shared.ui("🔍 EFFECT DEBUG: hasTriggeredEffects=\(hasTriggeredEffects), scene=\(scene != nil), rarity=\(rarity?.displayName ?? "nil")")
        
        guard !hasTriggeredEffects, let scene = scene else { 
            DebugLogger.shared.ui("❌ EFFECT DEBUG: Guard failed - effects NOT triggered (hasTriggeredEffects=\(hasTriggeredEffects), scene=\(scene != nil))")
            return 
        }
        
        // Use provided rarity or default to Common for all emojis
        let effectiveRarity = rarity ?? .common
        DebugLogger.shared.ui("✅ EFFECT DEBUG: Using \(effectiveRarity.displayName) rarity (original: \(rarity?.displayName ?? "nil"))")
        
        DebugLogger.shared.ui("✅ EFFECT DEBUG: Guard passed - proceeding with effects")
        hasTriggeredEffects = true
        
        // Create visual effects at tile center (relative positioning)
        DebugLogger.shared.ui("🎆 EFFECT DEBUG: Creating effect node for \(effectiveRarity.displayName) at tile center")
        let effectNode = EmojiEffectsManager.shared.createEffectForRarity(effectiveRarity, at: CGPoint.zero, in: scene)
        addChild(effectNode) // Add to tile so it moves with the tile
        DebugLogger.shared.ui("✅ EFFECT DEBUG: Effect node added to tile (will follow tile movement)")
        
        // Create points display above tile center
        DebugLogger.shared.ui("💰 EFFECT DEBUG: Creating points display for \(getPointsForRarity(effectiveRarity)) points")
        let pointsNode = EmojiEffectsManager.shared.createPointsDisplay(
            points: getPointsForRarity(effectiveRarity),
            rarity: effectiveRarity,
            at: CGPoint(x: 0, y: 40) // 40 points above tile center
        )
        addChild(pointsNode) // Add to tile so it moves with the tile
        DebugLogger.shared.ui("✅ EFFECT DEBUG: Points node added to tile (will follow tile movement)")
        
        // 🎯 TWO-PHASE SCORING: Animate points to score bar WITHOUT adding to model (server already has full score)
        let points = getPointsForRarity(effectiveRarity)
        if let gameModel = gameModel {
            // Don't call addEmojiPoints() - server already calculated full score, just animate the visual effect
            DebugLogger.shared.ui("🎬 VISUAL SCORING: Animating \(points) points to score bar (server already has full score)")
            
            // Animate points flying to score bar after a short delay
            let delay = SKAction.wait(forDuration: 0.5)
            let animateToScore = SKAction.run { [weak self] in
                self?.animatePointsToScoreBar(points: points, rarity: effectiveRarity, gameModel: gameModel)
            }
            let sequence = SKAction.sequence([delay, animateToScore])
            run(sequence)
        }
        
        // Trigger camera shake for legendary drops
        if effectiveRarity == .legendary {
            triggerCameraShake()
        }
        
        DebugLogger.shared.ui("🎆 EFFECTS: Triggered \(effectiveRarity.displayName) effects for \(emoji) (+\(getPointsForRarity(effectiveRarity)) points)")
    }
    
    private func animatePointsToScoreBar(points: Int, rarity: EmojiRarity, gameModel: GameModel) {
        guard let scene = scene else { return }
        
        // Calculate score bar position (top right area of screen)
        let scoreBarPosition = CGPoint(
            x: scene.size.width * 0.85, // Right side
            y: scene.size.height * 0.9   // Top area
        )
        
        EmojiEffectsManager.shared.animatePointsToScoreBar(
            points: points,
            rarity: rarity,
            from: position,
            to: scoreBarPosition,
            in: scene
        ) { [weak gameModel] in
            // 🎯 PHASE 2 SCORING: Add points to score bar when animation reaches it
            DebugLogger.shared.ui("💫 SCORE BAR UPDATE: Adding \(points) points to score bar after animation completion")
            Task { @MainActor in
                gameModel?.addPointsToScoreBar(points)
            }
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
    
    private func triggerCameraShake() {
        guard let scene = scene else { return }
        
        let shakeAmount: CGFloat = 8
        let shakeDuration: TimeInterval = 0.5
        let shakeCount = 8
        
        var shakeActions: [SKAction] = []
        for _ in 0..<shakeCount {
            let randomX = CGFloat.random(in: -shakeAmount...shakeAmount)
            let randomY = CGFloat.random(in: -shakeAmount...shakeAmount)
            let move = SKAction.moveBy(x: randomX, y: randomY, duration: shakeDuration / Double(shakeCount * 2))
            let moveBack = SKAction.moveBy(x: -randomX, y: -randomY, duration: shakeDuration / Double(shakeCount * 2))
            shakeActions.append(move)
            shakeActions.append(moveBack)
        }
        
        let shakeSequence = SKAction.sequence(shakeActions)
        scene.run(shakeSequence)
    }
    
    private func setupEmojiDisplay(_ emoji: String) {
        let emojiLabel = SKLabelNode(text: emoji)
        emojiLabel.fontSize = 28
        emojiLabel.verticalAlignmentMode = .center
        emojiLabel.horizontalAlignmentMode = .center
        
        addCenteredContent(emojiLabel)
    }
    
    /// Adds temporary glow effect to newly dropped emoji tiles that fades away after a while
    func addNewlyDroppedGlowEffect() {
        // Get rarity-specific glow configuration
        let glowConfig: (glowRadius: CGFloat, glowColor: UIColor, duration: TimeInterval)
        
        switch rarity {
        case .legendary:
            glowConfig = (glowRadius: 25.0, glowColor: UIColor.systemYellow, duration: 8.0)
        case .mythic:
            glowConfig = (glowRadius: 20.0, glowColor: UIColor.systemPurple, duration: 7.0)
        case .epic:
            glowConfig = (glowRadius: 15.0, glowColor: UIColor.systemBlue, duration: 6.0)
        case .rare:
            glowConfig = (glowRadius: 12.0, glowColor: UIColor.systemRed, duration: 5.0)
        case .uncommon:
            glowConfig = (glowRadius: 10.0, glowColor: UIColor.systemOrange, duration: 4.0)
        case .common, .none:
            glowConfig = (glowRadius: 8.0, glowColor: UIColor.white, duration: 3.0)
        }
        
        // Create glow effect
        let glowNode = SKShapeNode(circleOfRadius: glowConfig.glowRadius * 2.0)
        glowNode.fillColor = glowConfig.glowColor
        glowNode.strokeColor = glowConfig.glowColor
        glowNode.lineWidth = glowConfig.glowRadius
        glowNode.glowWidth = glowConfig.glowRadius * 2.0
        glowNode.alpha = 0.8
        glowNode.blendMode = .add
        glowNode.zPosition = 9999 // High to shine through darkness
        glowNode.name = "persistent_glow"
        
        // Add outer glow for depth
        let outerGlow = SKShapeNode(circleOfRadius: glowConfig.glowRadius * 3.0)
        outerGlow.fillColor = glowConfig.glowColor
        outerGlow.strokeColor = glowConfig.glowColor
        outerGlow.lineWidth = glowConfig.glowRadius * 0.5
        outerGlow.glowWidth = glowConfig.glowRadius * 3.0
        outerGlow.alpha = 0.6
        outerGlow.blendMode = .add
        outerGlow.zPosition = 9998
        outerGlow.name = "persistent_outer_glow"
        
        // Add glow nodes
        addChild(outerGlow)
        addChild(glowNode)
        
        // Simple fade out after duration
        let wait = SKAction.wait(forDuration: glowConfig.duration)
        let fadeOut = SKAction.fadeOut(withDuration: 1.0)
        let remove = SKAction.removeFromParent()
        let sequence = SKAction.sequence([wait, fadeOut, remove])
        
        glowNode.run(sequence)
        outerGlow.run(sequence)
        
        DebugLogger.shared.ui("✨ NEWLY DROPPED GLOW: Added \(glowConfig.duration)s glow to \(emoji) (\(rarity?.displayName ?? "common"))")
    }
    
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Disable physics temporarily to prevent conflicts and flickering
        physicsBody?.isDynamic = false
        physicsBody?.velocity = CGVector.zero
        physicsBody?.angularVelocity = 0
        
        super.touchesBegan(touches, with: event)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Re-enable physics
        physicsBody?.isDynamic = true
        
        super.touchesEnded(touches, with: event)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Re-enable physics
        physicsBody?.isDynamic = true
        
        super.touchesCancelled(touches, with: event)
    }
    
    required init?(coder aDecoder: NSCoder) {
        self.emoji = "" // Default empty emoji for decoding
        self.rarity = nil // Default to no rarity for decoding
        super.init(coder: aDecoder)
    }
}