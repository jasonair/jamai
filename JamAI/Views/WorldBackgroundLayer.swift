//
//  WorldBackgroundLayer.swift
//  JamAI
//
//  Draws a tiled grid or dots in world coordinates. Sizes counter-scale with zoom.
//

import SwiftUI

struct WorldBackgroundLayer: View {
    let zoom: CGFloat
    let offset: CGSize
    let showDots: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Canvas { context, size in
            let spacing = Config.gridSize
            let z = max(zoom, 0.001)
            let worldLeft = -offset.width / z
            let worldTop = -offset.height / z
            let worldWidth = size.width / z
            let worldHeight = size.height / z
            let startX = floor(worldLeft / spacing) * spacing
            let startY = floor(worldTop / spacing) * spacing
            let endX = worldLeft + worldWidth
            let endY = worldTop + worldHeight
            
            if showDots {
                let dotSize: CGFloat = 2.0 / z
                var y = startY
                while y <= endY {
                    var x = startX
                    while x <= endX {
                        let rect = CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize)
                        context.fill(Path(ellipseIn: rect), with: .color(gridColor))
                        x += spacing
                    }
                    y += spacing
                }
            } else {
                let lineWidth: CGFloat = 1.0 / z
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
    }
    
    private var gridColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)
    }
}
