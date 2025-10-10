//
//  ColorPickerPopover.swift
//  JamAI
//
//  FigJam-style color picker popover for node organization
//

import SwiftUI

struct ColorPickerPopover: View {
    let selectedColorId: String
    let onColorSelected: (String) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(NodeColor.palette.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 8) {
                    ForEach(row) { nodeColor in
                        ColorButton(
                            nodeColor: nodeColor,
                            isSelected: nodeColor.id == selectedColorId,
                            onSelect: {
                                onColorSelected(nodeColor.id)
                                dismiss()
                            }
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 2)
    }
}

struct ColorButton: View {
    let nodeColor: NodeColor
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            ZStack {
                // Color circle
                if nodeColor.id == "rainbow" {
                    // Rainbow gradient
                    Circle()
                        .fill(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red
                                ]),
                                center: .center
                            )
                        )
                        .frame(width: 32, height: 32)
                } else {
                    Circle()
                        .fill(nodeColor.color)
                        .frame(width: 32, height: 32)
                }
                
                // Selection ring
                if isSelected {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 3)
                        .frame(width: 36, height: 36)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .help(nodeColor.name)
    }
}

// Preview
#Preview {
    ColorPickerPopover(selectedColorId: "blue") { _ in }
        .frame(width: 400, height: 200)
}
