//
//  TutorialTile.swift
//  Anagram Game
//
//  Tutorial tiles for onboarding new players with purple color scheme
//

import SwiftUI
import SpriteKit

class TutorialTile: InformationTile {
    private var tutorialLabels: [SKLabelNode] = []
    
    var tutorialText: String {
        return tutorialLabels.first?.text ?? ""
    }
    
    /// Tutorial tiles persist for 2 games to ensure they're seen
    override var maxAge: Int {
        return 2
    }
    
    /// Override color scheme to use purple
    override var tileColorScheme: TileColorScheme {
        return .purple
    }
    
    init(message: String, sceneSize: CGSize) {
        // Calculate optimal tile size with text wrapping
        let fontSize = InformationTile.primaryFontSize
        let lineHeight = InformationTile.primaryLineHeight
        let padding: CGFloat = 20
        let minWidth: CGFloat = 80
        
        // Calculate single line width first
        let tempLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        tempLabel.fontSize = fontSize
        tempLabel.text = message
        let singleLineWidth = tempLabel.frame.width
        
        // Calculate 80% of shelf width as maximum allowed width, but cap at 400px
        let sceneBasedWidth = TutorialTile.calculateMaxTileWidth(sceneSize: sceneSize)
        let maxAllowedWidth = min(sceneBasedWidth, 400.0)
        let actualMaxWidth = min(singleLineWidth + padding, maxAllowedWidth)
        let wrappedLines = TutorialTile.wrapText(message, maxWidth: actualMaxWidth - padding, fontSize: fontSize)
        
        // Calculate final dimensions
        let tileWidth = max(min(singleLineWidth + padding, actualMaxWidth), minWidth)
        let tileHeight = CGFloat(wrappedLines.count) * lineHeight + padding
        let baseMinHeight: CGFloat = 40  // Original minimum height
        let calculatedSize = CGSize(width: tileWidth, height: max(tileHeight, baseMinHeight * PhysicsGameScene.componentScaleFactor))
        
        super.init(size: calculatedSize)
        
        // Create tutorial labels for each line
        for (index, line) in wrappedLines.enumerated() {
            let label = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
            label.fontSize = fontSize
            label.fontColor = .white // White text on purple background
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.zPosition = 10.0
            label.text = line
            
            // Position labels vertically
            let yOffset = CGFloat(wrappedLines.count - 1 - index) * lineHeight - CGFloat(wrappedLines.count - 1) * lineHeight / 2
            label.position = CGPoint(x: 0, y: yOffset)
            
            tutorialLabels.append(label)
            addChild(label)
        }
    }
    
    // Helper methods for text wrapping calculation (same as MessageTile)
    static func calculateMaxTileWidth(sceneSize: CGSize) -> CGFloat {
        // 80% of scene width (representing shelf area)
        return sceneSize.width * 0.8
    }
    
    static func wrapText(_ text: String, maxWidth: CGFloat, fontSize: CGFloat) -> [String] {
        let words = text.components(separatedBy: " ")
        var lines: [String] = []
        var currentLine = ""
        
        let tempLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        tempLabel.fontSize = fontSize
        
        for word in words {
            let testLine = currentLine.isEmpty ? word : "\(currentLine) \(word)"
            tempLabel.text = testLine
            
            if tempLabel.frame.width <= maxWidth {
                currentLine = testLine
            } else {
                if !currentLine.isEmpty {
                    lines.append(currentLine)
                    currentLine = word
                } else {
                    // Single word is too long, just add it anyway
                    lines.append(word)
                }
            }
        }
        
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        
        return lines.isEmpty ? [""] : lines
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}