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
            let z = max(zoom, 0.001)
            let scaledSpacing = Config.gridSize * z // tiles scale with zoom
            // compute starting offsets in screen-space
            var startX = offset.width.truncatingRemainder(dividingBy: scaledSpacing)
            var startY = offset.height.truncatingRemainder(dividingBy: scaledSpacing)
            if startX < 0 { startX += scaledSpacing }
            if startY < 0 { startY += scaledSpacing }

            if showDots {
                let dotSize: CGFloat = 2.0 // constant screen size
                var y = startY
                while y < size.height {
                    var x = startX
                    while x < size.width {
                        let rect = CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize)
                        context.fill(Path(ellipseIn: rect), with: .color(gridColor))
                        x += scaledSpacing
                    }
                    y += scaledSpacing
                }
            } else {
                let lineWidth: CGFloat = 1.0 // constant screen size
                var x = startX
                while x < size.width {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(gridColor), lineWidth: lineWidth)
                    x += scaledSpacing
                }
                var y = startY
                while y < size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(gridColor), lineWidth: lineWidth)
                    y += scaledSpacing
                }
            }
        }
    }
    
    private var gridColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)
    }
}
