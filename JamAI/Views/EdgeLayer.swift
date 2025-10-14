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
        // Use Shape-based rendering instead of Canvas to avoid clipping issues
        // Shapes don't clip at coordinate boundaries like Canvas does
        ZStack {
            ForEach(edges, id: \.id) { edge in
                if let sFrame = frames[edge.sourceId],
                   let tFrame = frames[edge.targetId] {
                    let (start, end, isHorizontal) = bestPorts(from: sFrame, to: tFrame)
                    
                    ZStack {
                        // The bezier curve edge
                        EdgeShape(from: start, to: end, horizontalPreferred: isHorizontal)
                            .stroke(strokeColor(for: edge), lineWidth: 2.0)
                        
                        // The arrow head
                        EdgeArrowShape(from: start, to: end, horizontalPreferred: isHorizontal)
                            .stroke(strokeColor(for: edge), lineWidth: 2.0)
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

    // Choose best side ports (left/right/top/bottom) based on relative positions
    // Returns: (startWorldPoint, endWorldPoint, prefersHorizontalBezier)
    private func bestPorts(from s: CGRect, to t: CGRect) -> (CGPoint, CGPoint, Bool) {
        let sc = CGPoint(x: s.midX, y: s.midY)
        let tc = CGPoint(x: t.midX, y: t.midY)
        let dx = tc.x - sc.x
        let dy = tc.y - sc.y
        if abs(dx) >= abs(dy) {
            // Prefer horizontal routing
            // Wire exits from source's right/left edge and enters target's left/right edge
            if dx >= 0 {
                // Target is to the right: exit from source's right, enter target's left
                let start = CGPoint(x: s.maxX, y: sc.y)
                let end = CGPoint(x: t.minX, y: tc.y)
                return (start, end, true)
            } else {
                // Target is to the left: exit from source's left, enter target's right
                let start = CGPoint(x: s.minX, y: sc.y)
                let end = CGPoint(x: t.maxX, y: tc.y)
                return (start, end, true)
            }
        } else {
            // Prefer vertical routing
            // Wire exits from source's top/bottom edge and enters target's bottom/top edge
            if dy >= 0 {
                // Target is below: exit from source's bottom, enter target's top
                let start = CGPoint(x: sc.x, y: s.maxY)
                let end = CGPoint(x: tc.x, y: t.minY)
                return (start, end, false)
            } else {
                // Target is above: exit from source's top, enter target's bottom
                let start = CGPoint(x: sc.x, y: s.minY)
                let end = CGPoint(x: tc.x, y: t.maxY)
                return (start, end, false)
            }
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
            // Horizontal routing: control points extend left/right
            let dx = (to.x - from.x) * 0.5
            let control1 = CGPoint(x: from.x + dx, y: from.y)
            let control2 = CGPoint(x: to.x - dx, y: to.y)
            path.addCurve(to: to, control1: control1, control2: control2)
        } else {
            // Vertical routing: control points extend up/down
            let dy = (to.y - from.y) * 0.5
            let control1 = CGPoint(x: from.x, y: from.y + dy)
            let control2 = CGPoint(x: to.x, y: to.y - dy)
            path.addCurve(to: to, control1: control1, control2: control2)
        }
        
        return path
    }
}

struct EdgeArrowShape: Shape {
    let from: CGPoint
    let to: CGPoint
    let horizontalPreferred: Bool
    
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
        
        let angle = atan2(to.y - control2.y, to.x - control2.x)
        let arrowSize: CGFloat = 10.0
        
        var path = Path()
        path.move(to: to)
        path.addLine(to: CGPoint(
            x: to.x - arrowSize * cos(angle - .pi / 6),
            y: to.y - arrowSize * sin(angle - .pi / 6)
        ))
        path.move(to: to)
        path.addLine(to: CGPoint(
            x: to.x - arrowSize * cos(angle + .pi / 6),
            y: to.y - arrowSize * sin(angle + .pi / 6)
        ))
        
        return path
    }
}
