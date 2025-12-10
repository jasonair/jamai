//
//  NodeItemWrapper.swift
//  JamAI
//
//  Lightweight wrapper to host a NodeView and its gesture/position logic.
//

import SwiftUI

struct NodeItemWrapper: View {
    @Binding var node: Node
    let isSelected: Bool
    let isMultiSelected: Bool  // Part of multi-select group (shift-click selection)
    let isRecentlyOpened: Bool  // Node was recently opened (within last 3) - keeps content expanded
    let isGenerating: Bool
    let hasError: Bool
    let hasUnreadResponse: Bool
    let hasCreditError: Bool
    let creditCheckResult: CreditCheckResult?
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
    let onExpandNote: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: () -> Void
    let onHeightChange: (CGFloat) -> Void
    let onWidthChange: (CGFloat) -> Void
    let onResizeActiveChanged: (Bool) -> Void
    let onResizeLiveGeometryChange: (CGFloat, CGFloat) -> Void
    let onMaximizeAndCenter: () -> Void
    let onTeamMemberChange: (TeamMember?) -> Void
    let onJamSquad: ((String) -> Void)?
    let onUpgradePlan: () -> Void
    let onUseLocalModel: () -> Void
    let onDismissCreditError: () -> Void
    var onNavigateToParent: (() -> Void)? = nil  // Navigate back to parent node for notes
    
    // Scroll position memory callbacks (macOS 15+)
    var onScrollOffsetChanged: ((CGFloat) -> Void)? = nil
    var savedScrollOffset: CGFloat? = nil
    
    /// Z-order check callback - returns true if this node should process the tap at the given window point
    var shouldProcessTap: ((NSPoint) -> Bool)? = nil
    
    // Wiring callbacks
    let isWiring: Bool
    let wireSourceNodeId: UUID?
    let onClickToStartWiring: (UUID, ConnectionSide) -> Void
    let onClickToConnect: (UUID, ConnectionSide) -> Void
    let onDeleteConnection: (UUID, ConnectionSide) -> Void
    let hasTopConnection: Bool
    let hasRightConnection: Bool
    let hasBottomConnection: Bool
    let hasLeftConnection: Bool
    
    @Environment(\.colorScheme) var colorScheme
    
    @State private var isResizingActive: Bool = false
    @State private var resizeCompensation: CGSize = .zero
    @State private var isTitleResizing: Bool = false
    @State private var titleResizeStartWidth: CGFloat = 0
    @State private var titleResizeStartHeight: CGFloat = 0
    @State private var titleDraggedWidth: CGFloat = 0
    @State private var titleDraggedHeight: CGFloat = 0
    @State private var titleDragStartLocation: CGPoint = .zero
    
    var body: some View {
        Group {
            if node.type == .title {
                ZStack(alignment: .bottomTrailing) {
                    // Title nodes: use TextLabelView plus a resize grip in the
                    // bottom-right corner when selected.
                    TextLabelView(
                        node: $node,
                        isSelected: isSelected,
                        onTap: onTap,
                        onDelete: onDelete,
                        onDescriptionEdit: onDescriptionEdit
                    )

                    if isSelected {
                        titleResizeGripOverlay
                    }
                }
            } else if node.type == .text {
                // Text annotation nodes: clamp to node.width
                TextLabelView(
                    node: $node,
                    isSelected: isSelected,
                    onTap: onTap,
                    onDelete: onDelete,
                    onDescriptionEdit: onDescriptionEdit
                )
                .frame(width: displayWidth, alignment: .topLeading)
            } else if node.type == .shape {
                ShapeItemView(
                    node: $node,
                    isSelected: isSelected,
                    onTap: onTap,
                    onDelete: onDelete
                )
            } else {
                NodeView(
                    node: $node,
                    isSelected: isSelected,
                    isRecentlyOpened: isRecentlyOpened,
                    isGenerating: isGenerating,
                    hasError: hasError,
                    hasUnreadResponse: hasUnreadResponse,
                    hasCreditError: hasCreditError,
                    creditCheckResult: creditCheckResult,
                    projectTeamMembers: projectTeamMembers,
                    searchHighlight: searchHighlight,
                    onTap: onTap,
                    onPromptSubmit: onPromptSubmit,
                    onTitleEdit: onTitleEdit,
                    onDescriptionEdit: onDescriptionEdit,
                    onDelete: onDelete,
                    onCreateChild: onCreateChild,
                    onDuplicate: onDuplicate,
                    onColorChange: onColorChange,
                    onExpandSelection: onExpandSelection,
                    onMakeNote: onMakeNote,
                    onJamWithThis: onJamWithThis,
                    onHeightChange: onHeightChange,
                    onWidthChange: onWidthChange,
                    onResizeActiveChanged: { active in
                        isResizingActive = active
                        onResizeActiveChanged(active)
                    },
                    onResizeCompensationChange: { comp in
                        resizeCompensation = comp
                    },
                    onResizeLiveGeometryChange: onResizeLiveGeometryChange,
                    onMaximizeAndCenter: onMaximizeAndCenter,
                    onTeamMemberChange: onTeamMemberChange,
                    onJamSquad: onJamSquad,
                    onUpgradePlan: onUpgradePlan,
                    onUseLocalModel: onUseLocalModel,
                    onDismissCreditError: onDismissCreditError,
                    onNavigateToParent: onNavigateToParent,
                    onScrollOffsetChanged: onScrollOffsetChanged,
                    savedScrollOffset: savedScrollOffset,
                    shouldProcessTap: shouldProcessTap,
                    isWiring: isWiring,
                    wireSourceNodeId: wireSourceNodeId,
                    onClickToStartWiring: onClickToStartWiring,
                    onClickToConnect: onClickToConnect,
                    onDeleteConnection: onDeleteConnection,
                    hasTopConnection: hasTopConnection,
                    hasRightConnection: hasRightConnection,
                    hasBottomConnection: hasBottomConnection,
                    hasLeftConnection: hasLeftConnection
                )
            }
        }
        // Multi-selection indicator - MUST be before .position() to render at node location
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isMultiSelected ? Color.blue : Color.clear, lineWidth: isMultiSelected ? 3 : 0)
                .shadow(color: isMultiSelected ? Color.blue.opacity(0.5) : Color.clear, radius: isMultiSelected ? 4 : 0)
                .allowsHitTesting(false)
        )
        .position(
            x: node.x + displayWidth / 2,
            y: node.y + displayHeight / 2
        )
        .offset(resizeCompensation)
        // Use regular gesture (not highPriority) so that child gestures like resize grip
        // can take precedence. This still takes precedence over canvas pan gestures.
        .gesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged { value in
                    // Don't move node if we're wiring or resizing
                    if !isResizingActive && !isWiring {
                        onDragChanged(value)
                    }
                }
                .onEnded { _ in
                    if !isWiring {
                        onDragEnded()
                    }
                }
        )
        // Invisible tagging view so AppKit hit-testing can recognize node areas
        .overlay(NodeHitTag().allowsHitTesting(false))
    }

    // Invisible NSView to tag node view hierarchy for hit-testing
    private struct NodeHitTag: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            let v = NSView(frame: .zero)
            v.identifier = NSUserInterfaceItemIdentifier("JamAI_Node")
            v.isHidden = true
            v.translatesAutoresizingMaskIntoConstraints = true
            v.setFrameSize(.zero)
            return v
        }
        func updateNSView(_ nsView: NSView, context: Context) {}
    }

    private var displayHeight: CGFloat {
        switch node.type {
        case .shape:
            return node.height
        case .text, .title:
            return max(40, node.height)
        case .note:
            return node.height
        case .image:
            return node.height
        case .standard:
            return node.height
        }
    }
    
    private var displayWidth: CGFloat {
        // Use the node's custom width property
        return node.width
    }

    /// Whether to use black for UI elements in dark mode with light node colors
    private var shouldUseBlackForDarkModeContrast: Bool {
        guard colorScheme == .dark else { return false }
        if let nodeColor = NodeColor.color(for: node.color), node.color != "none" {
            return nodeColor.isLightColor
        }
        return false
    }
    
    // Corner resize grip specifically for title nodes
    private var titleResizeGripOverlay: some View {
        ResizeGripView(forceBlack: shouldUseBlackForDarkModeContrast)
            .frame(width: 16, height: 16)
            .padding(.trailing, 8)
            .padding(.bottom, 8)
            .contentShape(Rectangle().size(width: 40, height: 40))
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if !isTitleResizing {
                            isTitleResizing = true
                            isResizingActive = true
                            titleResizeStartWidth = node.width
                            titleResizeStartHeight = node.height
                            titleDraggedWidth = node.width
                            titleDraggedHeight = node.height
                            titleDragStartLocation = value.location
                            onResizeActiveChanged(true)
                        }

                        let deltaX = value.location.x - titleDragStartLocation.x
                        let deltaY = value.location.y - titleDragStartLocation.y

                        let minWidth: CGFloat = 200
                        let maxWidth: CGFloat = 2000
                        let minHeight: CGFloat = 60
                        let maxHeight: CGFloat = 800

                        titleDraggedWidth = max(minWidth, min(maxWidth, titleResizeStartWidth + deltaX))
                        titleDraggedHeight = max(minHeight, min(maxHeight, titleResizeStartHeight + deltaY))

                        onResizeLiveGeometryChange(titleDraggedWidth, titleDraggedHeight)
                    }
                    .onEnded { _ in
                        guard isTitleResizing else { return }
                        isTitleResizing = false
                        isResizingActive = false
                        onHeightChange(titleDraggedHeight)
                        onWidthChange(titleDraggedWidth)
                        onResizeActiveChanged(false)
                    }
            )
    }
}
