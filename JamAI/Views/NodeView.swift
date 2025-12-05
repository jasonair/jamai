//
//  NodeView.swift
//  JamAI
//
//  Individual node card view
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct NodeView: View {
    @Binding var node: Node
    let isSelected: Bool
    let isGenerating: Bool
    let projectTeamMembers: [(nodeName: String, teamMember: TeamMember, role: Role?)]
    let searchHighlight: NodeSearchHighlight?
    let onTap: () -> Void
    let onPromptSubmit: (String, Data?, String?, Bool) -> Void
    let onTitleEdit: (String) -> Void
    let onDescriptionEdit: (String) -> Void
    let onDelete: () -> Void
    let onCreateChild: () -> Void
    let onDuplicate: () -> Void
    let onColorChange: (String) -> Void
    let onExpandSelection: (String) -> Void
    let onMakeNote: (String) -> Void
    let onJamWithThis: (String) -> Void
    let onHeightChange: (CGFloat) -> Void
    let onWidthChange: (CGFloat) -> Void
    let onResizeActiveChanged: (Bool) -> Void
    let onResizeCompensationChange: (CGSize) -> Void
    let onResizeLiveGeometryChange: (CGFloat, CGFloat) -> Void
    let onMaximizeAndCenter: () -> Void
    let onTeamMemberChange: (TeamMember?) -> Void
    
    // Wiring props
    var isWiring: Bool = false
    var wireSourceNodeId: UUID? = nil
    var onClickToStartWiring: ((UUID, ConnectionSide) -> Void)? = nil
    var onClickToConnect: ((UUID, ConnectionSide) -> Void)? = nil
    var onDeleteConnection: ((UUID, ConnectionSide) -> Void)? = nil
    var hasTopConnection: Bool = false
    var hasRightConnection: Bool = false
    var hasBottomConnection: Bool = false
    var hasLeftConnection: Bool = false
    
    @State private var isHovered: Bool = false
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
    @State private var isScrollReady = false
    @State private var isCoverFadingOut = false
    @State private var isContentVisible = false
    @State private var isClosing = false
    @State private var showExpandedContent = false
    @State private var processingMessageIndex = 0
    @State private var processingOpacity: Double = 1.0
    @State private var processingTimer: Timer?
    @State private var visibleMessageLimit: Int = 8
    @State private var expandedUserMessageIds: Set<UUID> = []
    @State private var isVoiceTranscribing = false
    @State private var showDeleteConfirmation = false
    
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
                // Header - fixed at top
                headerView
                
                Divider()
                
                // Content with fixed input at bottom
                ZStack {
                VStack(spacing: 0) {
                    if isSelected || showExpandedContent {
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
                                            // Top padding to clear header and team member tray
                                            Color.clear.frame(height: teamTrayPadding)
                                            
                                            // Show description as first message if it exists (legacy data)
                                            if !node.description.isEmpty {
                                                HStack {
                                                    Spacer(minLength: 0)
                                                    Text(node.description)
                                                        .font(.system(size: 15, weight: .light))
                                                        .foregroundColor(contentSecondaryTextColor)
                                                        .frame(maxWidth: 700)
                                                    Spacer(minLength: 0)
                                                }
                                            }
                                            
                                            // Conversation thread - no width constraint, let MarkdownText handle it
                                            conversationView
                                            
                                            // Bottom anchor for scrolling to end
                                            Color.clear
                                                .frame(height: 1)
                                                .id("scroll-bottom-anchor")
                                        }
                                        .padding(Node.padding)
                                    }
                                    .disabled(!isSelected)
                                    .opacity(isContentVisible ? 1 : 0)
                                    .onAppear {
                                        // Reset states and scroll to bottom
                                        isScrollReady = false
                                        isCoverFadingOut = false
                                        isContentVisible = false
                                        scrollToBottomThenShow(proxy: proxy)
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
                                    .onChange(of: searchHighlight) { _, newHighlight in
                                        // Scroll to the highlighted message when search result is selected
                                        if let highlight = newHighlight, highlight.nodeId == node.id {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                withAnimation(.easeInOut(duration: 0.3)) {
                                                    proxy.scrollTo(highlight.messageId, anchor: .center)
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
                                    .opacity(isContentVisible ? 1 : 0)
                                    .onAppear {
                                        // No scrolling needed for notes, but still sequence animations
                                        isScrollReady = true
                                        isCoverFadingOut = false
                                        isContentVisible = false
                                        
                                        // Fade out cover first, then fade in note content
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            isCoverFadingOut = true
                                        }
                                        
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                            withAnimation(.easeIn(duration: 0.2)) {
                                                isContentVisible = true
                                            }
                                        }
                                    }
                            }
                        } else {
                            // For standard nodes: ScrollView with conversation
                            ScrollViewReader { proxy in
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 12) {
                                        // Top padding to clear header and team member tray
                                        Color.clear.frame(height: teamTrayPadding)
                                        
                                        // Show description as first message if it exists (legacy data)
                                        if !node.description.isEmpty {
                                            HStack {
                                                Spacer(minLength: 0)
                                                Text(node.description)
                                                    .font(.system(size: 15, weight: .light))
                                                    .foregroundColor(contentSecondaryTextColor)
                                                    .frame(maxWidth: 700)
                                                Spacer(minLength: 0)
                                            }
                                        }
                                        
                                        // Conversation thread - no width constraint, let MarkdownText handle it
                                        conversationView
                                        
                                        // Bottom anchor for scrolling to end
                                        Color.clear
                                            .frame(height: 1)
                                            .id("scroll-bottom-anchor")
                                    }
                                    .padding(Node.padding)
                                }
                                .disabled(!isSelected)
                                .opacity(isContentVisible ? 1 : 0)
                                .onAppear {
                                    // Reset states and scroll to bottom
                                    isScrollReady = false
                                    isCoverFadingOut = false
                                    isContentVisible = false
                                    scrollToBottomThenShow(proxy: proxy)
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
                                .onChange(of: searchHighlight) { _, newHighlight in
                                    // Scroll to the highlighted message when search result is selected
                                    if let highlight = newHighlight, highlight.nodeId == node.id {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                proxy.scrollTo(highlight.messageId, anchor: .center)
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
                            .padding(.horizontal, Node.padding / 2)
                            .padding(.vertical, Node.padding / 2)
                    }
                    }
                }
                
                // Cover view - shown when not selected OR when selected but content not visible yet
                if !isSelected || !isContentVisible || isClosing {
                    ZStack {
                        // Background stays solid
                        contentBackground
                        
                        // Icon and text fade out
                        VStack {
                            Spacer(minLength: 0)
                            HStack {
                                Spacer(minLength: 0)
                                VStack(spacing: 8) {
                                    if let teamMember = node.teamMember,
                                       let role = roleManager.role(withId: teamMember.roleId) {
                                        Image(systemName: role.icon)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 40, height: 40)
                                            .foregroundColor(headerTextColor)
                                            .opacity(0.8)
                                        Text(teamMember.displayName(with: role))
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(headerTextColor.opacity(0.8))
                                    }
                                    Text(node.title.isEmpty ? "Untitled" : node.title)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(headerTextColor)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(3)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(headerBackground)
                                        .cornerRadius(8)
                                        .frame(maxWidth: 260)
                                }
                                .offset(y: -10)
                                Spacer(minLength: 0)
                            }
                            Spacer(minLength: 0)
                        }
                        .opacity(isCoverFadingOut ? 0 : 1)
                    }
                }
                }
                .frame(height: (isResizing ? draggedHeight : node.height) - headerHeight)
                .background(contentBackground)
                .overlay(alignment: .top) {
                    // Team Member Tray - slides down from top as overlay
                    if shouldShowTeamMemberTray && (isSelected || showExpandedContent) && node.teamMember != nil {
                        VStack(spacing: 0) {
                            if let teamMember = node.teamMember {
                                TeamMemberTray(
                                    teamMember: teamMember,
                                    role: roleManager.role(withId: teamMember.roleId),
                                    personality: node.personality,
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
                                                        actionType: .attached
                                                    )
                                                }
                                            }
                                        },
                                            onRemove: { 
                                            let oldMember = node.teamMember
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
                                    },
                                    onPersonalityChange: { newPersonality in
                                        node.personality = newPersonality
                                    }
                                )
                                
                                Divider()
                            }
                        }
                        .background(contentBackground)
                        .offset(y: isScrollReady ? 0 : -70)
                        .animation(.easeOut(duration: 0.3), value: isScrollReady)
                    }
                }
                .clipped()
                .overlay(
                    TapThroughOverlay(onTap: onTap, isNodeSelected: isSelected)
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
            // Connection points for manual wiring
            .overlay(
                ConnectionPointsOverlayInline(
                    nodeId: node.id,
                    nodeWidth: node.width,
                    nodeHeight: node.height,
                    isNodeHovered: isHovered,
                    isNodeSelected: isSelected,
                    isWiring: isWiring,
                    wireSourceNodeId: wireSourceNodeId,
                    hasTopConnection: hasTopConnection,
                    hasRightConnection: hasRightConnection,
                    hasBottomConnection: hasBottomConnection,
                    hasLeftConnection: hasLeftConnection,
                    onClickToStartWiring: onClickToStartWiring ?? { _, _ in },
                    onClickToConnect: onClickToConnect ?? { _, _ in },
                    onDeleteConnection: onDeleteConnection
                )
            )
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                // Block node selection if modal is open
                guard !modalCoordinator.isModalPresented else { return }
                onTap()
            }
            .overlay(
                RightClickExpandOverlay(
                    onExpand: onExpandSelection,
                    onMakeNote: onMakeNote,
                    onJamWithThis: onJamWithThis
                )
            )
            // Delete confirmation overlay - centered on node
            .overlay(
                Group {
                    if showDeleteConfirmation {
                        ZStack {
                            // Semi-transparent background
                            Color.black.opacity(0.4)
                                .cornerRadius(Node.cornerRadius)
                            
                            // Confirmation dialog
                            VStack(spacing: 12) {
                                Text("Delete this node?")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("This action cannot be undone.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 12) {
                                    Button("Cancel") {
                                        showDeleteConfirmation = false
                                    }
                                    .buttonStyle(.bordered)
                                    .onHover { hovering in
                                        if hovering {
                                            NSCursor.pointingHand.push()
                                        } else {
                                            NSCursor.pop()
                                        }
                                    }
                                    
                                    Button("Delete") {
                                        showDeleteConfirmation = false
                                        onDelete()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                    .onHover { hovering in
                                        if hovering {
                                            NSCursor.pointingHand.push()
                                        } else {
                                            NSCursor.pop()
                                        }
                                    }
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(nsColor: .windowBackgroundColor))
                                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                            )
                        }
                    }
                }
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
                // Opening - set showExpandedContent immediately
                showExpandedContent = true
                isClosing = false
                // Only focus prompt for non-note nodes or when chat section is visible
                // Notes can be scrolled and clicked to focus without auto-focusing
                if node.type != .note || showChatSection {
                    isPromptFocused = true
                }
                isEditingTitle = false
            } else {
                // Closing - animate out before hiding content
                isClosing = true
                isDescFocused = false
                isPromptFocused = false
                isTitleFocused = false
                isEditingTitle = false
                isEditingDescription = false
                
                // Step 1: Fade out content
                withAnimation(.easeOut(duration: 0.15)) {
                    isContentVisible = false
                }
                
                // Step 2: Fade in cover icon/text
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeIn(duration: 0.15)) {
                        isCoverFadingOut = false
                    }
                    
                    // Step 3: Slide up team bar
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.easeIn(duration: 0.2)) {
                            isScrollReady = false
                        }
                        
                        // Finally: Hide expanded content after animations complete
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            showExpandedContent = false
                            isClosing = false
                        }
                    }
                }
            }
        }
        .allowsHitTesting(!modalCoordinator.isModalPresented) // Disable all interaction when modal is open
        )
    }
    
    // MARK: - Computed Properties
    
    private var imageNodeView: some View {
        let displayWidth = draggedWidth > 0 ? draggedWidth : node.width
        let displayHeight = draggedHeight > 0 ? draggedHeight : node.height

        return ZStack(alignment: .topLeading) {  // Top-left anchor
            Group {
                // Display the image
                if let imageData = node.imageData, let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.low)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: displayWidth, height: displayHeight, alignment: .topLeading)
                        .clipped()
                        .overlay(
                            // Selection border
                            Rectangle()
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: isSelected ? 2 : 0)
                        )
                        .onTapGesture { onTap() }
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
                                        onResizeCompensationChange(.zero)
                                    }

                                    let deltaX = value.location.x - dragStartLocation.x
                                    let deltaY = value.location.y - dragStartLocation.y

                                    // Calculate aspect ratio from original dimensions
                                    let aspectRatio = resizeStartWidth / resizeStartHeight

                                    // Determine driver dimension
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

                                    // Live geometry updates keep top-left pinned; no extra compensation needed
                                    onResizeCompensationChange(.zero)
                                    onResizeLiveGeometryChange(draggedWidth, draggedHeight)
                                }
                                .onEnded { value in
                                    if isResizing {
                                        // Calculate how much size changed (for reference)
                                        let _ = draggedWidth - resizeStartWidth
                                        let _ = draggedHeight - resizeStartHeight

                                        // Keep top-left pinned: do not change x/y
                                        var updatedNode = node
                                        updatedNode.width = draggedWidth
                                        updatedNode.height = draggedHeight

                                        // Update through binding
                                        node = updatedNode

                                        // Commit individual changes through callbacks for persistence
                                        onHeightChange(draggedHeight)
                                        onWidthChange(draggedWidth)

                                        // Clear compensation after commit
                                        onResizeCompensationChange(.zero)

                                        isResizing = false
                                        draggedHeight = 0
                                        draggedWidth = 0
                                        onResizeActiveChanged(false)
                                    }
                                }
                        )
                }
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
        // Fixed header height - team tray animates separately and doesn't affect this
        return 60
    }
    
    private var teamTrayPadding: CGFloat {
        // Padding at top of content to clear team member tray when present
        // Team tray is ~44px height + divider
        if shouldShowTeamMemberTray && node.teamMember != nil {
            return 35
        }
        return 0
    }
    
    // MARK: - Subviews
    
    @State private var showNodeMenu = false
    
    private var headerView: some View {
        HStack {
            // Node type icon (note icon for notes, no icon for standard nodes)
            if node.type == .note {
                Image(systemName: "note.text")
                    .foregroundColor(headerTextColor)
                    .font(.system(size: 16))
            }
            
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
            
            if isSelected || showExpandedContent {
                // Title and icons with fade animation
                Group {
                    // Title
                    if isEditingTitle {
                        TextField("Title", text: $editedTitle, onCommit: {
                            onTitleEdit(editedTitle)
                            isEditingTitle = false
                        })
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(headerTextColor)
                        .focused($isTitleFocused)
                    } else {
                        HStack(spacing: 8) {
                            Text(node.title.isEmpty ? "Untitled" : node.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(node.title.isEmpty ? headerTextColor.opacity(0.6) : headerTextColor)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .onTapGesture {
                                    // Block if modal is open
                                    if modalCoordinator.isModalPresented { return }
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
                }
                .opacity(isContentVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isContentVisible)
                
                Spacer()
                
                // Header action buttons with fade animation
                Group {
                    // Add Team Member button (only show if no team member exists)
                    if shouldShowTeamMemberTray && node.teamMember == nil {
                        Button(action: { 
                            // All plans now have unlimited team members - no limit check needed
                            
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
                    
                    // Node menu dropdown (only when selected)
                    Menu {
                        Button(action: onCreateChild) {
                            Label("Fork", systemImage: "arrow.branch")
                        }
                        
                        Button(action: onDuplicate) {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .medium))
                            .rotationEffect(.degrees(90))
                    }
                    .foregroundStyle(headerTextColor)
                    .tint(headerTextColor)
                    .buttonStyle(PlainButtonStyle())
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .help("Node options")
                    
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
                .opacity(isContentVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isContentVisible)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, Node.padding)
        .padding(.top, Node.padding)
        .padding(.bottom, Node.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 60) // Fixed header height
        .background(
            headerBackground
                .padding(.top, -Node.padding)
                .padding(.horizontal, -Node.padding)
        )
    }
    
    private var noteDescriptionView: some View {
        // Simple TextEditor that handles both reading and editing
        ZStack(alignment: .topLeading) {
            // Placeholder when empty
            if editedDescription.isEmpty {
                Text("Click to start typing...")
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(contentSecondaryTextColor.opacity(0.5))
                    .padding(.top, 0)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            
            // TextEditor - always present, scrolls naturally
            // Uses local state to avoid update loops
            TextEditor(text: $editedDescription)
                .font(.system(size: 15, weight: .light))
                .foregroundColor(contentSecondaryTextColor)
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
        .onChange(of: editedDescription) { _, newValue in
            // Auto-save on type for FigJam/Miro-style notes
            if newValue != node.description {
                onDescriptionEdit(newValue)
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
        let conversation = node.conversation
        let totalCount = conversation.count
        let limit = max(0, min(visibleMessageLimit, totalCount))
        let visibleMessages: [ConversationMessage] = totalCount > 0 ? Array(conversation.suffix(limit)) : []
        let hiddenCount = max(0, totalCount - visibleMessages.count)
        
        return VStack(alignment: .leading, spacing: 8) {
            if conversation.isEmpty {
                // Show legacy prompt/response for backwards compatibility
                if !node.prompt.isEmpty {
                    messageView(message: nil, role: .user, content: node.prompt)
                        .id("legacy-user")
                }
                if !node.response.isEmpty {
                    messageView(message: nil, role: .assistant, content: node.response)
                        .id("legacy-assistant")
                }
            } else {
                if hiddenCount > 0 {
                    Button(action: {
                        let newLimit = min(visibleMessageLimit + 8, totalCount)
                        visibleMessageLimit = newLimit
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.circle")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(contentSecondaryTextColor)
                            Text("Show earlier messages")
                                .font(.system(size: 11))
                                .foregroundColor(contentSecondaryTextColor)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(contentSecondaryTextColor.opacity(0.12))
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(maxWidth: 700)
                }
                
                // Show conversation thread
                // Fallback: if there are only assistant messages (older data), still show the last prompt above them
                if !conversation.contains(where: { $0.role == .user }) && !node.prompt.isEmpty {
                    messageView(message: nil, role: .user, content: node.prompt)
                        .id("legacy-user-fallback")
                }
                ForEach(visibleMessages) { message in
                    messageView(message: message, role: message.role, content: message.content)
                        .id(message.id)
                }
            }
            
            // Show processing message when AI is generating
            if isGenerating {
                processingMessageView
            }
        }
    }
    
    private func messageView(message: ConversationMessage?, role: MessageRole, content: String) -> some View {
        // Find the corresponding conversation message to check for images
        let conversationMsg = message ?? node.conversation.first(where: { msg in
            msg.role == role && msg.content == content
        })
        
        if role == .user {
            let truncationThreshold = 1500
            let isLongMessage = content.count > truncationThreshold
            let messageId = message?.id
            let isExpanded = messageId.map { expandedUserMessageIds.contains($0) } ?? false
            let shouldTruncate = isLongMessage && !isExpanded
            let displayText: String
            if shouldTruncate {
                let preview = content.prefix(truncationThreshold)
                displayText = String(preview) + "\u{2026}"
            } else {
                displayText = content
            }
            
            // User messages: center everything at text content width
            return AnyView(
                HStack {
                    Spacer(minLength: 0)
                    ZStack(alignment: .topTrailing) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("You")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(contentSecondaryTextColor)
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
                                if !displayText.isEmpty {
                                    Text(displayText)
                                        .font(.system(size: 15, weight: .light))
                                        .foregroundColor(contentPrimaryTextColor)
                                        .textSelection(.enabled)
                                }
                                
                                if isLongMessage, let messageId = messageId {
                                    Button(action: {
                                        if expandedUserMessageIds.contains(messageId) {
                                            expandedUserMessageIds.remove(messageId)
                                        } else {
                                            expandedUserMessageIds.insert(messageId)
                                        }
                                    }) {
                                        Text(isExpanded ? "Show less" : "See more")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.accentColor)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .padding(.top, 2)
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .frame(maxWidth: 700, alignment: .leading)
                        
                        if let concreteMessage = message {
                            Button(action: {
                                revertConversation(to: concreteMessage, originalContent: content)
                            }) {
                                Image(systemName: "arrow.counterclockwise.circle")
                                    .font(.system(size: 14))
                                    .foregroundColor(contentSecondaryTextColor.opacity(0.9))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.top, 24)
                            .padding(.trailing, 4)
                            .help("Revert to this prompt")
                            .disabled(isGenerating)
                            .opacity(isGenerating ? 0.4 : 1.0)
                        }
                    }
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
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(contentSecondaryTextColor)
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
                            MarkdownText(
                                text: content,
                                onCopy: { text in
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(text, forType: .string)
                                },
                                textColorOverride: contentPrimaryTextColor,
                                accessoryTintColor: contentSecondaryTextColor
                            )
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
                                    .foregroundColor(contentSecondaryTextColor.opacity(0.7))
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(contentSecondaryTextColor)
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
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(contentSecondaryTextColor)
                                .frame(width: 20, height: 20)
                                .background(contentSecondaryTextColor.opacity(0.1))
                                .clipShape(Circle())
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(contentPrimaryTextColor)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                
                                Text(result.source)
                                    .font(.system(size: 10))
                                    .foregroundColor(contentSecondaryTextColor)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                                .foregroundColor(contentSecondaryTextColor)
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
                if recordingService.isRecording || isVoiceTranscribing {
                    VoiceInputView(
                        recordingService: recordingService,
                        isTranscribing: $isVoiceTranscribing
                    ) { transcription in
                        // Append transcription to existing text
                        if !promptText.isEmpty {
                            promptText += " " + transcription
                        } else {
                            promptText = transcription
                        }
                        isPromptFocused = true
                        // Track transcription usage for analytics (no credit deduction)
                        Task {
                            await CreditTracker.shared.trackTranscriptionUsage(
                                transcriptText: transcription,
                                nodeId: node.id,
                                projectId: node.projectId
                            )
                        }
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
                            .foregroundColor(contentSecondaryTextColor)
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
                ZStack(alignment: .topLeading) {
                    if promptText.isEmpty {
                        Text("Ask a question...")
                            .font(.system(size: 15, weight: .light))
                            .foregroundColor(contentSecondaryTextColor.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 10)
                            .padding(.leading, 5) // Shift placeholder slightly right
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $promptText)
                        .font(.system(size: 15, weight: .light))
                        .foregroundColor(contentPrimaryTextColor)
                        .scrollContentBackground(.hidden)
                        // Slightly smaller external horizontal padding to offset TextEditor internal inset
                        // so the caret visually aligns with the placeholder text
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                        .frame(minHeight: 40, maxHeight: 100, alignment: .topLeading)
                        .frame(minHeight: 40, maxHeight: 100, alignment: .topLeading)
                        .focused($isPromptFocused)
                        .disabled(!isSelected)
                        .onKeyPress(.return, phases: .down) { keyPress in
                            // Shift+Return: insert newline
                            // Return alone: submit prompt
                            if keyPress.modifiers.contains(.shift) {
                                return .ignored // Let TextEditor insert newline
                            } else if keyPress.modifiers.contains(.command) {
                                // Command+Return should behave like normal Return inside the editor
                                return .ignored
                            } else {
                                submitPrompt()
                                return .handled
                            }
                        }
                        .onKeyPress("a", phases: .down) { keyPress in
                            // Enable Command+A to select all text within the prompt editor
                            if keyPress.modifiers.contains(.command) {
                                // Explicitly send selectAll: to the current first responder
                                // so the underlying NSTextView selects all text.
                                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                                return .handled
                            }
                            return .ignored
                        }
                }
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .padding(.bottom, 36) // Extra space between text and buttons
                
                // Button row at bottom - aligned with text padding
                HStack {
                    // Left side buttons
                    HStack(spacing: 8) {
                        // Image upload button
                        if dataService.userAccount?.canAccessAdvancedFeatures ?? false {
                            Button(action: selectImage) {
                                Image(systemName: selectedImage == nil ? "photo" : "photo.fill")
                                    .font(.system(size: 19))
                                    .foregroundColor(selectedImage == nil ? contentSecondaryTextColor : headerTextColor)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Upload image")
                        }
                        
                        // Web search toggle button (temporarily disabled in UI)
                        if false {
                            let isSearchActive = webSearchEnabled || (isGenerating && node.conversation.last(where: { $0.role == .user })?.webSearchEnabled == true)

                            Button(action: {
                                webSearchEnabled.toggle()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 11))

                                    Text("Web Search")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(isSearchActive ? headerTextColor : contentSecondaryTextColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.clear)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isSearchActive ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help(isSearchActive ? "Web search enabled" : "Enable web search")
                            .disabled(isGenerating)
                        }
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
                                .foregroundColor(recordingService.isRecording ? .red : contentSecondaryTextColor)
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
                                .foregroundColor((promptText.isEmpty && selectedImage == nil) ? contentSecondaryTextColor : headerTextColor)
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
            .padding(5)
            .frame(maxWidth: 700)
            Spacer(minLength: 0)
        }
    }
    
    // MARK: - Styling
    
    private var headerBaseColor: Color {
        if let nodeColor = NodeColor.color(for: node.color), node.color != "none" {
            return nodeColor.color
        } else {
            return colorScheme == .dark
                ? Color(nsColor: .controlBackgroundColor)
                : Color(white: 0.95)
        }
    }
    
    private var headerBackground: some View {
        AnyView(headerBaseColor)
    }
    
    private var contentBackground: some View {
        let overlayOpacity = colorScheme == .dark ? 0.04 : 0.06
        return AnyView(
            ZStack {
                headerBaseColor
                Color.white.opacity(overlayOpacity)
            }
        )
    }
    
    private var headerTextColor: Color {
        if let nodeColor = NodeColor.color(for: node.color), node.color != "none" {
            return nodeColor.textColor(for: nodeColor.color)
        } else {
            return .primary
        }
    }
    
    private var contentPrimaryTextColor: Color {
        if let _ = NodeColor.color(for: node.color), node.color != "none" {
            return headerTextColor
        } else {
            return .primary
        }
    }
    
    private var contentSecondaryTextColor: Color {
        if let _ = NodeColor.color(for: node.color), node.color != "none" {
            return headerTextColor.opacity(0.8)
        } else {
            return .secondary
        }
    }
    
    private var cardBackground: some View {
        if let nodeColor = NodeColor.color(for: node.color), node.color != "none" {
            // Apply tint to card body; stronger tint for notes to stand out
            if node.type == .note {
                // Notes get more visible color treatment
                let tintOpacity: Double = 1.0
                let tintColor = nodeColor.color.opacity(tintOpacity)
                let baseColor = Color.clear
                
                return AnyView(
                    ZStack {
                        baseColor
                        tintColor
                    }
                )
            } else {
                // Standard nodes get subtle tint
                let tintOpacity: Double = 1.0
                let tintColor = nodeColor.color.opacity(tintOpacity)
                let baseColor = Color.clear
                
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
                    : Color(white: 0.95)
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
                            onResizeCompensationChange(.zero)
                        }
                        // Calculate delta from initial drag position (prevents drift)
                        let deltaX = value.location.x - dragStartLocation.x
                        let deltaY = value.location.y - dragStartLocation.y
                        
                        // Update local state only - smooth without triggering binding updates
                        let minWidth = node.type == .note ? Node.minNoteWidth : Node.minWidth
                        let maxWidth = node.type == .note ? Node.maxNoteWidth : Node.maxWidth
                        let minHeight = node.type == .note ? Node.minNoteHeight : Node.minHeight
                        let maxHeight = node.type == .note ? Node.maxNoteHeight : Node.maxHeight
                        draggedHeight = max(minHeight, min(maxHeight, resizeStartHeight + deltaY))
                        draggedWidth = max(minWidth, min(maxWidth, resizeStartWidth + deltaX))

                        // Live geometry updates keep top-left pinned; no extra compensation needed
                        onResizeCompensationChange(.zero)
                        onResizeLiveGeometryChange(draggedWidth, draggedHeight)
                    }
                    .onEnded { _ in
                        isResizing = false
                        // Only update the binding once at the end
                        onHeightChange(draggedHeight)
                        onWidthChange(draggedWidth)
                        // Clear compensation after commit to persist top-left pin
                        onResizeCompensationChange(.zero)
                        onResizeActiveChanged(false)
                    }
            )
    }
    
    // MARK: - Actions
    
    private func scrollToBottomThenShow(proxy: ScrollViewProxy) {
        // Scroll multiple times while hidden to ensure scroll position is at the end
        // Content needs time to fully lay out before scroll will work correctly
        // Then reveal the content with a fade-in animation
        let scrollDelays: [Double] = [0.1, 0.25, 0.4, 0.55, 0.7]
        
        for delay in scrollDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                proxy.scrollTo("scroll-bottom-anchor", anchor: .bottom)
            }
        }
        
        // After scrolling is complete, trigger animations in sequence
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            // One final scroll right before showing to ensure position is correct
            proxy.scrollTo("scroll-bottom-anchor", anchor: .bottom)
            
            // Step 1: Team bar slides down
            withAnimation(.easeOut(duration: 0.3)) {
                isScrollReady = true
            }
            
            // Step 2: Cover icon/text fades out (after team bar animation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeOut(duration: 0.2)) {
                    isCoverFadingOut = true
                }
                
                // Step 3: Content fades in (after cover fades out)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.easeIn(duration: 0.2)) {
                        isContentVisible = true
                    }
                }
            }
        }
    }
    
    private func revertConversation(to message: ConversationMessage, originalContent: String) {
        let alert = NSAlert()
        alert.messageText = "Revert to this step?"
        alert.informativeText = "This will remove all messages after this prompt and move it back into the input. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Revert")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        
        let allMessages = node.conversation
        guard let index = allMessages.firstIndex(where: { $0.id == message.id }) else { return }
        let trimmed = Array(allMessages.prefix(index))
        
        var updatedNode = node
        updatedNode.setConversation(trimmed)
        updatedNode.prompt = originalContent
        if let lastAssistant = trimmed.last(where: { $0.role == .assistant }) {
            updatedNode.response = lastAssistant.content
        } else {
            updatedNode.response = ""
        }
        node = updatedNode
        
        promptText = originalContent
        isPromptFocused = true
        
        // Ensure the node stays selected after the revert completes
        onTap()
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
                } catch let error as AudioRecordingError {
                    await MainActor.run {
                        if case .permissionDenied = error {
                            // Open System Settings > Privacy & Security > Microphone
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                NSWorkspace.shared.open(url)
                            }
                        } else {
                            // Show generic error alert for other errors
                            let alert = NSAlert()
                            alert.messageText = "Recording Error"
                            alert.informativeText = error.localizedDescription
                            alert.alertStyle = .warning
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                        }
                    }
                } catch {
                    // Handle unexpected errors
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(contentSecondaryTextColor)
                    .frame(maxWidth: 700, alignment: .leading)
                    .padding(.horizontal, 8)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(processingMessages[processingMessageIndex])
                            .font(.system(size: 15, weight: .light))
                            .foregroundColor(contentSecondaryTextColor)
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
