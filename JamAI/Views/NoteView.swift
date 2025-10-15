import SwiftUI

struct NoteView: View {
    @Binding var node: Node
    let isSelected: Bool
    let onDelete: () -> Void
    let onExpandNote: () -> Void
    let onDescriptionEdit: (String) -> Void
    let onTap: () -> Void
    let onResizeActiveChanged: (Bool) -> Void

    @Environment(\.colorScheme) var colorScheme
    @State private var text: String = ""
    @FocusState private var isTextFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Drag handle icon
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.black.opacity(0.4))
                    .font(.system(size: 14))
                    .help("Drag to move note")
                
                Text(node.title.isEmpty ? "Note" : node.title)
                    .font(.headline)
                    .foregroundColor(.black.opacity(0.9))
                Spacer()
                Button(action: onExpandNote) {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundColor(.black.opacity(0.8))
                }
                .buttonStyle(PlainButtonStyle())
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.9))
                }
                .buttonStyle(PlainButtonStyle())
            }

            TextEditor(text: $text)
                .font(.body)
                .foregroundColor(.black)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .onChange(of: text) { _, newValue in
                    onDescriptionEdit(newValue)
                }
                .focused($isTextFocused)
                .onChange(of: isTextFocused) { _, newValue in
                    onResizeActiveChanged(newValue)
                }
                .overlay(
                    TapThroughOverlay(onTap: onTap, shouldFocusOnTap: false)
                )
        }
        .padding(12)
        .frame(width: Node.width(for: node.type), height: node.isExpanded ? node.height : Node.collapsedHeight, alignment: .topLeading)
        .background(stickyBackground)
        .cornerRadius(Node.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Node.cornerRadius)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.2), radius: 6, x: 0, y: 3)
        .onAppear {
            text = node.description
            // Focus editor on appear to prevent wrapper drag during initial mouse movement
            isTextFocused = true
            onResizeActiveChanged(true)
        }
        .onTapGesture { onTap() }
    }

    private var stickyBackground: some View {
        let base = NodeColor.color(for: "lightYellow")?.lightVariant ?? Color.yellow.opacity(0.6)
        let tint = NodeColor.color(for: "yellow")?.color.opacity(0.08) ?? Color.yellow.opacity(0.08)
        return AnyView(ZStack { base; tint })
    }
}
