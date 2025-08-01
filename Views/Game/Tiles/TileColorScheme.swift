//
//  TileColorScheme.swift
//  Anagram Game
//
//  Color scheme system for 3D tile rendering
//

import SwiftUI

// MARK: - Tile Color Scheme System
struct TileColorScheme {
    let topFace: UIColor      // Light color for 3D top surface
    let frontFace: UIColor    // Main visible surface
    let rightFace: UIColor    // Shadow side (darker)
    let strokeColor: UIColor  // Border color
}

extension TileColorScheme {
    // Yellow scheme for letter tiles
    static let yellow = TileColorScheme(
        topFace: UIColor(red: 1.0, green: 1.0, blue: 0.8, alpha: 1.0),     // Very bright almost white yellow
        frontFace: .systemYellow,                                            // Standard yellow
        rightFace: UIColor(red: 0.2, green: 0.1, blue: 0.0, alpha: 1.0),   // Very dark shadow
        strokeColor: .black
    )
    
    // Green scheme for information tiles
    static let green = TileColorScheme(
        topFace: UIColor(red: 0.3, green: 1.0, blue: 0.3, alpha: 1.0),     // Light green
        frontFace: UIColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0),   // Medium green
        rightFace: UIColor(red: 0.1, green: 0.4, blue: 0.1, alpha: 1.0),   // Dark green shadow
        strokeColor: .black
    )
    
    // Blue scheme for theme tiles
    static let blue = TileColorScheme(
        topFace: UIColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1.0),     // Light blue
        frontFace: UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0),   // Medium blue
        rightFace: UIColor(red: 0.1, green: 0.2, blue: 0.6, alpha: 1.0),   // Dark blue shadow
        strokeColor: .black
    )
}