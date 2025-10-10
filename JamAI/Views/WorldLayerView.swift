//
//  WorldLayerView.swift
//  JamAI
//
//  Hosts the edge layer and node items in world coordinates.
//

import SwiftUI

struct WorldLayerView: View {
    let edges: [Edge]
    let frames: [UUID: CGRect]
    let zoom: CGFloat
    let offset: CGSize
    let showDots: Bool
    let positionsVersion: Int
    let nodes: [Node]
    let nodeViewBuilder: (Node) -> AnyView
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // Background in world coordinates
            if showDots { dotsBackground } else { gridBackground }
            
            // Edges below nodes
            EdgeLayer(
                edges: edges,
                frames: frames,
                zoom: zoom
            )
            .id("edges-\(positionsVersion)")
            
            ForEach(nodes) { node in
                nodeViewBuilder(node)
            }
        }
    }

    // MARK: - World Backgrounds
    private var dotsBackground: some View {
        Canvas { context, size in
            let spacing = Config.gridSize
            let worldLeft = -offset.width / max(zoom, 0.001)
            let worldTop = -offset.height / max(zoom, 0.001)
            let worldWidth = size.width / max(zoom, 0.001)
            let worldHeight = size.height / max(zoom, 0.001)
            let startX = floor(worldLeft / spacing) * spacing
            let startY = floor(worldTop / spacing) * spacing
            let endX = worldLeft + worldWidth
            let endY = worldTop + worldHeight
            let dotSize: CGFloat = 2.0 / max(zoom, 0.001)
            
            var y = startY
            while y <= endY {
                var x = startX
                while x <= endX {
                    // Draw in world coords; parent scale keeps spacing; we counter-scale size
                    let rect = CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: rect), with: .color(gridColor))
                    x += spacing
                }
                y += spacing
            }
        }
    }

    private var gridBackground: some View {
        Canvas { context, size in
            let spacing = Config.gridSize
            let worldLeft = -offset.width / max(zoom, 0.001)
            let worldTop = -offset.height / max(zoom, 0.001)
            let worldWidth = size.width / max(zoom, 0.001)
            let worldHeight = size.height / max(zoom, 0.001)
            let startX = floor(worldLeft / spacing) * spacing
            let startY = floor(worldTop / spacing) * spacing
            let endX = worldLeft + worldWidth
            let endY = worldTop + worldHeight
            let lineWidth: CGFloat = 1.0 / max(zoom, 0.001)
            
            var x = startX
            while x <= endX {
                var path = Path()
                path.move(to: CGPoint(x: x, y: worldTop))
                path.addLine(to: CGPoint(x: x, y: worldTop + worldHeight))
                context.stroke(path, with: .color(gridColor), lineWidth: lineWidth)
                x += spacing
            }
            
            var y = startY
            while y <= endY {
                var path = Path()
                path.move(to: CGPoint(x: worldLeft, y: y))
                path.addLine(to: CGPoint(x: worldLeft + worldWidth, y: y))
                context.stroke(path, with: .color(gridColor), lineWidth: lineWidth)
                y += spacing
            }
        }
    }

    // Grid color matches CanvasView's gridColor logic
    private var gridColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.05)
            : Color.black.opacity(0.05)
    }
}
