//
//  ScoreTile.swift
//  Anagram Game
//
//  Score display tiles showing points and difficulty
//

import SwiftUI
import SpriteKit

class ScoreTile: InformationTile {
    private var scoreLabel: SKLabelNode?
    private var difficultyLabel: SKLabelNode?
    
    override init(size: CGSize = CGSize(width: 80, height: 60)) {
        super.init(size: size)
        setupScoreLabels()
    }
    
    private func setupScoreLabels() {
        // Create score label (top line)
        scoreLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        scoreLabel?.fontSize = InformationTile.primaryFontSize
        scoreLabel?.fontColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        scoreLabel?.verticalAlignmentMode = .center
        scoreLabel?.horizontalAlignmentMode = .center
        scoreLabel?.position = CGPoint(x: 0, y: 8)
        scoreLabel?.zPosition = 10.0
        addChild(scoreLabel!)
        
        // Create difficulty label (bottom line)
        difficultyLabel = SKLabelNode(fontNamed: "Arial")
        difficultyLabel?.fontSize = InformationTile.secondaryFontSize
        difficultyLabel?.fontColor = UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0)
        difficultyLabel?.verticalAlignmentMode = .center
        difficultyLabel?.horizontalAlignmentMode = .center
        difficultyLabel?.position = CGPoint(x: 0, y: -8)
        difficultyLabel?.zPosition = 10.0
        addChild(difficultyLabel!)
    }
    
    func updateScore(_ score: Int, difficulty: Int? = nil) {
        scoreLabel?.text = "\(score) pts"
        
        if let difficulty = difficulty {
            let level = getDifficultyLevel(for: difficulty)
            difficultyLabel?.text = "\(level) (\(difficulty))"
        }
    }
    
    private func getDifficultyLevel(for score: Int) -> String {
        switch score {
        case 0..<20:
            return "Very Easy"
        case 20..<40:
            return "Easy"
        case 40..<60:
            return "Medium"
        case 60..<80:
            return "Hard"
        default:
            return "Very Hard"
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}