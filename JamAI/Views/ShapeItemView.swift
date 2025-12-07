import SwiftUI
import AppKit

struct ShapeItemView: View {
    @Binding var node: Node
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            shape
                .fill(fillColor)
                .overlay(
                    shape.stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                .frame(width: node.width, height: node.height)
                .onTapGesture {
                    // Set shift state for the tap handler
                    TapThroughView.lastTapWasShiftClick = NSEvent.modifierFlags.contains(.shift)
                    onTap()
                }
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(6)
        }
    }
    
    private var shape: AnyShape {
        AnyShape(kind: node.shapeKind ?? .rectangle, cornerRadius: 12)
    }
    
    private var fillColor: Color {
        if let c = NodeColor.color(for: node.color) {
            return c.lightVariant
        }
        return Color(nsColor: .controlBackgroundColor)
    }
}

struct AnyShape: Shape {
    let kind: ShapeKind
    let cornerRadius: CGFloat
    func path(in rect: CGRect) -> Path {
        switch kind {
        case .rectangle:
            return RoundedRectangle(cornerRadius: cornerRadius).path(in: rect)
        case .ellipse:
            return Ellipse().path(in: rect)
        }
    }
}
