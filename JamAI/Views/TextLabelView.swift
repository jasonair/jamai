import SwiftUI

struct TextLabelView: View {
    @Binding var node: Node
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onDescriptionEdit: (String) -> Void
    let onHeightChange: (CGFloat) -> Void
    let onWidthChange: (CGFloat) -> Void
    let onResizeActiveChanged: (Bool) -> Void
    
    @State private var text: String = ""
    @State private var isEditing: Bool = false
    @State private var isResizing: Bool = false
    @State private var resizeStartHeight: CGFloat = 0
    @State private var resizeStartWidth: CGFloat = 0
    @FocusState private var isFocused: Bool
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Main text content
            textContent
                .frame(width: currentWidth, height: currentHeight, alignment: .topLeading)
            
            // Resize handle at bottom (only when selected)
            if isSelected {
                resizeHandle
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .onAppear { 
            text = node.description
            // Auto-start editing if text is empty (newly created)
            if node.description.isEmpty {
                isEditing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFocused = true
                }
            }
        }
        .onChange(of: node.description) { _, newValue in
            if !isEditing { text = newValue }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { isEditing = false }
        }
    }
    
    private var textContent: some View {
        HStack(spacing: 8) {
            if isEditing {
                TextField("Type here...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: node.fontSize, weight: node.isBold ? .bold : .regular, design: fontDesign))
                    .foregroundColor(.primary)
                    .focused($isFocused)
                    .lineLimit(nil)
                    .onChange(of: text) { _, newValue in
                        onDescriptionEdit(newValue)
                    }
                    .onSubmit {
                        isEditing = false
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text(node.description.isEmpty ? "Double-click to edit" : node.description)
                    .font(.system(size: node.fontSize, weight: node.isBold ? .bold : .regular, design: fontDesign))
                    .foregroundColor(node.description.isEmpty ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        isEditing = true
                        isFocused = true
                    }
                    .onTapGesture(count: 1) {
                        if !isEditing {
                            onTap()
                        }
                    }
            }
            if isSelected && !isEditing {
                VStack {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(PlainButtonStyle())
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 6)
            .frame(maxWidth: .infinity)
            .overlay(
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray)
                        .frame(width: 30, height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray)
                        .frame(width: 3, height: 3)
                }
            )
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isResizing {
                            isResizing = true
                            resizeStartHeight = node.height
                            resizeStartWidth = node.width ?? 250
                            onResizeActiveChanged(true)
                        }
                        
                        // Resize both width and height based on drag direction
                        let newHeight = max(60, min(600, resizeStartHeight + value.translation.height))
                        let newWidth = max(150, min(600, resizeStartWidth + value.translation.width))
                        
                        var updatedNode = node
                        updatedNode.height = newHeight
                        updatedNode.width = newWidth
                        node = updatedNode
                    }
                    .onEnded { _ in
                        isResizing = false
                        onHeightChange(node.height)
                        onWidthChange(node.width ?? 250)
                        onResizeActiveChanged(false)
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
    
    private var currentHeight: CGFloat {
        max(60, node.height)
    }
    
    private var currentWidth: CGFloat {
        node.width ?? 250
    }

    private var fontDesign: Font.Design {
        switch node.fontFamily?.lowercased() {
        case "serif": return .serif
        case "mono", "monospace", "monospaced": return .monospaced
        default: return .default
        }
    }
}

// Previews omitted to avoid duplication in build
