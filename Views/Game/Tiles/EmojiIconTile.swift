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
    private let rarity: EmojiRarity?
    
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
        
        // Enable user interaction specifically for emoji tiles (needed for dragging)
        isUserInteractionEnabled = true
    }
    
    private func setupEmojiDisplay(_ emoji: String) {
        let emojiLabel = SKLabelNode(text: emoji)
        emojiLabel.fontSize = 28
        emojiLabel.verticalAlignmentMode = .center
        emojiLabel.horizontalAlignmentMode = .center
        
        addCenteredContent(emojiLabel)
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