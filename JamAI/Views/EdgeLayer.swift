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
    let zoom: CGFloat
    let offset: CGSize
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        // Use TimelineView for real-time updates at 60fps
        TimelineView(.animation) { _ in
            Canvas { context, _ in
                for edge in edges {
                    guard let sFrame = frames[edge.sourceId],
                          let tFrame = frames[edge.targetId] else { continue }
                    
                    // World-space endpoints using best side ports
                    let (startW, endW, isHorizontal) = bestPorts(from: sFrame, to: tFrame)
                    
                    // Map to screen (top-left anchor): screen = world * zoom + offset
                    let start = CGPoint(
                        x: startW.x * zoom + offset.width,
                        y: startW.y * zoom + offset.height
                    )
                    let end = CGPoint(
                        x: endW.x * zoom + offset.width,
                        y: endW.y * zoom + offset.height
                    )
                    
                    let stroke = strokeColor(for: edge)
                    drawBezierCurve(context: context, from: start, to: end, color: stroke, horizontalPreferred: isHorizontal)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func drawBezierCurve(context: GraphicsContext, from start: CGPoint, to end: CGPoint, color: Color, horizontalPreferred: Bool) {
        var path = Path()
        path.move(to: start)
        // Control points based on orientation
        if horizontalPreferred {
            let dx = abs(end.x - start.x) * 0.5
            let control1 = CGPoint(x: start.x + dx, y: start.y)
            let control2 = CGPoint(x: end.x - dx, y: end.y)
            path.addCurve(to: end, control1: control1, control2: control2)
            context.stroke(path, with: .color(color), lineWidth: 2.0)
            drawArrowHead(context: context, at: end, angle: getAngle(from: control2, to: end), color: color)
            return
        } else {
            let dy = abs(end.y - start.y) * 0.5
            let control1 = CGPoint(x: start.x, y: start.y + dy)
            let control2 = CGPoint(x: end.x, y: end.y - dy)
            path.addCurve(to: end, control1: control1, control2: control2)
            context.stroke(path, with: .color(color), lineWidth: 2.0)
            drawArrowHead(context: context, at: end, angle: getAngle(from: control2, to: end), color: color)
            return
        }
    }
    
    private func drawArrowHead(context: GraphicsContext, at point: CGPoint, angle: Double, color: Color) {
        // Fixed screen-space arrow head size
        let arrowSize: CGFloat = 10.0
        
        var path = Path()
        path.move(to: point)
        path.addLine(to: CGPoint(
            x: point.x - arrowSize * cos(angle - .pi / 6),
            y: point.y - arrowSize * sin(angle - .pi / 6)
        ))
        path.move(to: point)
        path.addLine(to: CGPoint(
            x: point.x - arrowSize * cos(angle + .pi / 6),
            y: point.y - arrowSize * sin(angle + .pi / 6)
        ))
        
        context.stroke(path, with: .color(color), lineWidth: 2.0)
    }
    
    private func getAngle(from: CGPoint, to: CGPoint) -> Double {
        return atan2(to.y - from.y, to.x - from.x)
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
            let start = dx >= 0 ? CGPoint(x: s.maxX, y: sc.y) : CGPoint(x: s.minX, y: sc.y)
            let end = dx >= 0 ? CGPoint(x: t.minX, y: tc.y) : CGPoint(x: t.maxX, y: tc.y)
            return (start, end, true)
        } else {
            // Prefer vertical routing
            let start = dy >= 0 ? CGPoint(x: sc.x, y: s.maxY) : CGPoint(x: sc.x, y: s.minY)
            let end = dy >= 0 ? CGPoint(x: tc.x, y: t.minY) : CGPoint(x: tc.x, y: t.maxY)
            return (start, end, false)
        }
    }
}
