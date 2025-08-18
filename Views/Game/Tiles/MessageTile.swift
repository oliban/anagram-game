//
//  MessageTile.swift
//  Anagram Game
//
//  Message display tiles for showing text content
//

import SwiftUI
import SpriteKit

class MessageTile: InformationTile {
    private var messageLabels: [SKLabelNode] = []
    
    var messageText: String {
        return messageLabels.first?.text ?? ""
    }
    
    /// Override maxAge for level-up message tiles
    override var maxAge: Int {
        let text = messageText.lowercased()
        if text.contains("🎉") && (text.contains("novice") || text.contains("beginner") || text.contains("intermediate") || text.contains("advanced") || text.contains("expert") || text.contains("master") || text.contains("grandmaster") || text.contains("legendary") || text.contains("formidable") || text.contains("elite")) {
            return 3  // Level-up tiles persist for 3 games
        }
        return 1  // Other message tiles cleanup after 1 game
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
        let sceneBasedWidth = MessageTile.calculateMaxTileWidth(sceneSize: sceneSize)
        let maxAllowedWidth = min(sceneBasedWidth, 400.0)
        let actualMaxWidth = min(singleLineWidth + padding, maxAllowedWidth)
        let wrappedLines = MessageTile.wrapText(message, maxWidth: actualMaxWidth - padding, fontSize: fontSize)
        
        // Calculate final dimensions
        let tileWidth = max(min(singleLineWidth + padding, actualMaxWidth), minWidth)
        let tileHeight = CGFloat(wrappedLines.count) * lineHeight + padding
        let baseMinHeight: CGFloat = 40  // Original minimum height
        let calculatedSize = CGSize(width: tileWidth, height: max(tileHeight, baseMinHeight * PhysicsGameScene.componentScaleFactor))
        
        super.init(size: calculatedSize)
        
        // Create message labels for each line
        for (index, line) in wrappedLines.enumerated() {
            let label = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
            label.fontSize = fontSize
            label.fontColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.zPosition = 10.0
            label.text = line
            
            // Position labels vertically
            let yOffset = CGFloat(wrappedLines.count - 1 - index) * lineHeight - CGFloat(wrappedLines.count - 1) * lineHeight / 2
            label.position = CGPoint(x: 0, y: yOffset)
            
            messageLabels.append(label)
            addChild(label)
        }
    }
    
    // Helper methods for text wrapping calculation
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