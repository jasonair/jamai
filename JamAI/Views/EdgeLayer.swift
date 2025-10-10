//
//  EdgeLayer.swift
//  JamAI
//
//  Renders Bezier curve connections between nodes
//

import SwiftUI
import Combine

struct EdgeLayer: View {
    let edges: [Edge]
    let nodes: [UUID: Node]
    let zoom: CGFloat
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Canvas { context, size in
            for edge in edges {
                guard let source = nodes[edge.sourceId],
                      let target = nodes[edge.targetId] else {
                    continue
                }
                
                let sourcePosCenter = CGPoint(
                    x: source.x + (source.isExpanded ? Node.expandedWidth : Node.collapsedWidth) / 2,
                    y: source.y + (source.isExpanded ? Node.expandedHeight : Node.collapsedHeight)
                )
                
                let targetPosTop = CGPoint(
                    x: target.x + (target.isExpanded ? Node.expandedWidth : Node.collapsedWidth) / 2,
                    y: target.y
                )
                
                drawBezierCurve(
                    context: context,
                    from: sourcePosCenter,
                    to: targetPosTop
                )
            }
        }
    }
    
    private func drawBezierCurve(context: GraphicsContext, from start: CGPoint, to end: CGPoint) {
        var path = Path()
        path.move(to: start)
        
        // Control points for smooth Bezier curve
        let controlPointOffset: CGFloat = abs(end.y - start.y) * 0.5
        let control1 = CGPoint(x: start.x, y: start.y + controlPointOffset)
        let control2 = CGPoint(x: end.x, y: end.y - controlPointOffset)
        
        path.addCurve(to: end, control1: control1, control2: control2)
        
        context.stroke(
            path,
            with: .color(edgeColor),
            lineWidth: 2.0 / zoom
        )
        
        // Draw arrow at end
        drawArrowHead(context: context, at: end, angle: getAngle(from: control2, to: end))
    }
    
    private func drawArrowHead(context: GraphicsContext, at point: CGPoint, angle: Double) {
        let arrowSize: CGFloat = 10.0 / zoom
        
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
            lineWidth: 2.0 / zoom
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
