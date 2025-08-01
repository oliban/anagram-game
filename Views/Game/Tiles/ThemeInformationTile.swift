//
//  ThemeInformationTile.swift
//  Anagram Game
//
//  Theme information tiles with blue color scheme
//

import SwiftUI
import SpriteKit

class ThemeInformationTile: InformationTile {
    // Override to use blue color scheme instead of green
    override var tileColorScheme: TileColorScheme { .blue }
    
    init(theme: String, size: CGSize = CGSize(width: 100, height: 60)) {
        super.init(type: .theme, content: theme.capitalized, size: size)
        // Enable user interaction for this tile
        isUserInteractionEnabled = true
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Disable physics temporarily to prevent conflicts
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
        fatalError("init(coder:) has not been implemented")
    }
}