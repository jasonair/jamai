import SwiftUI

struct ToolDockView: View {
    @Binding var selectedTool: CanvasTool
    
    var body: some View {
        HStack(spacing: 8) {
            toolButton(image: "cursorarrow", tool: .select, hint: "Select (V)")
            toolButton(image: "textformat", tool: .text, hint: "Text (T)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
    }
    
    @ViewBuilder
    private func toolButton(image: String, tool: CanvasTool, hint: String) -> some View {
        Button(action: { selectedTool = tool }) {
            Image(systemName: image)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(selectedTool == tool ? .accentColor : .primary)
                .frame(width: 32, height: 28)
                .background(selectedTool == tool ? Color.accentColor.opacity(0.15) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .help(hint)
    }
}

// Previews omitted to avoid duplication in build
