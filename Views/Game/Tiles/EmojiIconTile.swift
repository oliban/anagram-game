//
//  EmojiIconTile.swift
//  Anagram Game
//
//  Emoji icon tiles for displaying emoji content
//

import SwiftUI
import SpriteKit

class EmojiIconTile: IconTile {
    init(emoji: String, size: CGSize = CGSize(width: 60, height: 60)) {
        super.init(size: size)
        setupEmojiDisplay(emoji)
    }
    
    private func setupEmojiDisplay(_ emoji: String) {
        let emojiLabel = SKLabelNode(text: emoji)
        emojiLabel.fontSize = 28
        emojiLabel.verticalAlignmentMode = .center
        emojiLabel.horizontalAlignmentMode = .center
        
        addCenteredContent(emojiLabel)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}