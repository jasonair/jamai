//
//  NodeView.swift
//  JamAI
//
//  Individual node card view
//

import SwiftUI
import UniformTypeIdentifiers

struct NodeView: View {
    @Binding var node: Node
    let isSelected: Bool
    let isGenerating: Bool
    let onTap: () -> Void
    let onPromptSubmit: (String, Data?, String?) -> Void
    let onTitleEdit: (String) -> Void
    let onDescriptionEdit: (String) -> Void
    let onDelete: () -> Void
    let onCreateChild: () -> Void
    let onColorChange: (String) -> Void
    let onExpandSelection: (String) -> Void
    let onMakeNote: (String) -> Void
    let onJamWithThis: (String) -> Void
    let onHeightChange: (CGFloat) -> Void
    let onWidthChange: (CGFloat) -> Void
    let onResizeActiveChanged: (Bool) -> Void
    
    @State private var isEditingTitle = false
    @State private var isEditingDescription = false
    @State private var editedTitle = ""
    @State private var editedDescription = ""
    @State private var promptText = ""
    @State private var isResizing = false
    @State private var resizeStartHeight: CGFloat = 0
    @State private var resizeStartWidth: CGFloat = 0
    @State private var draggedHeight: CGFloat = 0
    @State private var draggedWidth: CGFloat = 0
    @State private var dragStartLocation: CGPoint = .zero
    @State private var showingColorPicker = false
    @State private var showChatSection = false
    @State private var selectedImage: NSImage?
    @State private var selectedImageData: Data?
    @State private var selectedImageMimeType: String?
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isPromptFocused: Bool
    @FocusState private var isDescFocused: Bool
    @State private var scrollViewID = UUID()
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                headerView
                
                Divider()
                
                if node.isExpanded {
                // Expanded content with fixed input at bottom
                VStack(spacing: 0) {
                    // Content area - different layout for notes vs standard nodes
                    if node.type == .note {
                        // For notes: Handle both note view and conversation view
                        if showChatSection {
                            // When chat is visible, use ScrollView for conversation
                            ScrollViewReader { proxy in
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 12) {
                                        // Note description (read-only when chat is visible)
                                        if !node.description.isEmpty {
                                            Text(node.description)
                                                .font(.system(size: 15))
                                                .padding(Node.padding)
                                        }
                                        
                                        // Conversation thread
                                        conversationView
                                            .padding(.horizontal, Node.padding)
                                            .id(scrollViewID)
                                    }
                                    .padding(.bottom, Node.padding)
                                }
                                .onChange(of: node.conversation.count) { oldCount, newCount in
                                    if newCount > oldCount {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                            withAnimation {
                                                if let last = node.conversation.last {
                                                    proxy.scrollTo(last.id, anchor: .bottom)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        } else {
                            // When chat is hidden, show note content
                            // Single TextEditor handles both reading and editing
                            noteDescriptionView
                                .padding(Node.padding)
                        }
                    } else {
                        // For standard nodes: ScrollView with conversation
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
                    }
                    
                    // Only show divider and input if not a note OR if chat section is visible
                    if node.type != .note || showChatSection {
                        Divider()
                        
                        // Input area - always visible at bottom
                        inputView
                            .padding(Node.padding)
                    }
                }
                .frame(height: (isResizing ? draggedHeight : node.height) - 60)
                .overlay(
                    TapThroughOverlay(onTap: onTap)
                )
            } else {
                // Collapsed content
                collapsedContentView
                    .padding(Node.padding)
            }
            }
            .frame(
                width: isResizing ? draggedWidth : node.width,
                height: node.isExpanded ? (isResizing ? draggedHeight : node.height) : Node.collapsedHeight
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
            .overlay(
                RightClickExpandOverlay(
                    onExpand: onExpandSelection,
                    onMakeNote: onMakeNote,
                    onJamWithThis: onJamWithThis
                )
            )
            
            // Resize grip overlay - positioned absolutely in corner (only when expanded)
            if node.isExpanded {
                resizeGripOverlay
            }
        }
        .onAppear {
            if isSelected {
                // Only focus prompt for non-note nodes or when chat section is visible
                if node.type != .note || showChatSection {
                    isPromptFocused = true
                }
                isEditingTitle = false
            }
        }
        .onChange(of: isSelected) { oldValue, newValue in
            if newValue {
                // Only focus prompt for non-note nodes or when chat section is visible
                // Notes can be scrolled and clicked to focus without auto-focusing
                if node.type != .note || showChatSection {
                    isPromptFocused = true
                }
                isEditingTitle = false
            } else {
                // When deselected, clear all focus states
                // Content is already auto-saved, just clear focus
                isDescFocused = false
                isPromptFocused = false
                isTitleFocused = false
                isEditingTitle = false
                isEditingDescription = false
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            // Drag handle icon
            Image(systemName: node.type == .note ? "note.text" : "line.3.horizontal")
                .foregroundColor(headerTextColor)
                .font(.system(size: 16))
                .help(node.type == .note ? "Note" : "Drag to move node")
            
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
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(headerTextColor)
                .focused($isTitleFocused)
            } else {
                HStack(spacing: 8) {
                    Text(node.title.isEmpty ? "Untitled" : node.title)
                        .font(.system(size: 18, weight: .semibold))
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
            
            // JAM button (for notes only)
            if node.type == .note {
                Button(action: {
                    showChatSection.toggle()
                    if showChatSection {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isPromptFocused = true
                        }
                    }
                }) {
                    Image(systemName: "bubble.left.fill")
                        .foregroundColor(headerTextColor)
                        .font(.system(size: 16))
                }
                .buttonStyle(PlainButtonStyle())
                .help(showChatSection ? "Hide chat" : "Jam with this note")
            }
            
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
                .font(.system(size: 15))
            } else {
                Text(node.description.isEmpty ? "No description" : node.description)
                    .font(.system(size: 15))
                    .foregroundColor(node.description.isEmpty ? .secondary : .primary)
                    .onTapGesture {
                        if node.isExpanded {
                            editedDescription = node.description
                            isEditingDescription = true
                        }
                    }
            }
        }
    }
    
    private var noteDescriptionView: some View {
        // Simple TextEditor that handles both reading and editing
        ZStack(alignment: .topLeading) {
            // Placeholder when empty
            if editedDescription.isEmpty {
                Text("Click to start typing...")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            
            // TextEditor - always present, scrolls naturally
            // Uses local state to avoid update loops
            TextEditor(text: $editedDescription)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($isDescFocused)
        }
        .onAppear {
            // Sync local state with node on appear
            if editedDescription != node.description {
                editedDescription = node.description
            }
        }
        .onChange(of: isDescFocused) { _, isFocused in
            if isFocused {
                // Entering edit mode - sync state
                if editedDescription != node.description {
                    editedDescription = node.description
                }
            } else {
                // Exiting edit mode - save if changed
                if editedDescription != node.description {
                    onDescriptionEdit(editedDescription)
                }
            }
        }
    }
    
    private var collapsedContentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            descriptionView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        // Find the corresponding conversation message to check for images
        let conversationMsg = node.conversation.first(where: { msg in
            msg.role == role && msg.content == content
        })
        
        return VStack(alignment: .leading, spacing: 4) {
            Text(role == .user ? "You" : "Jam")
                .font(.system(size: 12, weight: .semibold))
                .fontWeight(.semibold)
                .foregroundColor(role == .user ? .secondary : .accentColor)
            
            VStack(alignment: .leading, spacing: 8) {
                // Show image if present
                if let imageData = conversationMsg?.imageData,
                   let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 200, maxHeight: 200)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
                
                // Show text content
                if !content.isEmpty {
                    MarkdownText(text: content, onCopy: role == .assistant ? { text in
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    } : nil)
                        .font(.system(size: 15))
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(role == .user ? Color.secondary.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
    }
    
    private var inputView: some View {
        VStack(spacing: 8) {
            // Image preview if selected (smaller thumbnail)
            if let image = selectedImage {
                HStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 60, maxHeight: 60)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    
                    Spacer()
                    
                    Button(action: {
                        selectedImage = nil
                        selectedImageData = nil
                        selectedImageMimeType = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Remove image")
                }
                .padding(6)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Input field with buttons in bottom corners
            ZStack(alignment: .bottomLeading) {
                // Text field with full area - minimal bottom padding
                TextField("Ask a question...", text: $promptText, axis: .vertical)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 24) // Just enough for button row
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .lineLimit(3...6)
                    .focused($isPromptFocused)
                    .onSubmit {
                        submitPrompt()
                    }
                
                // Button row at bottom - tight to bottom edge
                HStack {
                    // Image upload button (bottom left)
                    Button(action: selectImage) {
                        Image(systemName: selectedImage == nil ? "photo" : "photo.fill")
                            .font(.system(size: 19))
                            .foregroundColor(selectedImage == nil ? .secondary : .accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Upload image")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    
                    Spacer()
                    
                    // Send button (bottom right)
                    Button(action: {
                        submitPrompt()
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor((promptText.isEmpty && selectedImage == nil) ? .secondary : .accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(promptText.isEmpty && selectedImage == nil)
                    .keyboardShortcut(.return, modifiers: [])
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
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
            // Apply tint to card body; stronger tint for notes to stand out
            if node.type == .note {
                // Notes get more visible color treatment
                let tintOpacity: Double = colorScheme == .dark ? 0.25 : 0.50
                let tintColor = colorScheme == .dark
                    ? nodeColor.color.opacity(tintOpacity)
                    : nodeColor.lightVariant.opacity(tintOpacity)
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
                // Standard nodes get subtle tint
                let tintOpacity: Double = 0.05
                let tintColor = nodeColor.lightVariant.opacity(tintOpacity)
                let baseColor = colorScheme == .dark
                    ? Color(nsColor: .controlBackgroundColor)
                    : Color.white
                
                return AnyView(
                    ZStack {
                        baseColor
                        tintColor
                    }
                )
            }
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
    
    private var resizeGripOverlay: some View {
        // macOS-style resize grip - absolutely positioned in bottom right corner
        ResizeGripView()
            .frame(width: 16, height: 16)
            .padding(.trailing, 8)
            .padding(.bottom, 8)
            .contentShape(Rectangle().size(width: 40, height: 40))
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if !isResizing {
                            isResizing = true
                            resizeStartHeight = node.height
                            resizeStartWidth = node.width
                            draggedHeight = node.height
                            draggedWidth = node.width
                            dragStartLocation = value.location
                            onResizeActiveChanged(true)
                        }
                        // Calculate delta from initial drag position (prevents drift)
                        let deltaX = value.location.x - dragStartLocation.x
                        let deltaY = value.location.y - dragStartLocation.y
                        
                        // Update local state only - smooth without triggering binding updates
                        let minWidth = node.type == .note ? Node.minNoteWidth : Node.minWidth
                        draggedHeight = max(Node.minHeight, min(Node.maxHeight, resizeStartHeight + deltaY))
                        draggedWidth = max(minWidth, min(Node.maxWidth, resizeStartWidth + deltaX))
                    }
                    .onEnded { _ in
                        isResizing = false
                        // Only update the binding once at the end
                        onHeightChange(draggedHeight)
                        onWidthChange(draggedWidth)
                        onResizeActiveChanged(false)
                    }
            )
    }
    
    // MARK: - Actions
    
    private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.message = "Select an image to send"
        
        if panel.runModal() == .OK, let url = panel.url {
            if let image = NSImage(contentsOf: url) {
                // Process the image
                if let processed = ImageHelper.processImage(image) {
                    selectedImage = image
                    selectedImageData = processed.data
                    selectedImageMimeType = processed.mimeType
                } else {
                    // Show error - image too large or processing failed
                    print("Failed to process image")
                }
            }
        }
    }
    
    private func submitPrompt() {
        // Allow sending with just an image or just text or both
        if !promptText.isEmpty || selectedImage != nil {
            let textToSend = promptText.isEmpty ? "" : promptText
            onPromptSubmit(textToSend, selectedImageData, selectedImageMimeType)
            promptText = ""
            selectedImage = nil
            selectedImageData = nil
            selectedImageMimeType = nil
            isPromptFocused = true // Keep focus in input
        }
    }
}
