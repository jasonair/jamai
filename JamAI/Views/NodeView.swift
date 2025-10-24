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
    let projectTeamMembers: [(nodeName: String, teamMember: TeamMember, role: Role?)]
    let onTap: () -> Void
    let onPromptSubmit: (String, Data?, String?, Bool) -> Void
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
    let onMaximizeAndCenter: () -> Void
    let onTeamMemberChange: (TeamMember?) -> Void
    
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
    @State private var webSearchEnabled = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isPromptFocused: Bool
    @FocusState private var isDescFocused: Bool
    @State private var scrollViewID = UUID()
    @State private var hasInitiallyLoaded = false
    @State private var processingMessageIndex = 0
    @State private var processingOpacity: Double = 1.0
    @State private var processingTimer: Timer?
    
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject private var modalCoordinator: ModalCoordinator
    @StateObject private var roleManager = RoleManager.shared
    @StateObject private var dataService = FirebaseDataService.shared
    @StateObject private var recordingService = AudioRecordingService()
    
    var body: some View {
        // Special handling for image nodes - no chrome, just the image
        if node.type == .image {
            return AnyView(imageNodeView)
        }
        
        return AnyView(
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                headerView
                
                Divider()
                
                // Team Member Tray (only for non-note nodes or notes with chat enabled)
                if shouldShowTeamMemberTray {
                    if let teamMember = node.teamMember {
                        TeamMemberTray(
                            teamMember: teamMember,
                            role: roleManager.role(withId: teamMember.roleId),
                            onSettings: { 
                                // Clear SwiftUI focus states
                                isTitleFocused = false
                                isPromptFocused = false
                                isDescFocused = false
                                
                                // Show modal - sheet detection will handle scroll
                                modalCoordinator.showTeamMemberModal(
                                    existingMember: node.teamMember,
                                    projectTeamMembers: projectTeamMembers,
                                    onSave: { newMember in
                                    onTeamMemberChange(newMember)
                                    
                                    // Track analytics for team member addition/change
                                    if let role = roleManager.role(withId: newMember.roleId), let userId = dataService.userAccount?.id {
                                        Task {
                                            await AnalyticsService.shared.trackTeamMemberUsage(
                                                userId: userId,
                                                projectId: node.projectId,
                                                nodeId: node.id,
                                                roleId: role.id,
                                                roleName: role.name,
                                                roleCategory: role.category.rawValue,
                                                experienceLevel: newMember.experienceLevel.rawValue,
                                                actionType: .attached // Or .changed if we distinguish
                                            )
                                        }
                                    }
                                },
                                    onRemove: { 
                                    let oldMember = node.teamMember // Capture before it's nil
                                    onTeamMemberChange(nil)

                                    // Track analytics for team member removal
                                    if let member = oldMember, let role = roleManager.role(withId: member.roleId), let userId = dataService.userAccount?.id {
                                        Task {
                                            await AnalyticsService.shared.trackTeamMemberUsage(
                                                userId: userId,
                                                projectId: node.projectId,
                                                nodeId: node.id,
                                                roleId: role.id,
                                                roleName: role.name,
                                                roleCategory: role.category.rawValue,
                                                experienceLevel: member.experienceLevel.rawValue,
                                                actionType: .removed
                                            )
                                        }
                                    }
                                }
                                )
                            }
                        )
                        
                        Divider()
                    }
                }
                
                // Content with fixed input at bottom
                VStack(spacing: 0) {
                    // Content area - different layout for notes vs standard nodes
                    // Use flexible frame to account for team member tray height
                    Group {
                    if node.type == .note {
                        // For notes: Handle both note view and conversation view
                        if showChatSection {
                            // When chat is visible, use ScrollView for conversation
                            ScrollViewReader { proxy in
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 12) {
                                        // Note description (read-only when chat is visible)
                                        if !node.description.isEmpty {
                                            HStack {
                                                Spacer(minLength: 0)
                                                Text(node.description)
                                                    .font(.system(size: 15))
                                                    .frame(maxWidth: 700)
                                                Spacer(minLength: 0)
                                            }
                                        }
                                        
                                        // Conversation thread - no width constraint, let MarkdownText handle it
                                        conversationView
                                            .id(scrollViewID)
                                    }
                                    .padding(Node.padding)
                                }
                                .disabled(!isSelected)
                                .onAppear {
                                    // Only auto-scroll on initial load to prevent scroll spam
                                    if !hasInitiallyLoaded {
                                        hasInitiallyLoaded = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            if let last = node.conversation.last {
                                                proxy.scrollTo(last.id, anchor: .bottom)
                                            }
                                        }
                                    }
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
                                    // Description - centered
                                    HStack {
                                        Spacer(minLength: 0)
                                        descriptionView
                                            .frame(maxWidth: 700)
                                        Spacer(minLength: 0)
                                    }
                                    
                                    // Conversation thread - no width constraint, let MarkdownText handle it
                                    conversationView
                                        .id(scrollViewID)
                                }
                                .padding(Node.padding)
                            }
                            .disabled(!isSelected)
                            .onAppear {
                                // Only auto-scroll on initial load to prevent scroll spam
                                if !hasInitiallyLoaded {
                                    hasInitiallyLoaded = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
                    }
                    .frame(maxHeight: .infinity) // Let content fill available space
                    
                    // Only show divider and input if not a note OR if chat section is visible
                    if node.type != .note || showChatSection {
                        Divider()
                        
                        // Input area - always visible at bottom
                        inputView
                            .padding(Node.padding)
                    }
                }
                .frame(height: (isResizing ? draggedHeight : node.height) - headerHeight)
                .overlay(
                    TapThroughOverlay(onTap: onTap)
                )
            }
            .frame(
                width: isResizing ? draggedWidth : node.width,
                height: isResizing ? draggedHeight : node.height
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
                // Block node selection if modal sheet is open
                guard NSApp.mainWindow?.sheets.isEmpty ?? true else { return }
                onTap()
            }
            .overlay(
                RightClickExpandOverlay(
                    onExpand: onExpandSelection,
                    onMakeNote: onMakeNote,
                    onJamWithThis: onJamWithThis
                )
            )
            
            // Resize grip overlay - positioned absolutely in corner
            resizeGripOverlay
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
                // Scroll detection now uses ViewModel's selectedNodeId - no first responder needed
            }
        }
        .allowsHitTesting(!modalCoordinator.isModalPresented) // Disable all interaction when modal is open
        )
    }
    
    // MARK: - Computed Properties
    
    private var imageNodeView: some View {
        let displayWidth = draggedWidth > 0 ? draggedWidth : node.width
        let displayHeight = draggedHeight > 0 ? draggedHeight : node.height
        
        return ZStack(alignment: .topLeading) {  // Changed to topLeading for proper anchor
            // Display the image
            if let imageData = node.imageData, let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)  // Changed to .fit to maintain aspect ratio properly
                    .frame(width: displayWidth, height: displayHeight, alignment: .topLeading)
                    .clipped()
                    .overlay(
                        // Selection border
                        Rectangle()
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: isSelected ? 2 : 0)
                    )
                    .onTapGesture {
                        onTap()
                    }
                    // Performance: Use faster interpolation during resize
                    .drawingGroup(opaque: false, colorMode: .nonLinear)
            } else {
                // Fallback if image data is missing
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: displayWidth, height: displayHeight)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                    )
            }
            
            // Resize grip (only visible when selected) - positioned at bottom right
            if isSelected {
                ResizeGripView()
                    .position(x: displayWidth - 8, y: displayHeight - 8)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isResizing {
                                    isResizing = true
                                    resizeStartHeight = node.height
                                    resizeStartWidth = node.width
                                    dragStartLocation = value.startLocation
                                    draggedHeight = node.height
                                    draggedWidth = node.width
                                    onResizeActiveChanged(true)
                                }
                                
                                let deltaX = value.location.x - dragStartLocation.x
                                let deltaY = value.location.y - dragStartLocation.y
                                
                                // Calculate aspect ratio from original dimensions
                                let aspectRatio = resizeStartWidth / resizeStartHeight
                                
                                // Determine which dimension changed more (driver dimension)
                                let xChange = abs(deltaX)
                                let yChange = abs(deltaY)
                                
                                if xChange > yChange {
                                    // Width is driver - calculate height from width
                                    let newWidth = max(50, resizeStartWidth + deltaX)
                                    let newHeight = newWidth / aspectRatio
                                    draggedWidth = newWidth
                                    draggedHeight = max(50, newHeight)
                                } else {
                                    // Height is driver - calculate width from height
                                    let newHeight = max(50, resizeStartHeight + deltaY)
                                    let newWidth = newHeight * aspectRatio
                                    draggedHeight = newHeight
                                    draggedWidth = max(50, newWidth)
                                }
                            }
                            .onEnded { value in
                                if isResizing {
                                    // Calculate how much size changed
                                    let widthDelta = draggedWidth - resizeStartWidth
                                    let heightDelta = draggedHeight - resizeStartHeight
                                    
                                    // Adjust position to keep top-left corner fixed
                                    // Since nodes are positioned by center, we need to shift by half the delta
                                    let newX = node.x + widthDelta / 2
                                    let newY = node.y + heightDelta / 2
                                    
                                    print("🔧 [Resize] Old: (\(node.x), \(node.y), \(resizeStartWidth)x\(resizeStartHeight))")
                                    print("🔧 [Resize] New: (\(newX), \(newY), \(draggedWidth)x\(draggedHeight))")
                                    print("🔧 [Resize] Delta: width=\(widthDelta), height=\(heightDelta), pos shift=(\(widthDelta/2), \(heightDelta/2))")
                                    
                                    // Create updated node with new position and size
                                    var updatedNode = node
                                    updatedNode.x = newX
                                    updatedNode.y = newY
                                    updatedNode.width = draggedWidth
                                    updatedNode.height = draggedHeight
                                    
                                    // Update through binding
                                    node = updatedNode
                                    
                                    // Commit individual changes through callbacks for proper tracking
                                    onHeightChange(draggedHeight)
                                    onWidthChange(draggedWidth)
                                    
                                    isResizing = false
                                    draggedHeight = 0
                                    draggedWidth = 0
                                    onResizeActiveChanged(false)
                                }
                            }
                    )
            }
        }
        .frame(width: displayWidth, height: displayHeight)
    }
    
    private var shouldShowTeamMemberTray: Bool {
        // Show tray for standard nodes, or for notes when chat is enabled
        if node.type == .note {
            return showChatSection
        }
        return true
    }
    
    private var headerHeight: CGFloat {
        var height: CGFloat = 60 // Base header height
        
        // Add team member tray height if present
        if shouldShowTeamMemberTray && node.teamMember != nil {
            height += 60 // Team member tray height (~50-60px)
        }
        
        return height
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
                            // Block if modal sheet is open
                            if let window = NSApp.mainWindow, !window.sheets.isEmpty {
                                return
                            }
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
            
            // Add Team Member button (only show if no team member exists)
            if shouldShowTeamMemberTray && node.teamMember == nil {
                Button(action: { 
                    // Check team member limit before allowing addition
                    if let account = dataService.userAccount {
                        // Skip limit check if unlimited (-1)
                        if !account.plan.hasUnlimitedTeamMembers {
                            let currentTeamMemberCount = projectTeamMembers.count + 1 // +1 for this node
                            if currentTeamMemberCount >= account.plan.maxTeamMembersPerJam {
                                // Show alert about limit reached
                                showTeamMemberLimitAlert(maxAllowed: account.plan.maxTeamMembersPerJam, currentPlan: account.plan)
                                return
                            }
                        }
                    }
                    
                    // Clear SwiftUI focus states
                    isTitleFocused = false
                    isPromptFocused = false
                    isDescFocused = false
                    
                    // Show modal - sheet detection will handle scroll
                    modalCoordinator.showTeamMemberModal(
                        existingMember: nil,
                        projectTeamMembers: projectTeamMembers,
                        onSave: { newMember in
                            onTeamMemberChange(newMember)
                            
                            // Track analytics for team member addition
                            if let role = roleManager.role(withId: newMember.roleId), let userId = dataService.userAccount?.id {
                                Task {
                                    await AnalyticsService.shared.trackTeamMemberUsage(
                                        userId: userId,
                                        projectId: node.projectId,
                                        nodeId: node.id,
                                        roleId: role.id,
                                        roleName: role.name,
                                        roleCategory: role.category.rawValue,
                                        experienceLevel: newMember.experienceLevel.rawValue,
                                        actionType: .attached
                                    )
                                }
                            }
                        },
                        onRemove: nil
                    )
                }) {
                    Image(systemName: "person.badge.plus")
                        .foregroundColor(headerTextColor)
                        .font(.system(size: 16))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Add Team Member")
            }
            
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
            
            // Toggle size button (maximize/minimize)
            Button(action: onMaximizeAndCenter) {
                let maxWidth = node.type == .note ? Node.maxNoteWidth : Node.maxWidth
                let isMaximized = node.width >= maxWidth && node.height >= Node.maxHeight
                Image(systemName: isMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .foregroundColor(headerTextColor)
                    .font(.system(size: 16))
            }
            .buttonStyle(PlainButtonStyle())
            .help(node.width >= (node.type == .note ? Node.maxNoteWidth : Node.maxWidth) && node.height >= Node.maxHeight ? "Minimize" : "Maximize")
        }
        .padding(.horizontal, Node.padding)
        .padding(.top, Node.padding)
        .padding(.bottom, Node.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            headerBackground
                .padding(.top, -Node.padding)
                .padding(.horizontal, -Node.padding)
        )
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
                        // Block if modal sheet is open
                        if let window = NSApp.mainWindow, !window.sheets.isEmpty {
                            return
                        }
                        editedDescription = node.description
                        isEditingDescription = true
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
            
            // Show processing message when AI is generating
            if isGenerating {
                processingMessageView
            }
        }
    }
    
    private func messageView(role: MessageRole, content: String) -> some View {
        // Find the corresponding conversation message to check for images
        let conversationMsg = node.conversation.first(where: { msg in
            msg.role == role && msg.content == content
        })
        
        if role == .user {
            // User messages: center everything at text content width
            return AnyView(
                HStack {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("You")
                            .font(.system(size: 12, weight: .semibold))
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                        
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
                                Text(content)
                                    .font(.system(size: 15))
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .frame(maxWidth: 700)
                    Spacer(minLength: 0)
                }
            )
        } else {
            // Assistant messages: title centered, content can extend full width
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    // Center the "Jam" title at text content width
                    HStack {
                        Spacer(minLength: 0)
                        Text("Jam")
                            .font(.system(size: 12, weight: .semibold))
                            .fontWeight(.semibold)
                            .foregroundColor(.accentColor)
                            .frame(maxWidth: 700, alignment: .leading)
                            .padding(.horizontal, 8)
                        Spacer(minLength: 0)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        // Show image if present
                        if let imageData = conversationMsg?.imageData,
                           let nsImage = NSImage(data: imageData) {
                            HStack {
                                Spacer(minLength: 0)
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 200, maxHeight: 200)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                    )
                                    .frame(maxWidth: 700, alignment: .leading)
                                    .padding(.horizontal, 8)
                                Spacer(minLength: 0)
                            }
                            .padding(.top, 8)
                        }
                        
                        // Show text content - MarkdownText handles centering text and full-width tables
                        if !content.isEmpty {
                            MarkdownText(text: content, onCopy: { text in
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                            })
                                .font(.system(size: 15))
                        }
                        
                        // Show search results if available
                        if let searchResults = conversationMsg?.searchResults, !searchResults.isEmpty {
                            searchResultsView(results: searchResults)
                                .padding(.top, 12)
                        }
                        
                        // Show web search footer if this message used search
                        if conversationMsg?.webSearchEnabled == true {
                            HStack {
                                Spacer()
                                Text("Generated using web search")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .padding(.top, 8)
                                Spacer()
                            }
                            .frame(maxWidth: 700)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            )
        }
    }
    
    private func searchResultsView(results: [SearchResult]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Text("Sources")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                Spacer()
            }
            .frame(maxWidth: 700)
            
            // Vertical stack of source cards - safe, no nested scrolling
            VStack(spacing: 8) {
                ForEach(Array(results.prefix(5).enumerated()), id: \.offset) { index, result in
                    Button(action: {
                        if let url = URL(string: result.url) {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(alignment: .top, spacing: 10) {
                            // Number badge
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.accentColor)
                                .frame(width: 20, height: 20)
                                .background(Color.accentColor.opacity(0.1))
                                .clipShape(Circle())
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                
                                Text(result.source)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.06))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(result.url)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: 700)
        }
    }
    
    private var inputView: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(spacing: 8) {
            // Voice recording view
            if recordingService.isRecording {
                VoiceInputView(recordingService: recordingService) { transcription in
                    // Append transcription to existing text
                    if !promptText.isEmpty {
                        promptText += " " + transcription
                    } else {
                        promptText = transcription
                    }
                    isPromptFocused = true
                }
            }
            
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
                // Text field with full area - better bottom padding for button spacing
                TextField("Ask a question...", text: $promptText, axis: .vertical)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 15))
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 36) // More space between text and buttons
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .lineLimit(3...6)
                    .focused($isPromptFocused)
                    .onKeyPress(.return, phases: .down) { keyPress in
                        // Shift+Return: insert newline (default behavior)
                        // Return alone: submit prompt
                        if keyPress.modifiers.contains(.shift) {
                            return .ignored // Let TextField handle newline
                        } else {
                            submitPrompt()
                            return .handled
                        }
                    }
                
                // Button row at bottom - aligned with text padding
                HStack {
                    // Left side buttons
                    HStack(spacing: 8) {
                        // Image upload button
                        if dataService.userAccount?.canAccessAdvancedFeatures ?? false {
                            Button(action: selectImage) {
                                Image(systemName: selectedImage == nil ? "photo" : "photo.fill")
                                    .font(.system(size: 19))
                                    .foregroundColor(selectedImage == nil ? .secondary : .accentColor)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Upload image")
                        }
                        
                        // Web search toggle button - PRO SEARCH for premium users
                        let userPlan = dataService.userAccount?.plan ?? .free
                        let isPremiumUser = userPlan == .pro || userPlan == .teams || userPlan == .enterprise
                        let isSearchActive = webSearchEnabled || (isGenerating && node.conversation.last(where: { $0.role == .user })?.webSearchEnabled == true)
                        
                        Button(action: {
                            webSearchEnabled.toggle()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "globe")
                                    .font(.system(size: isPremiumUser ? 11 : 19))
                                
                                if isPremiumUser {
                                    Text("PRO SEARCH")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                            }
                            .foregroundColor(isSearchActive ? .accentColor : .secondary)
                            .padding(.horizontal, isPremiumUser ? 8 : 0)
                            .padding(.vertical, isPremiumUser ? 4 : 0)
                            .background(Color.clear)
                            .cornerRadius(12)
                            .overlay(
                                isPremiumUser ? AnyView(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isSearchActive ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1.5)
                                ) : AnyView(EmptyView())
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(isPremiumUser ? (isSearchActive ? "PRO search enabled" : "Enable PRO search") : (isSearchActive ? "Web search enabled" : "Enable web search"))
                        .disabled(isGenerating)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    
                    Spacer()
                    
                    // Right side buttons (mic + send)
                    HStack(spacing: 8) {
                        // Voice input button
                        Button(action: toggleVoiceRecording) {
                            Image(systemName: recordingService.isRecording ? "mic.fill" : "mic")
                                .font(.system(size: 19))
                                .foregroundColor(recordingService.isRecording ? .red : .secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(recordingService.isRecording ? "Recording..." : "Voice input")
                        .disabled(isGenerating)
                        
                        // Send button
                        Button(action: {
                            submitPrompt()
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor((promptText.isEmpty && selectedImage == nil) ? .secondary : .accentColor)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(promptText.isEmpty && selectedImage == nil)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                }
                .padding(.horizontal, 8) // Match TextField horizontal padding
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
            }
            .frame(maxWidth: 700)
            Spacer(minLength: 0)
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
                        let maxWidth = node.type == .note ? Node.maxNoteWidth : Node.maxWidth
                        draggedHeight = max(Node.minHeight, min(Node.maxHeight, resizeStartHeight + deltaY))
                        draggedWidth = max(minWidth, min(maxWidth, resizeStartWidth + deltaX))
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
    
    private func showTeamMemberLimitAlert(maxAllowed: Int, currentPlan: UserPlan) {
        let alert = NSAlert()
        alert.messageText = "Team Member Limit Reached"
        alert.informativeText = "Your \(currentPlan.displayName) plan allows up to \(maxAllowed) AI team members. Upgrade your plan to add more team members."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
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
            onPromptSubmit(textToSend, selectedImageData, selectedImageMimeType, webSearchEnabled)
            promptText = ""
            selectedImage = nil
            selectedImageData = nil
            selectedImageMimeType = nil
            webSearchEnabled = false // Reset after submission
            isPromptFocused = true // Keep focus in input
        }
    }
    
    private func toggleVoiceRecording() {
        if recordingService.isRecording {
            // Stop recording - VoiceInputView handles transcription
            return
        } else {
            // Start recording
            Task {
                do {
                    try await recordingService.startRecording()
                } catch {
                    // Show error alert on main thread
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "Recording Error"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }
        }
    }
    
    // MARK: - Processing Message Animation
    
    private var processingMessageView: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Text("Jam")
                    .font(.system(size: 12, weight: .semibold))
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: 700, alignment: .leading)
                    .padding(.horizontal, 8)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(processingMessages[processingMessageIndex])
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                            .opacity(processingOpacity)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: processingOpacity)
                    }
                    
                    // Show web search indicator if the last user message had web search enabled
                    if let lastUserMsg = node.conversation.last(where: { $0.role == .user }),
                       lastUserMsg.webSearchEnabled {
                        HStack(spacing: 5) {
                            Image(systemName: "globe")
                                .font(.system(size: 11))
                                .foregroundColor(.accentColor)
                                .rotationEffect(.degrees(processingOpacity == 0.4 ? 360 : 0))
                                .animation(.linear(duration: 2.0).repeatForever(autoreverses: false), value: processingOpacity)
                            
                            Text("Searching the web...")
                                .font(.system(size: 12))
                                .foregroundColor(.accentColor.opacity(0.8))
                                .opacity(processingOpacity)
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 700)
            Spacer(minLength: 0)
        }
        .onAppear {
            // Start pulsing animation
            processingOpacity = 0.4
            // Rotate through messages
            processingTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
                processingMessageIndex = (processingMessageIndex + 1) % processingMessages.count
            }
        }
        .onDisappear {
            // Clean up timer
            processingTimer?.invalidate()
            processingTimer = nil
            // Reset states
            processingOpacity = 1.0
            processingMessageIndex = 0
        }
    }
    
    private let processingMessages = [
        "Jamming...",
        "Cooking up something good...",
        "Thinking deeply...",
        "Brewing ideas...",
        "Crafting a response...",
        "Working on it...",
        "Almost there..."
    ]
}
