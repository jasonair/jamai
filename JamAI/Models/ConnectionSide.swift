//
//  ConnectionSide.swift
//  JamAI
//
//  Represents the four sides of a node for connection points
//

import Foundation
import SwiftUI

/// Represents which side of a node a connection point is on
enum ConnectionSide: String, Codable, Sendable, CaseIterable {
    case top
    case right
    case bottom
    case left
    
    /// Returns the position of the connection point relative to the node's frame
    func position(for frame: CGRect) -> CGPoint {
        switch self {
        case .top:
            return CGPoint(x: frame.midX, y: frame.minY)
        case .right:
            return CGPoint(x: frame.maxX, y: frame.midY)
        case .bottom:
            return CGPoint(x: frame.midX, y: frame.maxY)
        case .left:
            return CGPoint(x: frame.minX, y: frame.midY)
        }
    }
    
    /// Returns the offset from the edge for displaying the connection point
    func offset(size: CGFloat = 0) -> CGSize {
        switch self {
        case .top:
            return CGSize(width: 0, height: -size / 2)
        case .right:
            return CGSize(width: size / 2, height: 0)
        case .bottom:
            return CGSize(width: 0, height: size / 2)
        case .left:
            return CGSize(width: -size / 2, height: 0)
        }
    }
    
    /// Returns the opposite side (for determining wire entry point)
    var opposite: ConnectionSide {
        switch self {
        case .top: return .bottom
        case .right: return .left
        case .bottom: return .top
        case .left: return .right
        }
    }
}
