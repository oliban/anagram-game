//
//  EmojiEffectsManager.swift
//  Anagram Game
//
//  Enhanced visual effects system for emoji drops with rarity-based effects
//

import SwiftUI
import SpriteKit

class EmojiEffectsManager {
    static let shared = EmojiEffectsManager()
    private init() {}
    
    // MARK: - Main Effect Creation
    
    func createEffectForRarity(_ rarity: EmojiRarity, at position: CGPoint, in scene: SKScene) -> SKNode {
        let effectContainer = SKNode()
        effectContainer.position = position
        effectContainer.zPosition = 1000 // Always on top
        effectContainer.name = "emoji_effect_container"
        
        switch rarity {
        case .legendary:
            createLegendaryEffect(in: effectContainer, scene: scene)
        case .mythic:
            createMythicEffect(in: effectContainer)
        case .epic:
            createEpicEffect(in: effectContainer)
        case .rare:
            createRareEffect(in: effectContainer)
        case .uncommon:
            createUncommonEffect(in: effectContainer)
        case .common:
            createCommonEffect(in: effectContainer)
        }
        
        return effectContainer
    }
    
    func createPointsDisplay(points: Int, rarity: EmojiRarity, at position: CGPoint) -> SKNode {
        let pointsContainer = SKNode()
        pointsContainer.position = position
        pointsContainer.zPosition = 1100 // Above effects
        pointsContainer.name = "points_display"
        
        // Create points label
        let pointsLabel = SKLabelNode(text: "+\(points)")
        pointsLabel.fontSize = getFontSizeForRarity(rarity)
        pointsLabel.fontName = "AvenirNext-Bold"
        pointsLabel.fontColor = getTextColorForRarity(rarity)
        pointsLabel.verticalAlignmentMode = .center
        pointsLabel.horizontalAlignmentMode = .center
        
        // Add text shadow/outline for better visibility
        let shadowLabel = SKLabelNode(text: "+\(points)")
        shadowLabel.fontSize = pointsLabel.fontSize
        shadowLabel.fontName = pointsLabel.fontName
        shadowLabel.fontColor = .black
        shadowLabel.verticalAlignmentMode = .center
        shadowLabel.horizontalAlignmentMode = .center
        shadowLabel.position = CGPoint(x: 2, y: -2)
        shadowLabel.zPosition = -1
        
        pointsContainer.addChild(shadowLabel)
        pointsContainer.addChild(pointsLabel)
        
        // Add special border effects for higher rarities
        if rarity == .legendary {
            addRainbowBorder(to: pointsContainer, size: CGSize(width: 100, height: 40))
        } else if rarity == .mythic {
            addStarBorder(to: pointsContainer, size: CGSize(width: 80, height: 35))
        } else if rarity == .epic {
            addLightningBorder(to: pointsContainer, size: CGSize(width: 70, height: 30))
        }
        
        // Animate points display
        animatePointsDisplay(pointsContainer, rarity: rarity)
        
        return pointsContainer
    }
    
    // MARK: - Rarity-Specific Effects
    
    private func createLegendaryEffect(in container: SKNode, scene: SKScene) {
        // Golden explosion with particles
        createGoldenExplosion(in: container)
        
        // Screen flash effect
        createScreenFlash(in: scene)
        
        // Crown particle rain
        createCrownParticleRain(in: container)
        
        // Pulsing golden glow
        createPulsingGlow(in: container, color: .systemYellow, intensity: 1.0)
    }
    
    private func createMythicEffect(in container: SKNode) {
        // Purple cosmic spiral
        createCosmicSpiral(in: container)
        
        // Floating star particles
        createStarParticles(in: container)
        
        // Color-shifting glow
        createColorShiftingGlow(in: container, colors: [.systemPurple, .systemBlue, .systemPurple])
    }
    
    private func createEpicEffect(in container: SKNode) {
        // Electric lightning bolts
        createLightningBolts(in: container)
        
        // Electric arc particles
        createElectricArcs(in: container)
        
        // Blue energy ring expansion
        createEnergyRing(in: container, color: .systemBlue)
    }
    
    private func createRareEffect(in container: SKNode) {
        // Fire particle explosion
        createFireExplosion(in: container)
        
        // Floating ember particles
        createEmberParticles(in: container)
        
        // Pulsing red glow
        createPulsingGlow(in: container, color: .systemRed, intensity: 0.8)
    }
    
    private func createUncommonEffect(in container: SKNode) {
        // Orange sparkle burst
        createSparkleEffect(in: container, color: .systemOrange, particleCount: 15)
        
        // Warm glow
        createPulsingGlow(in: container, color: .systemOrange, intensity: 0.6)
    }
    
    private func createCommonEffect(in container: SKNode) {
        // Simple white sparkle
        createSparkleEffect(in: container, color: .white, particleCount: 8)
        
        // Gentle brightness increase
        createPulsingGlow(in: container, color: .white, intensity: 0.4)
    }
    
    // MARK: - Specific Effect Implementations
    
    private func createGoldenExplosion(in container: SKNode) {
        for i in 0..<20 {
            let particle = SKSpriteNode(color: .systemYellow, size: CGSize(width: 4, height: 4))
            particle.position = CGPoint.zero
            
            let angle = Double(i) * (2 * Double.pi / 20)
            let distance: CGFloat = 80
            let endPosition = CGPoint(
                x: cos(angle) * distance,
                y: sin(angle) * distance
            )
            
            let moveAction = SKAction.move(to: endPosition, duration: 0.8)
            let fadeAction = SKAction.fadeOut(withDuration: 0.8)
            let scaleAction = SKAction.scale(to: 0.2, duration: 0.8)
            let groupAction = SKAction.group([moveAction, fadeAction, scaleAction])
            let removeAction = SKAction.removeFromParent()
            let sequence = SKAction.sequence([groupAction, removeAction])
            
            container.addChild(particle)
            particle.run(sequence)
        }
    }
    
    private func createScreenFlash(in scene: SKScene) {
        let flashNode = SKSpriteNode(color: .white, size: scene.size)
        flashNode.position = CGPoint(x: scene.size.width/2, y: scene.size.height/2)
        flashNode.alpha = 0.0
        flashNode.zPosition = 2000 // Above everything
        flashNode.name = "screen_flash"
        
        let fadeIn = SKAction.fadeAlpha(to: 0.3, duration: 0.1)
        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        let remove = SKAction.removeFromParent()
        let sequence = SKAction.sequence([fadeIn, fadeOut, remove])
        
        scene.addChild(flashNode)
        flashNode.run(sequence)
    }
    
    private func createCrownParticleRain(in container: SKNode) {
        for i in 0..<10 {
            let crownParticle = SKLabelNode(text: "👑")
            crownParticle.fontSize = 16
            crownParticle.position = CGPoint(x: CGFloat.random(in: -50...50), y: 100)
            
            let delay = SKAction.wait(forDuration: Double(i) * 0.2)
            let fall = SKAction.moveBy(x: 0, y: -200, duration: 2.0)
            let fade = SKAction.fadeOut(withDuration: 2.0)
            let rotate = SKAction.rotate(byAngle: CGFloat.pi * 2, duration: 2.0)
            let groupAction = SKAction.group([fall, fade, rotate])
            let remove = SKAction.removeFromParent()
            let sequence = SKAction.sequence([delay, groupAction, remove])
            
            container.addChild(crownParticle)
            crownParticle.run(sequence)
        }
    }
    
    private func createCosmicSpiral(in container: SKNode) {
        for i in 0..<30 {
            let particle = SKSpriteNode(color: .systemPurple, size: CGSize(width: 3, height: 3))
            container.addChild(particle)
            
            let angle = Double(i) * 0.4
            let radius: CGFloat = 5
            let spiralDuration: TimeInterval = 2.0
            
            let spiralAction = SKAction.customAction(withDuration: spiralDuration) { node, elapsedTime in
                let progress = elapsedTime / spiralDuration
                let currentAngle = angle + Double(progress) * 4 * Double.pi
                let currentRadius = radius + (progress * 60)
                
                node.position = CGPoint(
                    x: cos(currentAngle) * currentRadius,
                    y: sin(currentAngle) * currentRadius
                )
                node.alpha = 1.0 - progress
            }
            
            let remove = SKAction.removeFromParent()
            let sequence = SKAction.sequence([spiralAction, remove])
            
            let delay = SKAction.wait(forDuration: Double(i) * 0.05)
            particle.run(SKAction.sequence([delay, sequence]))
        }
    }
    
    private func createStarParticles(in container: SKNode) {
        for i in 0..<12 {
            let star = SKLabelNode(text: "⭐")
            star.fontSize = 12
            star.position = CGPoint(x: CGFloat.random(in: -60...60), y: CGFloat.random(in: -60...60))
            
            let float = SKAction.moveBy(x: 0, y: 30, duration: 1.5)
            let fade = SKAction.fadeOut(withDuration: 1.5)
            let pulse = SKAction.repeatForever(SKAction.sequence([
                SKAction.scale(to: 1.2, duration: 0.3),
                SKAction.scale(to: 0.8, duration: 0.3)
            ]))
            
            let groupAction = SKAction.group([float, fade])
            let remove = SKAction.removeFromParent()
            let sequence = SKAction.sequence([groupAction, remove])
            
            container.addChild(star)
            star.run(pulse)
            star.run(sequence)
        }
    }
    
    private func createLightningBolts(in container: SKNode) {
        for i in 0..<6 {
            let bolt = createLightningPath()
            bolt.strokeColor = .cyan
            bolt.lineWidth = 3
            bolt.alpha = 0.0
            
            let flash = SKAction.sequence([
                SKAction.fadeAlpha(to: 1.0, duration: 0.1),
                SKAction.fadeOut(withDuration: 0.2)
            ])
            
            let delay = SKAction.wait(forDuration: Double(i) * 0.1)
            let remove = SKAction.removeFromParent()
            let sequence = SKAction.sequence([delay, flash, remove])
            
            container.addChild(bolt)
            bolt.run(sequence)
        }
    }
    
    private func createLightningPath() -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: CGPoint.zero)
        
        var currentPoint = CGPoint.zero
        for _ in 0..<8 {
            currentPoint.x += CGFloat.random(in: -10...10)
            currentPoint.y += CGFloat.random(in: 10...15)
            path.addLine(to: currentPoint)
        }
        
        return SKShapeNode(path: path)
    }
    
    private func createElectricArcs(in container: SKNode) {
        for i in 0..<8 {
            let arc = SKSpriteNode(color: .cyan, size: CGSize(width: 2, height: 2))
            arc.position = CGPoint.zero
            
            let angle = Double(i) * (2 * Double.pi / 8)
            let endPosition = CGPoint(
                x: cos(angle) * 40,
                y: sin(angle) * 40
            )
            
            let move = SKAction.move(to: endPosition, duration: 0.3)
            let fade = SKAction.fadeOut(withDuration: 0.3)
            let group = SKAction.group([move, fade])
            let remove = SKAction.removeFromParent()
            let sequence = SKAction.sequence([group, remove])
            
            container.addChild(arc)
            arc.run(sequence)
        }
    }
    
    private func createEnergyRing(in container: SKNode, color: UIColor) {
        let ring = SKShapeNode(circleOfRadius: 5)
        ring.strokeColor = color
        ring.fillColor = .clear
        ring.lineWidth = 3
        ring.alpha = 1.0
        
        let expand = SKAction.scale(to: 8.0, duration: 1.0)
        let fade = SKAction.fadeOut(withDuration: 1.0)
        let group = SKAction.group([expand, fade])
        let remove = SKAction.removeFromParent()
        let sequence = SKAction.sequence([group, remove])
        
        container.addChild(ring)
        ring.run(sequence)
    }
    
    private func createFireExplosion(in container: SKNode) {
        for i in 0..<15 {
            let flame = SKSpriteNode(color: UIColor.systemRed, size: CGSize(width: 6, height: 6))
            flame.position = CGPoint.zero
            
            let angle = Double(i) * (2 * Double.pi / 15)
            let distance: CGFloat = CGFloat.random(in: 30...60)
            let endPosition = CGPoint(
                x: cos(angle) * distance,
                y: sin(angle) * distance
            )
            
            let move = SKAction.move(to: endPosition, duration: 0.6)
            let fade = SKAction.fadeOut(withDuration: 0.6)
            let scale = SKAction.scale(to: 0.3, duration: 0.6)
            let colorShift = SKAction.colorize(with: .systemOrange, colorBlendFactor: 1.0, duration: 0.6)
            let group = SKAction.group([move, fade, scale, colorShift])
            let remove = SKAction.removeFromParent()
            let sequence = SKAction.sequence([group, remove])
            
            container.addChild(flame)
            flame.run(sequence)
        }
    }
    
    private func createEmberParticles(in container: SKNode) {
        for i in 0..<8 {
            let ember = SKSpriteNode(color: .systemOrange, size: CGSize(width: 3, height: 3))
            ember.position = CGPoint(x: CGFloat.random(in: -30...30), y: -20)
            
            let float = SKAction.moveBy(x: CGFloat.random(in: -20...20), y: 80, duration: 2.0)
            let fade = SKAction.fadeOut(withDuration: 2.0)
            let pulse = SKAction.repeatForever(SKAction.sequence([
                SKAction.scale(to: 1.3, duration: 0.4),
                SKAction.scale(to: 0.7, duration: 0.4)
            ]))
            
            let delay = SKAction.wait(forDuration: Double(i) * 0.2)
            let group = SKAction.group([float, fade])
            let remove = SKAction.removeFromParent()
            let sequence = SKAction.sequence([delay, group, remove])
            
            container.addChild(ember)
            ember.run(pulse)
            ember.run(sequence)
        }
    }
    
    private func createSparkleEffect(in container: SKNode, color: UIColor, particleCount: Int) {
        for i in 0..<particleCount {
            let sparkle = SKSpriteNode(color: color, size: CGSize(width: 4, height: 4))
            sparkle.position = CGPoint.zero
            
            let angle = Double(i) * (2 * Double.pi / Double(particleCount))
            let distance: CGFloat = CGFloat.random(in: 20...40)
            let endPosition = CGPoint(
                x: cos(angle) * distance,
                y: sin(angle) * distance
            )
            
            let move = SKAction.move(to: endPosition, duration: 0.5)
            let fade = SKAction.fadeOut(withDuration: 0.5)
            let scale = SKAction.scale(to: 0.2, duration: 0.5)
            let group = SKAction.group([move, fade, scale])
            let remove = SKAction.removeFromParent()
            let sequence = SKAction.sequence([group, remove])
            
            container.addChild(sparkle)
            sparkle.run(sequence)
        }
    }
    
    private func createPulsingGlow(in container: SKNode, color: UIColor, intensity: CGFloat) {
        let glow = SKSpriteNode(color: color, size: CGSize(width: 80, height: 80))
        glow.alpha = 0.0
        glow.zPosition = -10 // Behind the main effect
        
        let pulse = SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: intensity * 0.6, duration: 0.5),
            SKAction.fadeAlpha(to: intensity * 0.2, duration: 0.5)
        ]))
        
        let scale = SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.2, duration: 0.5),
            SKAction.scale(to: 0.8, duration: 0.5)
        ]))
        
        let fadeOut = SKAction.sequence([
            SKAction.wait(forDuration: 3.0),
            SKAction.fadeOut(withDuration: 1.0),
            SKAction.removeFromParent()
        ])
        
        container.addChild(glow)
        glow.run(pulse)
        glow.run(scale)
        glow.run(fadeOut)
    }
    
    private func createColorShiftingGlow(in container: SKNode, colors: [UIColor]) {
        let glow = SKSpriteNode(color: colors[0], size: CGSize(width: 60, height: 60))
        glow.alpha = 0.7
        glow.zPosition = -10
        
        var colorActions: [SKAction] = []
        for color in colors {
            let colorAction = SKAction.colorize(with: color, colorBlendFactor: 1.0, duration: 0.8)
            colorActions.append(colorAction)
        }
        
        let colorShift = SKAction.repeatForever(SKAction.sequence(colorActions))
        let scale = SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.3, duration: 0.8),
            SKAction.scale(to: 0.7, duration: 0.8)
        ]))
        
        let fadeOut = SKAction.sequence([
            SKAction.wait(forDuration: 2.5),
            SKAction.fadeOut(withDuration: 1.0),
            SKAction.removeFromParent()
        ])
        
        container.addChild(glow)
        glow.run(colorShift)
        glow.run(scale)
        glow.run(fadeOut)
    }
    
    // MARK: - Points Display Animation
    
    private func animatePointsDisplay(_ container: SKNode, rarity: EmojiRarity) {
        let duration: TimeInterval = rarity == .legendary ? 2.0 : 1.5
        
        // Scale up animation
        let scaleUp = SKAction.scale(to: 1.2, duration: 0.2)
        let scaleDown = SKAction.scale(to: 1.0, duration: 0.1)
        
        // Float upward
        let float = SKAction.moveBy(x: 0, y: 50, duration: duration)
        let fade = SKAction.fadeOut(withDuration: duration)
        
        // Combination
        let scaleSequence = SKAction.sequence([scaleUp, scaleDown])
        let floatAndFade = SKAction.group([float, fade])
        let remove = SKAction.removeFromParent()
        
        let fullSequence = SKAction.sequence([scaleSequence, floatAndFade, remove])
        container.run(fullSequence)
    }
    
    // MARK: - Animated Points to Score Bar
    
    func animatePointsToScoreBar(points: Int, rarity: EmojiRarity, from startPosition: CGPoint, to endPosition: CGPoint, in scene: SKScene, completion: @escaping () -> Void) {
        // Create a flying points indicator
        let flyingPoints = SKLabelNode(text: "+\(points)")
        flyingPoints.fontSize = getFontSizeForRarity(rarity) * 0.8 // Slightly smaller for flying version
        flyingPoints.fontName = "AvenirNext-Bold"
        flyingPoints.fontColor = getTextColorForRarity(rarity)
        flyingPoints.verticalAlignmentMode = .center
        flyingPoints.horizontalAlignmentMode = .center
        flyingPoints.position = startPosition
        flyingPoints.zPosition = 1200 // Above everything else
        
        // Add glow effect for better visibility
        let glowNode = SKSpriteNode(color: getTextColorForRarity(rarity).withAlphaComponent(0.3), size: CGSize(width: 60, height: 30))
        glowNode.zPosition = -1
        flyingPoints.addChild(glowNode)
        
        scene.addChild(flyingPoints)
        
        // Calculate bezier curve path for natural movement
        let controlPoint = CGPoint(
            x: (startPosition.x + endPosition.x) / 2,
            y: max(startPosition.y, endPosition.y) + 100 // Arc upward
        )
        
        // Create path animation
        let path = createBezierPath(from: startPosition, to: endPosition, control: controlPoint)
        let pathAnimation = SKAction.follow(path, asOffset: false, orientToPath: false, duration: 1.2)
        
        // Scale animation during flight
        let scaleUp = SKAction.scale(to: 1.3, duration: 0.3)
        let scaleDown = SKAction.scale(to: 0.8, duration: 0.9)
        let scaleSequence = SKAction.sequence([scaleUp, scaleDown])
        
        // Fade animation
        let fadeDelay = SKAction.wait(forDuration: 0.8)
        let fadeOut = SKAction.fadeOut(withDuration: 0.4)
        let fadeSequence = SKAction.sequence([fadeDelay, fadeOut])
        
        // Completion actions
        let remove = SKAction.removeFromParent()
        let callCompletion = SKAction.run(completion)
        let finalSequence = SKAction.sequence([remove, callCompletion])
        
        // Run all animations
        flyingPoints.run(pathAnimation)
        flyingPoints.run(scaleSequence)
        flyingPoints.run(SKAction.sequence([fadeSequence, finalSequence]))
        
        // Add trail particles for legendary and mythic
        if rarity == .legendary || rarity == .mythic {
            addTrailParticles(to: flyingPoints, color: getTextColorForRarity(rarity))
        }
    }
    
    private func createBezierPath(from start: CGPoint, to end: CGPoint, control: CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }
    
    private func addTrailParticles(to node: SKNode, color: UIColor) {
        for i in 0..<5 {
            let particle = SKSpriteNode(color: color, size: CGSize(width: 3, height: 3))
            particle.alpha = 0.6
            particle.zPosition = -10
            node.addChild(particle)
            
            let delay = SKAction.wait(forDuration: Double(i) * 0.1)
            let trail = SKAction.moveBy(x: CGFloat.random(in: -10...10), y: CGFloat.random(in: -20...0), duration: 0.8)
            let fade = SKAction.fadeOut(withDuration: 0.8)
            let remove = SKAction.removeFromParent()
            let sequence = SKAction.sequence([delay, SKAction.group([trail, fade]), remove])
            
            particle.run(sequence)
        }
    }
    
    // MARK: - Helper Methods
    
    private func getFontSizeForRarity(_ rarity: EmojiRarity) -> CGFloat {
        switch rarity {
        case .legendary: return 32
        case .mythic: return 28
        case .epic: return 24
        case .rare: return 20
        case .uncommon: return 18
        case .common: return 16
        }
    }
    
    private func getTextColorForRarity(_ rarity: EmojiRarity) -> UIColor {
        switch rarity {
        case .legendary: return .systemYellow
        case .mythic: return .systemPurple
        case .epic: return .systemBlue
        case .rare: return .systemRed
        case .uncommon: return .systemOrange
        case .common: return .white
        }
    }
    
    private func addRainbowBorder(to container: SKNode, size: CGSize) {
        let border = SKShapeNode(rect: CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height), cornerRadius: 8)
        border.fillColor = .clear
        border.strokeColor = .systemRed
        border.lineWidth = 3
        border.zPosition = -1
        
        let rainbow = SKAction.sequence([
            SKAction.colorize(with: .systemRed, colorBlendFactor: 1.0, duration: 0.2),
            SKAction.colorize(with: .systemOrange, colorBlendFactor: 1.0, duration: 0.2),
            SKAction.colorize(with: .systemYellow, colorBlendFactor: 1.0, duration: 0.2),
            SKAction.colorize(with: .systemGreen, colorBlendFactor: 1.0, duration: 0.2),
            SKAction.colorize(with: .systemBlue, colorBlendFactor: 1.0, duration: 0.2),
            SKAction.colorize(with: .systemPurple, colorBlendFactor: 1.0, duration: 0.2)
        ])
        
        container.addChild(border)
        border.run(SKAction.repeatForever(rainbow))
    }
    
    private func addStarBorder(to container: SKNode, size: CGSize) {
        for i in 0..<8 {
            let star = SKLabelNode(text: "⭐")
            star.fontSize = 10
            star.zPosition = -1
            
            let angle = Double(i) * (2 * Double.pi / 8)
            star.position = CGPoint(
                x: cos(angle) * size.width/2,
                y: sin(angle) * size.height/2
            )
            
            let rotate = SKAction.rotate(byAngle: CGFloat.pi * 2, duration: 2.0)
            container.addChild(star)
            star.run(SKAction.repeatForever(rotate))
        }
    }
    
    private func addLightningBorder(to container: SKNode, size: CGSize) {
        let border = SKShapeNode(rect: CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height), cornerRadius: 4)
        border.fillColor = .clear
        border.strokeColor = .cyan
        border.lineWidth = 2
        border.zPosition = -1
        border.alpha = 0.0
        
        let flash = SKAction.sequence([
            SKAction.fadeAlpha(to: 1.0, duration: 0.1),
            SKAction.fadeOut(withDuration: 0.2),
            SKAction.wait(forDuration: 0.3)
        ])
        
        container.addChild(border)
        border.run(SKAction.repeatForever(flash))
    }
}