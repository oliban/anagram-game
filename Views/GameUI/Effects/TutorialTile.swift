//
//  TutorialTile.swift
//  Anagram Game
//
//  Tutorial tiles for onboarding new players with purple color scheme
//

import SwiftUI
import SpriteKit

class TutorialTile: MessageTile {
    
    var tutorialText: String {
        return messageText
    }
    
    /// Tutorial tiles persist for 2 games to ensure they're seen
    override var maxAge: Int {
        return 2
    }
    
    /// Override color scheme to use purple
    override var tileColorScheme: TileColorScheme {
        return .purple
    }
    
    override init(message: String, sceneSize: CGSize) {
        super.init(message: message, sceneSize: sceneSize)
        
        // Update text color to white for purple background and make font smaller
        updateTextStyling()
    }
    
    private func updateTextStyling() {
        // Update all labels to use white text and smaller font
        for child in children {
            if let label = child as? SKLabelNode {
                label.fontColor = .white
                label.fontSize = 14  // Smaller font for tutorial tiles
            }
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}