//
//  ScoreTile.swift
//  Anagram Game
//
//  Score display tiles showing only points
//

import SwiftUI
import SpriteKit

class ScoreTile: InformationTile {
    private var scoreLabel: SKLabelNode?
    
    override init(size: CGSize = CGSize(width: 80, height: 60)) {
        super.init(size: size)
        setupScoreLabels()
    }
    
    private func setupScoreLabels() {
        // Create score label (centered)
        scoreLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        scoreLabel?.fontSize = InformationTile.primaryFontSize
        scoreLabel?.fontColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        scoreLabel?.verticalAlignmentMode = .center
        scoreLabel?.horizontalAlignmentMode = .center
        scoreLabel?.position = CGPoint(x: 0, y: 0) // Centered since no difficulty label
        scoreLabel?.zPosition = 10.0
        addChild(scoreLabel!)
    }
    
    func updateScore(_ score: Int, difficulty: Int? = nil) {
        scoreLabel?.text = "\(score) pts"
        // Difficulty parameter ignored - only showing score now
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}