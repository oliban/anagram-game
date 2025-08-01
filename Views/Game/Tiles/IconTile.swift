//
//  IconTile.swift
//  Anagram Game
//
//  Base class for icon-based information tiles
//

import SwiftUI
import SpriteKit

class IconTile: InformationTile {
    private var iconImageNode: SKNode?
    
    override init(size: CGSize = CGSize(width: 60, height: 60)) {
        super.init(size: size)
        zPosition = 50
    }
    
    func updateIcon(imageName: String) {
        iconImageNode?.removeFromParent()
        
        let iconTexture = SKTexture(imageNamed: imageName)
        let iconNode = SKSpriteNode(texture: iconTexture)
        
        let iconSize = CGSize(width: size.width * 0.7, height: size.height * 0.7)
        iconNode.size = iconSize
        iconNode.position = CGPoint(x: 0, y: 0)
        iconNode.zPosition = 0.2
        
        iconImageNode = iconNode
        addChild(iconNode)
    }
    
    func updateIcon(emoji: String, fontSize: CGFloat = 40) {
        iconImageNode?.removeFromParent()
        
        let emojiLabel = SKLabelNode(text: emoji)
        emojiLabel.fontSize = fontSize
        emojiLabel.fontName = "AppleColorEmoji"
        emojiLabel.position = CGPoint(x: 0, y: -fontSize * 0.3)
        emojiLabel.zPosition = 0.2
        
        iconImageNode = emojiLabel
        addChild(emojiLabel)
    }
    
    // Helper method for subclasses to add centered content
    func addCenteredContent(_ node: SKNode) {
        node.position = CGPoint.zero
        node.zPosition = 10.0
        addChild(node)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}