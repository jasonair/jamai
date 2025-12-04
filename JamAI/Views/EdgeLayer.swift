//
//  EdgeLayer.swift
//  JamAI
//
//  Renders Bezier curve connections between nodes with real-time updates
//

import SwiftUI

struct EdgeLayer: View {
    let edges: [Edge]
    let frames: [UUID: CGRect]
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.0) * 14
            
            ZStack {
                ForEach(edges, id: \.id) { edge in
                    if let sFrame = frames[edge.sourceId],
                       let tFrame = frames[edge.targetId] {
                        let (start, end, isHorizontal) = bestPorts(from: sFrame, to: tFrame)
                        
                        // All edges are dashed with animation (RAG context flow)
                        AnimatedDashedEdgeView(
                            from: start,
                            to: end,
                            horizontalPreferred: isHorizontal,
                            strokeColor: strokeColor(for: edge),
                            dashPhase: CGFloat(phase)
                        )
                    }
                }
            }
        }
    }
    
    private var edgeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.3)
            : Color.black.opacity(0.2)
    }
    
    private func strokeColor(for edge: Edge) -> Color {
        if let id = edge.color, let c = NodeColor.color(for: id) {
            return c.color
        }
        return edgeColor
    }

    // Gap between node edge and connection point center (must match ConnectionPointsOverlayInline.edgeGap)
    // Connection circles are positioned edgeGap pixels OUTSIDE the node bounds
    // With 6px gap + 8px radius, circle center is 14px from node edge
    private let connectionPointOffset: CGFloat = 14
    
    // Choose best side ports (left/right/top/bottom) based on relative positions
    // Points are offset to align with connection circle centers (outside the node)
    private func bestPorts(from s: CGRect, to t: CGRect) -> (CGPoint, CGPoint, Bool) {
        let sc = CGPoint(x: s.midX, y: s.midY)
        let tc = CGPoint(x: t.midX, y: t.midY)
        let dx = tc.x - sc.x
        let dy = tc.y - sc.y
        if abs(dx) >= abs(dy) {
            if dx >= 0 {
                // Source exits right (circle is to the right of node), target enters left (circle is to the left of node)
                let start = CGPoint(x: s.maxX + connectionPointOffset, y: sc.y)
                let end = CGPoint(x: t.minX - connectionPointOffset, y: tc.y)
                return (start, end, true)
            } else {
                // Source exits left, target enters right
                let start = CGPoint(x: s.minX - connectionPointOffset, y: sc.y)
                let end = CGPoint(x: t.maxX + connectionPointOffset, y: tc.y)
                return (start, end, true)
            }
        } else {
            if dy >= 0 {
                // Source exits bottom, target enters top
                let start = CGPoint(x: sc.x, y: s.maxY + connectionPointOffset)
                let end = CGPoint(x: tc.x, y: t.minY - connectionPointOffset)
                return (start, end, false)
            } else {
                // Source exits top, target enters bottom
                let start = CGPoint(x: sc.x, y: s.minY - connectionPointOffset)
                let end = CGPoint(x: tc.x, y: t.maxY + connectionPointOffset)
                return (start, end, false)
            }
        }
    }
}

// MARK: - Animated Dashed Edge View

struct AnimatedDashedEdgeView: View {
    let from: CGPoint
    let to: CGPoint
    let horizontalPreferred: Bool
    let strokeColor: Color
    let dashPhase: CGFloat
    
    private let circleRadius: CGFloat = 8.0  // Match connection point radius
    
    var body: some View {
        ZStack {
            // Dashed bezier curve with animated flow
            EdgeShape(from: from, to: to, horizontalPreferred: horizontalPreferred)
                .stroke(
                    strokeColor,
                    style: StrokeStyle(
                        lineWidth: 2.0,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: [8, 6],
                        dashPhase: -dashPhase  // Negative for flow toward target
                    )
                )
            
            // Full circle at source (start) point
            Circle()
                .fill(Color.white)
                .frame(width: circleRadius * 2, height: circleRadius * 2)
                .overlay(
                    Circle()
                        .stroke(strokeColor, lineWidth: 1.5)
                )
                .position(from)
            
            // Full circle at target (end) point
            Circle()
                .fill(Color.white)
                .frame(width: circleRadius * 2, height: circleRadius * 2)
                .overlay(
                    Circle()
                        .stroke(strokeColor, lineWidth: 1.5)
                )
                .position(to)
        }
    }
}

// MARK: - Edge Shapes

struct EdgeShape: Shape {
    let from: CGPoint
    let to: CGPoint
    let horizontalPreferred: Bool
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        
        if horizontalPreferred {
            let dx = (to.x - from.x) * 0.5
            let control1 = CGPoint(x: from.x + dx, y: from.y)
            let control2 = CGPoint(x: to.x - dx, y: to.y)
            path.addCurve(to: to, control1: control1, control2: control2)
        } else {
            let dy = (to.y - from.y) * 0.5
            let control1 = CGPoint(x: from.x, y: from.y + dy)
            let control2 = CGPoint(x: to.x, y: to.y - dy)
            path.addCurve(to: to, control1: control1, control2: control2)
        }
        
        return path
    }
}

