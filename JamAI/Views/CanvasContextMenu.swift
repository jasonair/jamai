import SwiftUI

struct CanvasContextMenu: View {
    let onCreateChat: () -> Void
    let onCreateNote: () -> Void
    let onCreateTitle: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 8) {
            contextButton(
                systemImage: "bubble.left.and.bubble.right",
                action: onCreateChat
            )
            .help("New Chat Here")
            
            contextButton(
                systemImage: "note.text",
                action: onCreateNote
            )
            .help("New Note Here")
            
            contextButton(
                systemImage: "textformat.size",
                action: onCreateTitle
            )
            .help("New Title Here")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
    }
    
    private func contextButton(
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        MenuItemButton(
            systemImage: systemImage,
            accent: accent,
            action: action
        )
    }
    
    private var accent: Color { Color.primary }
}

private struct MenuItemButton: View {
    let systemImage: String
    let accent: Color
    let action: () -> Void
    
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: isHovering ? .medium : .regular))
                .foregroundColor(accent)
                .frame(width: 28, height: 28)
                .background(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}
