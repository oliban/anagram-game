//
//  SpriteKitView.swift
//  Anagram Game
//
//  Created by Claude on 2025-07-29.
//  Extracted from PhysicsGameView.swift during refactoring
//

import SwiftUI
import SpriteKit

struct SpriteKitView: UIViewRepresentable {
    let scene: SKScene
    
    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.presentScene(scene)
        view.ignoresSiblingOrder = true
        view.showsFPS = false
        view.showsNodeCount = false
        return view
    }
    
    func updateUIView(_ uiView: SKView, context: Context) {
        // Update if needed
    }
}