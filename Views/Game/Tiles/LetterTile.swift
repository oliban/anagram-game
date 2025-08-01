//
//  LetterTile.swift
//  Anagram Game
//
//  Letter tiles with yellow color scheme and embossed letters
//

import SwiftUI
import SpriteKit

class LetterTile: BaseTile {
    let letter: String
    private var originalFrontColor: UIColor = .systemYellow
    
    // Override abstract properties
    override var tileColorScheme: TileColorScheme { .yellow }
    
    override var physicsMass: CGFloat {
        // Letter tiles use enhanced physics settings for better gameplay
        let tileArea = size.width * size.height
        return tileArea / 1600.0  // Base mass for 40x40 tile = 1.0
    }
    
    init(letter: String, size: CGSize = CGSize(width: 40, height: 40)) {
        self.letter = letter.uppercased()
        super.init(size: size)
        
        // Create 3D embossed letter on the front face
        createEmbossedLetter()
        
        // Apply letter-specific physics tuning
        setupLetterPhysics()
    }
    
    private func createEmbossedLetter() {
        // Create main letter with good contrast
        let letterLabel = SKLabelNode(text: letter)
        letterLabel.fontSize = 24
        letterLabel.fontName = "HelveticaNeue-Bold"
        letterLabel.fontColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)  // Dark text
        letterLabel.verticalAlignmentMode = .center
        letterLabel.horizontalAlignmentMode = .center
        letterLabel.position = CGPoint(x: 0, y: 0)
        letterLabel.zPosition = 10.0 // High z-position to ensure visibility
        
        // Add letter to the main tile node for consistent visibility
        addChild(letterLabel)
    }
    
    private func setupLetterPhysics() {
        // Enhanced physics settings for letter tiles
        physicsBody?.friction = 1.0  // Maximum friction
        physicsBody?.restitution = 0.0  // No bouncing
        physicsBody?.linearDamping = 0.99  // Maximum damping - stops movement immediately
        physicsBody?.angularDamping = 0.99  // Maximum angular damping - stops rotation immediately
        physicsBody?.affectedByGravity = true
    }
    
    // Visual update for rotation-based resting
    func updateVisualForRotation() {
        let rotation = zRotation
        let depth: CGFloat = 6
        
        // Calculate offset to make the tile appear to rest on its actual contact point
        let offsetX = sin(rotation) * depth * 0.5
        let offsetY = -abs(cos(rotation)) * depth * 0.3  // Always slightly down to appear resting
        
        // Apply offset to all child nodes (the 3D faces)
        for child in children {
            if child is SKShapeNode || child is SKLabelNode {
                child.position = CGPoint(x: offsetX, y: offsetY)
            }
        }
    }
    
    // Hint system methods
    func highlightFrontFace() {
        getFrontFace()?.fillColor = .systemBlue
    }
    
    func restoreFrontFace() {
        getFrontFace()?.fillColor = originalFrontColor
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}