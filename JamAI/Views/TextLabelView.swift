import SwiftUI

struct TextLabelView: View {
    @Binding var node: Node
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onDescriptionEdit: (String) -> Void
    
    @State private var text: String = ""
    @State private var isEditing: Bool = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            if isEditing {
                TextField("Type here...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: node.fontSize, weight: node.isBold ? .bold : .regular, design: fontDesign))
                    .foregroundColor(.primary)
                    .focused($isFocused)
                    .lineLimit(1...10)
                    .onChange(of: text) { _, newValue in
                        onDescriptionEdit(newValue)
                    }
                    .onSubmit {
                        isEditing = false
                    }
            } else {
                Text(node.description.isEmpty ? "Double-click to edit" : node.description)
                    .font(.system(size: node.fontSize, weight: node.isBold ? .bold : .regular, design: fontDesign))
                    .foregroundColor(node.description.isEmpty ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: false)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .frame(minWidth: 50, maxWidth: 400, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        isEditing = true
                        isFocused = true
                    }
            }
            if isSelected && !isEditing {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
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
        .onTapGesture { 
            if !isEditing {
                onTap() 
            }
        }
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
