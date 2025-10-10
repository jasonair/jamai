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
                    
                    // World-space endpoints
                    let startW = CGPoint(x: sFrame.maxX, y: sFrame.minY + Node.padding)
                    let endW = CGPoint(x: tFrame.minX, y: tFrame.minY + Node.padding)
                    
                    // Map to screen (top-left anchor): screen = world * zoom + offset
                    let start = CGPoint(
                        x: startW.x * zoom + offset.width,
                        y: startW.y * zoom + offset.height
                    )
                    let end = CGPoint(
                        x: endW.x * zoom + offset.width,
                        y: endW.y * zoom + offset.height
                    )
                    
                    drawBezierCurve(context: context, from: start, to: end)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func drawBezierCurve(context: GraphicsContext, from start: CGPoint, to end: CGPoint) {
        var path = Path()
        path.move(to: start)
        
        // Control points for smooth horizontal Bezier curve
        let horizontalOffset = abs(end.x - start.x) * 0.5
        let control1 = CGPoint(x: start.x + horizontalOffset, y: start.y)
        let control2 = CGPoint(x: end.x - horizontalOffset, y: end.y)
        
        path.addCurve(to: end, control1: control1, control2: control2)
        
        // Fixed screen-space stroke
        context.stroke(path, with: .color(edgeColor), lineWidth: 2.0)
        
        // Draw arrow at end
        drawArrowHead(context: context, at: end, angle: getAngle(from: control2, to: end))
    }
    
    private func drawArrowHead(context: GraphicsContext, at point: CGPoint, angle: Double) {
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
        
        context.stroke(
            path,
            with: .color(edgeColor),
            lineWidth: 2.0
        )
    }
    
    private func getAngle(from: CGPoint, to: CGPoint) -> Double {
        return atan2(to.y - from.y, to.x - from.x)
    }
    
    private var edgeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.3)
            : Color.black.opacity(0.2)
    }
}
