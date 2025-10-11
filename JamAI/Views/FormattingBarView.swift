import SwiftUI

struct FormattingBarView: View {
    @Binding var node: Node
    @State private var showColorPicker = false
    
    var body: some View {
        HStack(spacing: 12) {
            if node.type == .text {
                Button(action: { node.isBold.toggle() }) {
                    Image(systemName: node.isBold ? "bold" : "bold")
                        .foregroundColor(node.isBold ? .accentColor : .primary)
                }
                .buttonStyle(PlainButtonStyle())
                
                HStack(spacing: 6) {
                    Button(action: { adjustFontSize(-2) }) { Image(systemName: "textformat.size.smaller") }
                        .buttonStyle(PlainButtonStyle())
                    Text("\(Int(node.fontSize))")
                        .font(.caption)
                        .frame(width: 34)
                    Button(action: { adjustFontSize(2) }) { Image(systemName: "textformat.size.larger") }
                        .buttonStyle(PlainButtonStyle())
                }
                
                Picker("Font", selection: Binding<String>(
                    get: { node.fontFamily ?? "Default" },
                    set: { node.fontFamily = $0 == "Default" ? nil : $0 }
                )) {
                    Text("Default").tag("Default")
                    Text("Serif").tag("Serif")
                    Text("Mono").tag("Mono")
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
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
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
    }
    
    private func adjustFontSize(_ delta: CGFloat) {
        node.fontSize = max(8, min(96, node.fontSize + delta))
    }
    
    private var currentColor: Color {
        if let c = NodeColor.color(for: node.color) { return c.color }
        return Color.gray
    }
}

// Previews omitted
