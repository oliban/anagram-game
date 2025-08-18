//
//  BaseTile.swift
//  Anagram Game
//
//  Abstract base class for all tiles with shared 3D geometry and physics
//

import SwiftUI
import SpriteKit

// MARK: - Abstract Base Tile Class
class BaseTile: SKSpriteNode, RespawnableTile {
    // Common properties
    var isBeingDragged = false
    var isSquashed = false
    private var frontFace: SKShapeNode?
    private var originalScale: CGFloat = 1.0
    
    // Abstract properties (must be overridden by subclasses)
    var tileColorScheme: TileColorScheme {
        fatalError("Subclasses must override tileColorScheme")
    }
    
    var physicsMass: CGFloat {
        // Default mass calculation based on tile area
        let tileArea = size.width * size.height
        return tileArea / 1600.0  // Base mass for 40x40 tile = 1.0
    }
    
    init(size: CGSize) {
        super.init(texture: nil, color: .clear, size: size)
        setupTileGeometry(size: size, colorScheme: tileColorScheme)
        setupPhysicsBody(size: size)
    }
    
    private func setupTileGeometry(size: CGSize, colorScheme: TileColorScheme) {
        let tileWidth = size.width
        let tileHeight = size.height
        let depth: CGFloat = 6
        
        // Create the main tile body (top surface)
        let topFace = SKShapeNode()
        let topPath = CGMutablePath()
        topPath.move(to: CGPoint(x: -tileWidth / 2, y: tileHeight / 2))
        topPath.addLine(to: CGPoint(x: tileWidth / 2, y: tileHeight / 2))
        topPath.addLine(to: CGPoint(x: tileWidth / 2 + depth, y: tileHeight / 2 + depth))
        topPath.addLine(to: CGPoint(x: -tileWidth / 2 + depth, y: tileHeight / 2 + depth))
        topPath.closeSubpath()
        topFace.path = topPath
        topFace.fillColor = colorScheme.topFace
        topFace.strokeColor = colorScheme.strokeColor
        topFace.lineWidth = 2
        topFace.zPosition = -0.1
        addChild(topFace)
        
        // Create the front face (main visible surface)
        let frontFaceShape = SKShapeNode()
        let frontPath = CGMutablePath()
        frontPath.move(to: CGPoint(x: -tileWidth / 2, y: -tileHeight / 2))
        frontPath.addLine(to: CGPoint(x: tileWidth / 2, y: -tileHeight / 2))
        frontPath.addLine(to: CGPoint(x: tileWidth / 2, y: tileHeight / 2))
        frontPath.addLine(to: CGPoint(x: -tileWidth / 2, y: tileHeight / 2))
        frontPath.closeSubpath()
        frontFaceShape.path = frontPath
        frontFaceShape.fillColor = colorScheme.frontFace
        frontFaceShape.strokeColor = colorScheme.strokeColor
        frontFaceShape.lineWidth = 2
        frontFaceShape.zPosition = 0.1
        self.frontFace = frontFaceShape
        addChild(frontFaceShape)
        
        // Create the right face (shadow side)
        let rightFace = SKShapeNode()
        let rightPath = CGMutablePath()
        rightPath.move(to: CGPoint(x: tileWidth / 2, y: tileHeight / 2))
        rightPath.addLine(to: CGPoint(x: tileWidth / 2, y: -tileHeight / 2))
        rightPath.addLine(to: CGPoint(x: tileWidth / 2 + depth, y: -tileHeight / 2 + depth))
        rightPath.addLine(to: CGPoint(x: tileWidth / 2 + depth, y: tileHeight / 2 + depth))
        rightPath.closeSubpath()
        rightFace.path = rightPath
        rightFace.fillColor = colorScheme.rightFace
        rightFace.strokeColor = UIColor(
            red: max(0, colorScheme.rightFace.cgColor.components?[0] ?? 0 - 0.1),
            green: max(0, colorScheme.rightFace.cgColor.components?[1] ?? 0 - 0.1),
            blue: max(0, colorScheme.rightFace.cgColor.components?[2] ?? 0 - 0.1),
            alpha: 1.0
        )
        rightFace.lineWidth = 2
        rightFace.zPosition = 0.0
        addChild(rightFace)
    }
    
    private func setupPhysicsBody(size: CGSize) {
        let depth: CGFloat = 6
        let physicsSize = CGSize(width: size.width + depth, height: size.height + depth)
        
        physicsBody = SKPhysicsBody(rectangleOf: physicsSize)
        physicsBody?.isDynamic = true
        physicsBody?.affectedByGravity = true
        physicsBody?.mass = physicsMass
        physicsBody?.friction = 0.8
        physicsBody?.restitution = 0.2
        physicsBody?.linearDamping = 0.95
        physicsBody?.angularDamping = 0.95
        physicsBody?.allowsRotation = true
        physicsBody?.density = 1.0
        
        // Physics categories
        physicsBody?.categoryBitMask = PhysicsCategories.tile
        physicsBody?.contactTestBitMask = PhysicsCategories.tile | PhysicsCategories.shelf | PhysicsCategories.floor
        physicsBody?.collisionBitMask = PhysicsCategories.tile | PhysicsCategories.shelf | PhysicsCategories.floor
        
        zPosition = 50
    }
    
    // MARK: - RespawnableTile Protocol
    func getTileMass() -> CGFloat {
        return physicsBody?.mass ?? physicsMass
    }
    
    func squashTile(intensity: CGFloat = 1.0, direction: CGVector = CGVector(dx: 0, dy: -1)) {
        guard !isSquashed else { return }
        
        isSquashed = true
        
        let absDirectionX = abs(direction.dx)
        let absDirectionY = abs(direction.dy)
        
        let squashFactor = 0.2 + (intensity * 0.3)
        let stretchFactor = 0.1 + (intensity * 0.2)
        
        var scaleX: CGFloat = 1.0
        var scaleY: CGFloat = 1.0
        
        if absDirectionY > absDirectionX {
            scaleY = 1.0 - squashFactor
            scaleX = 1.0 + stretchFactor
        } else {
            scaleX = 1.0 - squashFactor
            scaleY = 1.0 + stretchFactor
        }
        
        let squashAction = SKAction.group([
            SKAction.scaleX(to: scaleX, duration: 0.1),
            SKAction.scaleY(to: scaleY, duration: 0.1)
        ])
        
        let restoreAction = SKAction.group([
            SKAction.scaleX(to: 1.0, duration: 0.15),
            SKAction.scaleY(to: 1.0, duration: 0.15)
        ])
        
        let resetSquashFlag = SKAction.run { [weak self] in
            self?.isSquashed = false
        }
        
        let sequence = SKAction.sequence([squashAction, restoreAction, resetSquashFlag])
        run(sequence)
    }
    
    // MARK: - Touch Handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        isBeingDragged = true
        physicsBody?.velocity = CGVector.zero
        physicsBody?.angularVelocity = 0
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isBeingDragged, let touch = touches.first else { return }
        let location = touch.location(in: parent!)
        position = location
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isBeingDragged = false
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isBeingDragged = false
    }
    
    
    // Access to front face for subclasses (e.g., hint system)
    func getFrontFace() -> SKShapeNode? {
        return frontFace
    }
    
    // MARK: - Abstract Age Management Methods
    // These provide default implementations that subclasses can override
    
    /// Increments the age of this tile by one game (override in subclasses)
    func incrementAge() {
        // Default implementation - subclasses should override this
    }
    
    /// Returns true if this tile should be cleaned up (override in subclasses)
    func shouldCleanup() -> Bool {
        // Default implementation - never cleanup
        return false
    }
    
    /// Returns the current age of this tile (override in subclasses)
    func getCurrentAge() -> Int {
        // Default implementation - age 0
        return 0
    }
    
    /// Returns the maximum age for this tile before cleanup (override in subclasses)
    var maxAge: Int {
        // Default implementation - never cleanup
        return -1
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}