//
//  ResizeGripView.swift
//  JamAI
//
//  macOS-style resize grip indicator with three diagonal lines
//

import SwiftUI

struct ResizeGripView: View {
    @Environment(\.colorScheme) var colorScheme
    
    /// Whether to force black color (for light backgrounds in dark mode)
    var forceBlack: Bool = false
    
    var body: some View {
        Canvas { context, size in
            let lineWidth: CGFloat = 1.5
            let spacing: CGFloat = 3.5
            let lineLength: CGFloat = 12
            
            // Color based on appearance
            // In dark mode with light node colors, use black for visibility
            let color: Color
            if forceBlack {
                color = Color.black.opacity(0.4)
            } else {
                color = colorScheme == .dark 
                    ? Color.white.opacity(0.4)
                    : Color.black.opacity(0.3)
            }
            
            // Draw three diagonal lines (bottom-left to top-right)
            for i in 0..<3 {
                let offset = CGFloat(i) * spacing
                let startX = size.width - lineLength + offset
                let startY = size.height
                let endX = size.width
                let endY = size.height - lineLength + offset
                
                var path = Path()
                path.move(to: CGPoint(x: startX, y: startY))
                path.addLine(to: CGPoint(x: endX, y: endY))
                
                context.stroke(
                    path,
                    with: .color(color),
                    lineWidth: lineWidth
                )
            }
        }
        .frame(width: 16, height: 16)
    }
}
