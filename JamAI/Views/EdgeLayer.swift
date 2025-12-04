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
    // With 3px gap + 8px radius, circle center is 11px from node edge
    private let connectionPointOffset: CGFloat = 11
    
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
            
            // Half-circle cap at the end (target)
            EdgeHalfCircleCap(from: from, to: to, horizontalPreferred: horizontalPreferred)
                .fill(strokeColor)
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

/// Half-circle cap at the target end of an edge
struct EdgeHalfCircleCap: Shape {
    let from: CGPoint
    let to: CGPoint
    let horizontalPreferred: Bool
    
    private let radius: CGFloat = 6.0
    
    func path(in rect: CGRect) -> Path {
        // Calculate the angle from the control point to the end point
        let control2: CGPoint
        if horizontalPreferred {
            let dx = (to.x - from.x) * 0.5
            control2 = CGPoint(x: to.x - dx, y: to.y)
        } else {
            let dy = (to.y - from.y) * 0.5
            control2 = CGPoint(x: to.x, y: to.y - dy)
        }
        
        // Angle pointing from control2 toward the target
        let angle = atan2(to.y - control2.y, to.x - control2.x)
        
        var path = Path()
        
        // Draw a half-circle (semicircle) at the target point
        // The flat side faces the incoming edge, curved side faces the node
        let startAngle = Angle(radians: Double(angle) - .pi / 2)
        let endAngle = Angle(radians: Double(angle) + .pi / 2)
        
        path.addArc(
            center: to,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.closeSubpath()
        
        return path
    }
}
