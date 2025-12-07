//
//  SnapGuideService.swift
//  JamAI
//
//  Service for calculating snap-to-align positions during node dragging.
//  Implements Figma/Illustrator-style snapping to nearby object edges and centers.
//

import Foundation
import SwiftUI

/// Represents a snap guide line to be displayed on the canvas
struct SnapGuide: Identifiable, Equatable {
    let id = UUID()
    let orientation: Orientation
    let position: CGFloat  // x for vertical, y for horizontal
    let start: CGFloat     // start coordinate (y for vertical, x for horizontal)
    let end: CGFloat       // end coordinate
    
    enum Orientation {
        case horizontal
        case vertical
    }
}

/// Result of snap calculation
struct SnapResult {
    var snappedPosition: CGPoint
    var guides: [SnapGuide]
    var didSnapX: Bool
    var didSnapY: Bool
}

/// Service that calculates snap positions based on nearby nodes
@MainActor
class SnapGuideService {
    static let shared = SnapGuideService()
    
    private init() {}
    
    /// Calculate snap position for a dragged node
    /// - Parameters:
    ///   - draggedNodeId: ID of the node being dragged
    ///   - proposedPosition: The proposed position (before snapping)
    ///   - draggedNodeSize: Size of the dragged node (width, height)
    ///   - allNodes: Dictionary of all nodes
    ///   - threshold: Distance within which to snap (in canvas coordinates)
    /// - Returns: SnapResult with snapped position and guide lines
    func calculateSnap(
        draggedNodeId: UUID,
        proposedPosition: CGPoint,
        draggedNodeSize: CGSize,
        allNodes: [UUID: Node],
        selectedNodeIds: Set<UUID>,
        threshold: CGFloat = Config.snapThreshold
    ) -> SnapResult {
        var guides: [SnapGuide] = []
        var snappedX = proposedPosition.x
        var snappedY = proposedPosition.y
        var didSnapX = false
        var didSnapY = false
        
        // Get all nodes except the dragged one and any other selected nodes
        let otherNodes = allNodes.values.filter { node in
            node.id != draggedNodeId && !selectedNodeIds.contains(node.id)
        }
        
        guard !otherNodes.isEmpty else {
            return SnapResult(
                snappedPosition: proposedPosition,
                guides: [],
                didSnapX: false,
                didSnapY: false
            )
        }
        
        // Calculate dragged node's key positions
        let draggedLeft = proposedPosition.x
        let draggedRight = proposedPosition.x + draggedNodeSize.width
        let draggedCenterX = proposedPosition.x + draggedNodeSize.width / 2
        let draggedTop = proposedPosition.y
        let draggedBottom = proposedPosition.y + draggedNodeSize.height
        let draggedCenterY = proposedPosition.y + draggedNodeSize.height / 2
        
        // Track best snap candidates
        var bestXSnap: (distance: CGFloat, snapTo: CGFloat, type: XSnapType)? = nil
        var bestYSnap: (distance: CGFloat, snapTo: CGFloat, type: YSnapType)? = nil
        
        enum XSnapType { case left, center, right }
        enum YSnapType { case top, center, bottom }
        
        for node in otherNodes {
            let nodeLeft = node.x
            let nodeRight = node.x + node.width
            let nodeCenterX = node.x + node.width / 2
            let nodeTop = node.y
            let nodeBottom = node.y + node.height
            let nodeCenterY = node.y + node.height / 2
            
            // Check X alignments (left, center, right edges)
            let xChecks: [(dragged: CGFloat, target: CGFloat, type: XSnapType)] = [
                (draggedLeft, nodeLeft, .left),       // Left to left
                (draggedLeft, nodeRight, .left),     // Left to right
                (draggedRight, nodeLeft, .right),   // Right to left
                (draggedRight, nodeRight, .right),  // Right to right
                (draggedCenterX, nodeCenterX, .center), // Center to center
                (draggedLeft, nodeCenterX, .left),  // Left to center
                (draggedRight, nodeCenterX, .right), // Right to center
                (draggedCenterX, nodeLeft, .center), // Center to left
                (draggedCenterX, nodeRight, .center) // Center to right
            ]
            
            for check in xChecks {
                let distance = abs(check.dragged - check.target)
                if distance < threshold {
                    if bestXSnap == nil || distance < bestXSnap!.distance {
                        bestXSnap = (distance, check.target, check.type)
                    }
                }
            }
            
            // Check Y alignments (top, center, bottom edges)
            let yChecks: [(dragged: CGFloat, target: CGFloat, type: YSnapType)] = [
                (draggedTop, nodeTop, .top),         // Top to top
                (draggedTop, nodeBottom, .top),     // Top to bottom
                (draggedBottom, nodeTop, .bottom),  // Bottom to top
                (draggedBottom, nodeBottom, .bottom), // Bottom to bottom
                (draggedCenterY, nodeCenterY, .center), // Center to center
                (draggedTop, nodeCenterY, .top),    // Top to center
                (draggedBottom, nodeCenterY, .bottom), // Bottom to center
                (draggedCenterY, nodeTop, .center), // Center to top
                (draggedCenterY, nodeBottom, .center) // Center to bottom
            ]
            
            for check in yChecks {
                let distance = abs(check.dragged - check.target)
                if distance < threshold {
                    if bestYSnap == nil || distance < bestYSnap!.distance {
                        bestYSnap = (distance, check.target, check.type)
                    }
                }
            }
        }
        
        // Apply best X snap
        if let xSnap = bestXSnap {
            didSnapX = true
            switch xSnap.type {
            case .left:
                snappedX = xSnap.snapTo
            case .center:
                snappedX = xSnap.snapTo - draggedNodeSize.width / 2
            case .right:
                snappedX = xSnap.snapTo - draggedNodeSize.width
            }
            
            // Create vertical guide line
            let guideX = xSnap.snapTo
            let allYPositions = otherNodes.flatMap { [$0.y, $0.y + $0.height] } + [snappedY, snappedY + draggedNodeSize.height]
            let guideStart = allYPositions.min() ?? snappedY
            let guideEnd = allYPositions.max() ?? (snappedY + draggedNodeSize.height)
            
            guides.append(SnapGuide(
                orientation: .vertical,
                position: guideX,
                start: guideStart - 20,
                end: guideEnd + 20
            ))
        }
        
        // Apply best Y snap
        if let ySnap = bestYSnap {
            didSnapY = true
            switch ySnap.type {
            case .top:
                snappedY = ySnap.snapTo
            case .center:
                snappedY = ySnap.snapTo - draggedNodeSize.height / 2
            case .bottom:
                snappedY = ySnap.snapTo - draggedNodeSize.height
            }
            
            // Create horizontal guide line
            let guideY = ySnap.snapTo
            let allXPositions = otherNodes.flatMap { [$0.x, $0.x + $0.width] } + [snappedX, snappedX + draggedNodeSize.width]
            let guideStart = allXPositions.min() ?? snappedX
            let guideEnd = allXPositions.max() ?? (snappedX + draggedNodeSize.width)
            
            guides.append(SnapGuide(
                orientation: .horizontal,
                position: guideY,
                start: guideStart - 20,
                end: guideEnd + 20
            ))
        }
        
        return SnapResult(
            snappedPosition: CGPoint(x: snappedX, y: snappedY),
            guides: guides,
            didSnapX: didSnapX,
            didSnapY: didSnapY
        )
    }
    
    /// Calculate snap for multiple selected nodes being dragged together
    /// Uses the primary (first) node as the reference for snapping
    func calculateSnapForMultiple(
        primaryNodeId: UUID,
        proposedPosition: CGPoint,
        primaryNodeSize: CGSize,
        allNodes: [UUID: Node],
        selectedNodeIds: Set<UUID>,
        threshold: CGFloat = Config.snapThreshold
    ) -> SnapResult {
        // Use the same logic but exclude all selected nodes from snap targets
        return calculateSnap(
            draggedNodeId: primaryNodeId,
            proposedPosition: proposedPosition,
            draggedNodeSize: primaryNodeSize,
            allNodes: allNodes,
            selectedNodeIds: selectedNodeIds,
            threshold: threshold
        )
    }
}
