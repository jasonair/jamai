//
//  SnapGuideLayer.swift
//  JamAI
//
//  Visual layer that displays snap alignment guide lines during node dragging.
//  Shows red/pink guide lines when nodes snap to edges or centers of other nodes.
//

import SwiftUI

struct SnapGuideLayer: View {
    let guides: [SnapGuide]
    let zoom: CGFloat
    let offset: CGSize
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Canvas { context, size in
            for guide in guides {
                let path = pathForGuide(guide)
                
                // Draw the guide line
                context.stroke(
                    path,
                    with: .color(guideColor),
                    style: StrokeStyle(lineWidth: 1.0, dash: [4, 2])
                )
            }
        }
        .allowsHitTesting(false)
    }
    
    private var guideColor: Color {
        colorScheme == .dark ? Color.pink.opacity(0.8) : Color.red.opacity(0.7)
    }
    
    private func pathForGuide(_ guide: SnapGuide) -> Path {
        var path = Path()
        
        switch guide.orientation {
        case .vertical:
            // Vertical line at guide.position (x coordinate)
            let screenX = guide.position * zoom + offset.width
            let screenStartY = guide.start * zoom + offset.height
            let screenEndY = guide.end * zoom + offset.height
            
            path.move(to: CGPoint(x: screenX, y: screenStartY))
            path.addLine(to: CGPoint(x: screenX, y: screenEndY))
            
        case .horizontal:
            // Horizontal line at guide.position (y coordinate)
            let screenY = guide.position * zoom + offset.height
            let screenStartX = guide.start * zoom + offset.width
            let screenEndX = guide.end * zoom + offset.width
            
            path.move(to: CGPoint(x: screenStartX, y: screenY))
            path.addLine(to: CGPoint(x: screenEndX, y: screenY))
        }
        
        return path
    }
}

#Preview {
    SnapGuideLayer(
        guides: [
            SnapGuide(orientation: .vertical, position: 200, start: 100, end: 500),
            SnapGuide(orientation: .horizontal, position: 300, start: 100, end: 400)
        ],
        zoom: 1.0,
        offset: .zero
    )
    .frame(width: 600, height: 600)
    .background(Color.gray.opacity(0.2))
}
