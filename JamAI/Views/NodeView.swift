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
    let onColorChange: (String) -> Void
    let onExpandSelection: (String) -> Void
    let onMakeNote: (String) -> Void
    let onJamWithThis: (String) -> Void
    let onHeightChange: (CGFloat) -> Void
    let onResizeActiveChanged: (Bool) -> Void
    
    @State private var isEditingTitle = false
    @State private var isEditingDescription = false
    @State private var editedTitle = ""
    @State private var editedDescription = ""
    @State private var promptText = ""
    @State private var isResizing = false
    @State private var resizeStartHeight: CGFloat = 0
    @State private var showingColorPicker = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isPromptFocused: Bool
    @State private var scrollViewID = UUID()
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            if node.isExpanded {
                // Expanded content with fixed input at bottom
                VStack(spacing: 0) {
                    // Scrollable conversation area
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                // Description
                                descriptionView
                                
                                // Conversation thread
                                conversationView
                                    .id(scrollViewID)
                            }
                            .padding(Node.padding)
                        }
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                withAnimation {
                                    if let lastAssistantId = node.conversation.last(where: { $0.role == .assistant })?.id {
                                        proxy.scrollTo(lastAssistantId, anchor: .bottom)
                                    } else if let lastMessageId = node.conversation.last?.id {
                                        proxy.scrollTo(lastMessageId, anchor: .bottom)
                                    } else if !node.response.isEmpty {
                                        proxy.scrollTo("legacy-assistant", anchor: .bottom)
                                    } else if !node.prompt.isEmpty {
                                        proxy.scrollTo("legacy-user", anchor: .bottom)
                                    }
                                }
                            }
                        }
                        .onChange(of: node.conversation.count) { oldCount, newCount in
                            if newCount > oldCount {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    withAnimation {
                                        if let last = node.conversation.last {
                                            switch last.role {
                                            case .user:
                                                if let lastUserId = node.conversation.last(where: { $0.role == .user })?.id {
                                                    proxy.scrollTo(lastUserId, anchor: .top)
                                                } else {
                                                    proxy.scrollTo(scrollViewID, anchor: .top)
                                                }
                                            case .assistant:
                                                if let lastUserId = node.conversation.last(where: { $0.role == .user })?.id {
                                                    proxy.scrollTo(lastUserId, anchor: .top)
                                                } else if let lastAssistantId = node.conversation.last(where: { $0.role == .assistant })?.id {
                                                    proxy.scrollTo(lastAssistantId, anchor: .top)
                                                } else {
                                                    proxy.scrollTo(scrollViewID, anchor: .top)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .onChange(of: isGenerating) { oldValue, newValue in
                            if newValue {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    withAnimation {
                                        if let lastUserId = node.conversation.last(where: { $0.role == .user })?.id {
                                            proxy.scrollTo(lastUserId, anchor: .top)
                                        } else if node.conversation.isEmpty && !node.response.isEmpty {
                                            // Expansion streaming without a user bubble
                                            proxy.scrollTo("legacy-assistant", anchor: .top)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Input area - always visible at bottom
                    inputView
                        .padding(Node.padding)
                }
                .frame(height: node.height - 60)
                .overlay(
                    TapThroughOverlay(onTap: onTap)
                )
            } else {
                // Collapsed content
                collapsedContentView
                    .padding(Node.padding)
            }
            
            // Resize handle at bottom (only when expanded)
            if node.isExpanded {
                resizeHandle
            }
        }
        .frame(
            width: Node.nodeWidth,
            height: node.isExpanded ? node.height : Node.collapsedHeight
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
            if isSelected {
                isPromptFocused = true
                isEditingTitle = false
            }
        }
        .onChange(of: isSelected) { oldValue, newValue in
            if newValue {
                isPromptFocused = true
                isEditingTitle = false
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            // Drag handle icon
            Image(systemName: "line.3.horizontal")
                .foregroundColor(headerTextColor)
                .font(.system(size: 16))
                .help("Drag to move node")
            
            // Color button
            Button(action: { showingColorPicker = true }) {
                ZStack {
                    if let nodeColor = NodeColor.color(for: node.color), nodeColor.id == "rainbow" {
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
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .strokeBorder(headerTextColor, lineWidth: 1.5)
                            )
                    } else if let nodeColor = NodeColor.color(for: node.color) {
                        Circle()
                            .fill(nodeColor.color)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .strokeBorder(headerTextColor, lineWidth: 1.5)
                            )
                    } else {
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .strokeBorder(headerTextColor, lineWidth: 1.5)
                            )
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .help("Change Node Color")
            .popover(isPresented: $showingColorPicker) {
                ColorPickerPopover(selectedColorId: node.color) { newColorId in
                    onColorChange(newColorId)
                }
            }
            
            // Title
            if isEditingTitle {
                TextField("Title", text: $editedTitle, onCommit: {
                    onTitleEdit(editedTitle)
                    isEditingTitle = false
                })
                .textFieldStyle(PlainTextFieldStyle())
                .font(.headline)
                .foregroundColor(headerTextColor)
                .focused($isTitleFocused)
            } else {
                HStack(spacing: 8) {
                    Text(node.title.isEmpty ? "Untitled" : node.title)
                        .font(.headline)
                        .foregroundColor(node.title.isEmpty ? headerTextColor.opacity(0.6) : headerTextColor)
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
                    .foregroundColor(headerTextColor)
                    .font(.system(size: 16))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Delete Node")
            
            // Create child node button
            Button(action: onCreateChild) {
                Image(systemName: "plus.square.on.square")
                    .foregroundColor(headerTextColor)
                    .font(.system(size: 16))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Create Child Node")
            
            // Expand/Collapse button
            Button(action: {
                // Update immediately without animation for instant response
                var updatedNode = node
                updatedNode.isExpanded.toggle()
                node = updatedNode
            }) {
                Image(systemName: node.isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .foregroundColor(headerTextColor)
                    .font(.system(size: 16))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Toggle Expand/Collapse")
        }
        .padding(Node.padding)
        .background(headerBackground)
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
                        .id("legacy-user")
                }
                if !node.response.isEmpty {
                    messageView(role: .assistant, content: node.response)
                        .id("legacy-assistant")
                }
            } else {
                // Show conversation thread
                ForEach(node.conversation) { message in
                    messageView(role: message.role, content: message.content)
                        .id(message.id)
                }
            }
        }
    }
    
    private func messageView(role: MessageRole, content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(role == .user ? "You" : "Jam")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(role == .user ? .secondary : .accentColor)
            
            MarkdownText(text: content)
                .font(.body)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(role == .user ? Color.secondary.opacity(0.1) : Color.clear)
                .cornerRadius(8)
                .overlay(
                    RightClickExpandOverlay(onExpand: onExpandSelection, onMakeNote: onMakeNote, onJamWithThis: onJamWithThis)
                )
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
                    .focused($isPromptFocused)
                    .onSubmit {
                        submitPrompt()
                    }
                
                Button(action: {
                    submitPrompt()
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(promptText.isEmpty ? .secondary : .accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(promptText.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
    }
    
    // MARK: - Styling
    
    private var headerBackground: some View {
        if let nodeColor = NodeColor.color(for: node.color), node.color != "none" {
            return AnyView(nodeColor.color)
        } else {
            return AnyView(
                colorScheme == .dark
                    ? Color(nsColor: .controlBackgroundColor)
                    : Color(white: 0.95)
            )
        }
    }
    
    private var headerTextColor: Color {
        if let nodeColor = NodeColor.color(for: node.color), node.color != "none" {
            return nodeColor.textColor(for: nodeColor.color)
        } else {
            return .primary
        }
    }
    
    private var cardBackground: some View {
        if let nodeColor = NodeColor.color(for: node.color), node.color != "none" {
            // Apply subtle tint to card body (5% opacity of selected color)
            let tintColor = nodeColor.lightVariant.opacity(0.05)
            let baseColor = colorScheme == .dark
                ? Color(nsColor: .controlBackgroundColor)
                : Color.white
            
            return AnyView(
                ZStack {
                    baseColor
                    tintColor
                }
            )
        } else {
            return AnyView(
                colorScheme == .dark
                    ? Color(nsColor: .controlBackgroundColor)
                    : Color.white
            )
        }
    }
    
    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.5)
            : Color.black.opacity(0.15)
    }
    
    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 6)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray)
                    .frame(width: 40, height: 4)
            )
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isResizing {
                            isResizing = true
                            resizeStartHeight = node.height
                            onResizeActiveChanged(true)
                        }
                        let newHeight = max(Node.minHeight, min(Node.maxHeight, resizeStartHeight + value.translation.height))
                        var updatedNode = node
                        updatedNode.height = newHeight
                        node = updatedNode
                    }
                    .onEnded { _ in
                        isResizing = false
                        onHeightChange(node.height)
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
    
    // MARK: - Actions
    
    private func submitPrompt() {
        if !promptText.isEmpty {
            onPromptSubmit(promptText)
            promptText = ""
            isPromptFocused = true // Keep focus in input
        }
    }
}
