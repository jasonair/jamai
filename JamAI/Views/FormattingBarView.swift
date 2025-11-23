import SwiftUI

struct FormattingBarView: View {
    @Binding var node: Node
    @State private var showColorPicker = false
    @State private var isFontPickerPresented = false
    @State private var isSizePickerPresented = false
    
    var body: some View {
        HStack(spacing: 10) {
            if node.type == .text || node.type == .title {
                Button(action: { node.isBold.toggle() }) {
                    Image(systemName: "bold")
                        .font(.system(size: 12, weight: node.isBold ? .semibold : .regular))
                        .foregroundColor(node.isBold ? .accentColor : .primary)
                        .frame(width: 26, height: 24)
                        .background(node.isBold ? Color.accentColor.opacity(0.1) : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())

                // Font family dropdown (persona-style)
                Button(action: {
                    isFontPickerPresented.toggle()
                    if isFontPickerPresented { isSizePickerPresented = false }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "textformat")
                        Text(currentFontDisplayName)
                            .lineLimit(1)
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .popover(
                    isPresented: $isFontPickerPresented,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .top
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(fontOptions) { option in
                            Button(action: {
                                node.fontFamily = option.value
                                isFontPickerPresented = false
                            }) {
                                HStack {
                                    if option.isSelected(currentFamily: node.fontFamily) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.primary)
                                    } else {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .medium))
                                            .opacity(0)
                                    }
                                    Text(option.label)
                                        .font(.system(size: 11))
                                        .foregroundColor(.primary)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
                    )
                }

                // Font size dropdown (drop-up)
                Button(action: {
                    isSizePickerPresented.toggle()
                    if isSizePickerPresented { isFontPickerPresented = false }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "textformat.size")
                        Text("\(Int(snappedFontSize)) pt")
                            .lineLimit(1)
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .popover(
                    isPresented: $isSizePickerPresented,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .top
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(popularFontSizes, id: \.self) { size in
                            Button(action: {
                                node.fontSize = size
                                isSizePickerPresented = false
                            }) {
                                HStack {
                                    if size == snappedFontSize {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.primary)
                                    } else {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .medium))
                                            .opacity(0)
                                    }
                                    Text("\(Int(size)) pt")
                                        .font(.system(size: 11))
                                        .foregroundColor(.primary)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
                    )
                }
            }

            Button(action: { showColorPicker = true }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(currentColor)
                        .frame(width: 16, height: 16)
                    Text("Color")
                        .font(.caption)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .popover(isPresented: $showColorPicker) {
                ColorPickerPopover(selectedColorId: node.color) { id in
                    node.color = id
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
    }
    
    private let popularFontSizes: [CGFloat] = [12, 14, 16, 18, 24, 32, 48, 64, 80, 96]
    
    private var snappedFontSize: CGFloat {
        let sizes = popularFontSizes.sorted()
        guard let first = sizes.first else { return node.fontSize }
        var best = first
        var smallestDifference = abs(first - node.fontSize)
        for size in sizes {
            let diff = abs(size - node.fontSize)
            if diff < smallestDifference {
                smallestDifference = diff
                best = size
            }
        }
        return best
    }
    
    private var currentFontDisplayName: String {
        guard let family = node.fontFamily?.lowercased() else { return "Default" }
        switch family {
        case "serif": return "Serif"
        case "rounded": return "Rounded"
        case "mono", "monospace", "monospaced": return "Mono"
        case "handwriting-noteworthy": return "Handwriting - Neat"
        case "handwriting-marker": return "Handwriting - Marker"
        default: return "Default"
        }
    }
    
    private var fontOptions: [FontOption] {
        [
            FontOption(id: "default", label: "Default", value: nil),
            FontOption(id: "serif", label: "Serif", value: "serif"),
            FontOption(id: "rounded", label: "Rounded", value: "rounded"),
            FontOption(id: "mono", label: "Mono", value: "mono"),
            FontOption(id: "handwriting-noteworthy", label: "Handwriting - Neat", value: "handwriting-noteworthy"),
            FontOption(id: "handwriting-marker", label: "Handwriting - Marker", value: "handwriting-marker")
        ]
    }
    
    private struct FontOption: Identifiable {
        let id: String
        let label: String
        let value: String?
        
        func isSelected(currentFamily: String?) -> Bool {
            if value == nil {
                return currentFamily == nil
            }
            return currentFamily?.lowercased() == value?.lowercased()
        }
    }
    
    private var currentColor: Color {
        if let c = NodeColor.color(for: node.color) { return c.color }
        return Color.gray
    }
}

// Previews omitted
