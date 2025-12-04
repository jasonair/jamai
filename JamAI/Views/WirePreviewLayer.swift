//
//  WirePreviewLayer.swift
//  JamAI
//
//  Renders a preview wire during drag-to-connect operations
//

import SwiftUI

struct WirePreviewLayer: View {
    let sourceNodeId: UUID?
    let sourceSide: ConnectionSide?
    let endPoint: CGPoint?
    let nodes: [UUID: Node]
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        if let sourceId = sourceNodeId,
           let side = sourceSide,
           let end = endPoint,
           let sourceNode = nodes[sourceId] {
            
            let sourceFrame = CGRect(
                x: sourceNode.x,
                y: sourceNode.y,
                width: sourceNode.width,
                height: sourceNode.height
            )
            let start = side.position(for: sourceFrame)
            
            ZStack {
                // The preview bezier curve
                WirePreviewShape(from: start, to: end)
                    .stroke(strokeColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                
                // End point indicator
                Circle()
                    .fill(strokeColor.opacity(0.8))
                    .frame(width: 8, height: 8)
                    .position(end)
            }
        }
    }
    
    private var strokeColor: Color {
        colorScheme == .dark
            ? Color.accentColor.opacity(0.8)
            : Color.accentColor.opacity(0.7)
    }
}

// MARK: - Wire Preview Shape

struct WirePreviewShape: Shape {
    let from: CGPoint
    let to: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        
        let dx = to.x - from.x
        let dy = to.y - from.y
        
        // Determine routing direction based on relative positions
        if abs(dx) >= abs(dy) {
            // Horizontal routing
            let controlOffset = abs(dx) * 0.5
            let control1 = CGPoint(x: from.x + (dx > 0 ? controlOffset : -controlOffset), y: from.y)
            let control2 = CGPoint(x: to.x - (dx > 0 ? controlOffset : -controlOffset), y: to.y)
            path.addCurve(to: to, control1: control1, control2: control2)
        } else {
            // Vertical routing
            let controlOffset = abs(dy) * 0.5
            let control1 = CGPoint(x: from.x, y: from.y + (dy > 0 ? controlOffset : -controlOffset))
            let control2 = CGPoint(x: to.x, y: to.y - (dy > 0 ? controlOffset : -controlOffset))
            path.addCurve(to: to, control1: control1, control2: control2)
        }
        
        return path
    }
}
