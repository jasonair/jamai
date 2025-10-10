//
//  NodeView.swift
//  JamAI
//
//  Individual node card view
//

import SwiftUI

struct NodeView: View {
    @Binding var node: Node
    let isSelected: Bool
    let isGenerating: Bool
    let onTap: () -> Void
    let onPromptSubmit: (String) -> Void
    let onTitleEdit: (String) -> Void
    let onDescriptionEdit: (String) -> Void
    let onDelete: () -> Void
    let onCreateChild: () -> Void
    
    @State private var isEditingTitle = false
    @State private var isEditingDescription = false
    @State private var editedTitle = ""
    @State private var editedDescription = ""
    @State private var promptText = ""
    @FocusState private var isTitleFocused: Bool
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerView
                .padding(Node.padding)
            
            Divider()
            
            if node.isExpanded {
                // Expanded content
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Description
                        descriptionView
                        
                        // Conversation thread
                        conversationView
                        
                        // Input area
                        inputView
                    }
                    .padding(Node.padding)
                }
                .frame(height: Node.expandedHeight - 60)
            } else {
                // Collapsed content
                collapsedContentView
                    .padding(Node.padding)
            }
        }
        .frame(
            width: Node.nodeWidth,
            height: node.isExpanded ? Node.expandedHeight : Node.collapsedHeight
        )
        .background(cardBackground)
        .cornerRadius(Node.cornerRadius)
        .shadow(
            color: shadowColor,
            radius: Node.shadowRadius,
            x: 0,
            y: 4
        )
        .overlay(
            RoundedRectangle(cornerRadius: Node.cornerRadius)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onTapGesture {
            onTap()
        }
        .onAppear {
            // Auto-focus title for new empty nodes
            if node.title.isEmpty && isSelected {
                editedTitle = node.title
                isEditingTitle = true
                isTitleFocused = true
            }
        }
        .onChange(of: isSelected) { newValue in
            // Auto-focus title when selecting an empty node
            if newValue && node.title.isEmpty {
                editedTitle = node.title
                isEditingTitle = true
                isTitleFocused = true
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            // Title
            if isEditingTitle {
                TextField("Title", text: $editedTitle, onCommit: {
                    onTitleEdit(editedTitle)
                    isEditingTitle = false
                })
                .textFieldStyle(PlainTextFieldStyle())
                .font(.headline)
                .focused($isTitleFocused)
            } else {
                HStack(spacing: 8) {
                    Text(node.title.isEmpty ? "Untitled" : node.title)
                        .font(.headline)
                        .foregroundColor(node.title.isEmpty ? .secondary : .primary)
                        .onTapGesture {
                            editedTitle = node.title
                            isEditingTitle = true
                            isTitleFocused = true
                        }
                    
                    if isGenerating {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    }
                }
            }
            
            Spacer()
            
            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Delete Node")
            
            // Create child node button
            Button(action: onCreateChild) {
                Image(systemName: "plus.square.on.square")
                    .foregroundColor(.green)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Create Child Node")
            
            // Expand/Collapse button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    var updatedNode = node
                    updatedNode.isExpanded.toggle()
                    node = updatedNode
                }
            }) {
                Image(systemName: node.isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Toggle Expand/Collapse")
        }
    }
    
    private var descriptionView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isEditingDescription {
                TextField("Description", text: $editedDescription, onCommit: {
                    onDescriptionEdit(editedDescription)
                    isEditingDescription = false
                })
                .textFieldStyle(PlainTextFieldStyle())
                .font(.caption)
            } else {
                Text(node.description.isEmpty ? "No description" : node.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(node.isExpanded ? nil : 2)
                    .onTapGesture {
                        if node.isExpanded {
                            editedDescription = node.description
                            isEditingDescription = true
                        }
                    }
            }
        }
    }
    
    private var collapsedContentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            descriptionView
            
            // Show last message from conversation or legacy prompt/response
            if let lastMessage = node.conversation.last {
                Text(lastMessage.content)
                    .font(.body)
                    .lineLimit(3)
                    .foregroundColor(.primary)
            } else if !node.prompt.isEmpty || !node.response.isEmpty {
                Text(node.response.isEmpty ? node.prompt : node.response)
                    .font(.body)
                    .lineLimit(3)
                    .foregroundColor(.primary)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
    
    private var conversationView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if node.conversation.isEmpty {
                // Show legacy prompt/response for backwards compatibility
                if !node.prompt.isEmpty {
                    messageView(role: .user, content: node.prompt)
                }
                if !node.response.isEmpty {
                    messageView(role: .assistant, content: node.response)
                }
            } else {
                // Show conversation thread
                ForEach(node.conversation) { message in
                    messageView(role: message.role, content: message.content)
                }
            }
        }
    }
    
    private func messageView(role: MessageRole, content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(role == .user ? "You" : "AI")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(role == .user ? .secondary : .accentColor)
            
            MarkdownText(text: content)
                .font(.body)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
        }
    }
    
    private var inputView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Prompt")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask a question...", text: $promptText, axis: .vertical)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .lineLimit(3...6)
                
                Button(action: {
                    if !promptText.isEmpty {
                        onPromptSubmit(promptText)
                        promptText = ""
                    }
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(promptText.isEmpty ? .secondary : .accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(promptText.isEmpty)
            }
        }
    }
    
    // MARK: - Styling
    
    private var cardBackground: some View {
        colorScheme == .dark
            ? Color(nsColor: .controlBackgroundColor)
            : Color.white
    }
    
    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.5)
            : Color.black.opacity(0.15)
    }
}
