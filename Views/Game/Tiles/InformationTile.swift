//
//  InformationTile.swift
//  Anagram Game
//
//  Base class for information tiles with green color scheme
//

import SwiftUI
import SpriteKit

enum InformationTileType {
    case score
    case theme
    case message
}

class InformationTile: BaseTile {
    // Standard font sizes for all information tiles
    static let primaryFontSize: CGFloat = 18
    static let secondaryFontSize: CGFloat = 12
    static let primaryLineHeight: CGFloat = 22
    
    private let tileType: InformationTileType
    private var contentLabels: [SKLabelNode] = []
    
    // Override abstract properties - color based on type
    override var tileColorScheme: TileColorScheme {
        switch tileType {
        case .score, .message:
            return .green
        case .theme:
            return .blue
        }
    }
    
    override var physicsMass: CGFloat {
        // Information tiles are lighter than letter tiles
        let tileArea = size.width * size.height
        return (tileArea / 1600.0) * 0.5  // Half the mass of letter tiles
    }
    
    // Unified initializer for all information tile types
    init(type: InformationTileType, content: String, size: CGSize = CGSize(width: 80, height: 60)) {
        self.tileType = type
        super.init(size: size)
        setupInformationPhysics()
        setupContent(content)
    }
    
    // Legacy initializer for backwards compatibility
    override init(size: CGSize = CGSize(width: 80, height: 60)) {
        self.tileType = .message
        super.init(size: size)
        setupInformationPhysics()
    }
    
    // Backwards compatibility for ThemeInformationTile constructor
    convenience init(theme: String, size: CGSize = CGSize(width: 100, height: 60)) {
        self.init(type: .theme, content: theme.capitalized, size: size)
    }
    
    private func setupInformationPhysics() {
        // Information tiles have different physics properties
        guard let body = physicsBody else {
            print("❌ InformationTile: No physics body found!")
            return
        }
        print("✅ InformationTile: Physics body exists, setting up properties")
        body.friction = 0.6
        body.restitution = 0.3
        body.linearDamping = 0.95
        body.angularDamping = 0.99
    }
    
    private func setupContent(_ content: String) {
        let label = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        label.text = content
        label.fontSize = InformationTile.primaryFontSize
        
        // Color based on tile type
        switch tileType {
        case .score, .message:
            label.fontColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0) // Dark on green
        case .theme:
            label.fontColor = .white // White on blue
        }
        
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 10.0
        addChild(label)
        contentLabels.append(label)
    }
    
    // Method to update content dynamically (for score updates, etc.)
    func updateContent(_ content: String) {
        contentLabels.first?.text = content
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}