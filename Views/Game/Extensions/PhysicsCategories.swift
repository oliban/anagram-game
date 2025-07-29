//
//  PhysicsCategories.swift
//  Anagram Game
//
//  Created by Claude on 2025-07-29.
//  Extracted from PhysicsGameView.swift during refactoring
//

import SpriteKit

/// Physics collision categories for different game objects
struct PhysicsCategories {
    static let tile: UInt32 = 0x1 << 0
    static let shelf: UInt32 = 0x1 << 1
    static let floor: UInt32 = 0x1 << 2
    static let wall: UInt32 = 0x1 << 3
}

/// Protocol for tiles that can be respawned when they go off-screen
protocol RespawnableTile: SKSpriteNode {
    var isBeingDragged: Bool { get set }
    var isSquashed: Bool { get set }
    func getTileMass() -> CGFloat
    func squashTile(intensity: CGFloat, direction: CGVector)
}