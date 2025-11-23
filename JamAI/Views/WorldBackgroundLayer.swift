//
//  WorldBackgroundLayer.swift
//  JamAI
//
//  Draws a tiled grid or dots in world coordinates. Sizes counter-scale with zoom.
//

import SwiftUI

struct WorldBackgroundLayer: View, Equatable {
    let zoom: CGFloat
    let offset: CGSize
    let style: CanvasBackgroundStyle
    
    @Environment(\.colorScheme) private var colorScheme
    
    // Only redraw when zoom, offset, or style actually change
    static func == (lhs: WorldBackgroundLayer, rhs: WorldBackgroundLayer) -> Bool {
        lhs.zoom == rhs.zoom &&
        lhs.offset == rhs.offset &&
        lhs.style == rhs.style
    }
    
    var body: some View {
        Canvas { context, size in
            let z = max(zoom, 0.001)
            let scaledSpacing = Config.gridSize * z // tiles scale with zoom
            // compute starting offsets in screen-space
            var startX = offset.width.truncatingRemainder(dividingBy: scaledSpacing)
            var startY = offset.height.truncatingRemainder(dividingBy: scaledSpacing)
            if startX < 0 { startX += scaledSpacing }
            if startY < 0 { startY += scaledSpacing }

            switch style {
            case .dots:
                // Dots: slight size and opacity boost as you zoom in (Freeform-like)
                let dotSize: CGFloat = min(4.0, max(2.0, 2.0 + (z - 1.0) * 1.2))
                // Strong contrast in both modes so dots are easy to see, with slightly
                // lower intensity in dark mode to avoid overpowering the canvas.
                let baseAlpha: Double = (colorScheme == .dark) ? 0.20 : 0.14
                let alphaBoost: Double = (colorScheme == .dark)
                    ? min(0.16, max(0.0, Double(z - 1.0) * 0.10))
                    : min(0.10, max(0.0, Double(z - 1.0) * 0.10))
                let dotColor: Color = (colorScheme == .dark ? Color.white : Color.black).opacity(baseAlpha + alphaBoost)
                var y = startY
                while y < size.height {
                    var x = startX
                    while x < size.width {
                        let rect = CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize)
                        context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                        x += scaledSpacing
                    }
                    y += scaledSpacing
                }
            case .grid:
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
            case .blank:
                // Intentionally draw nothing for a clean canvas background
                break
            }
        }
    }
    
    private var gridColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)
    }
}
