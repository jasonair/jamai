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
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        // Use TimelineView for real-time updates at 60fps
        TimelineView(.animation) { _ in
            Canvas { context, _ in
                for edge in edges {
                    guard let sFrame = frames[edge.sourceId],
                          let tFrame = frames[edge.targetId] else { continue }
                    
                    // Draw in world coordinates; world transform is applied by parent container
                    let start = CGPoint(x: sFrame.maxX, y: sFrame.minY + Node.padding)
                    let end = CGPoint(x: tFrame.minX, y: tFrame.minY + Node.padding)
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
        
        // Non-scaling stroke (counteracts parent world scale)
        context.stroke(path, with: .color(edgeColor), lineWidth: 2.0 / max(zoom, 0.001))
        
        // Draw arrow at end
        drawArrowHead(context: context, at: end, angle: getAngle(from: control2, to: end))
    }
    
    private func drawArrowHead(context: GraphicsContext, at point: CGPoint, angle: Double) {
        // Non-scaling arrow head size
        let arrowSize: CGFloat = 10.0 / max(zoom, 0.001)
        
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
