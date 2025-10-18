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
    let isGenerating: Bool
    let projectTeamMembers: [(nodeName: String, teamMember: TeamMember, role: Role?)]
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
    let onExpandNote: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: () -> Void
    let onHeightChange: (CGFloat) -> Void
    let onWidthChange: (CGFloat) -> Void
    let onResizeActiveChanged: (Bool) -> Void
    let onMaximizeAndCenter: () -> Void
    let onTeamMemberChange: (TeamMember?) -> Void
    @State private var isResizingActive: Bool = false
    
    var body: some View {
        Group {
            if node.type == .text {
                TextLabelView(
                    node: $node,
                    isSelected: isSelected,
                    onTap: onTap,
                    onDelete: onDelete,
                    onDescriptionEdit: onDescriptionEdit
                )
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
                    isGenerating: isGenerating,
                    projectTeamMembers: projectTeamMembers,
                    onTap: onTap,
                    onPromptSubmit: onPromptSubmit,
                    onTitleEdit: onTitleEdit,
                    onDescriptionEdit: onDescriptionEdit,
                    onDelete: onDelete,
                    onCreateChild: onCreateChild,
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
                    onMaximizeAndCenter: onMaximizeAndCenter,
                    onTeamMemberChange: onTeamMemberChange
                )
            }
        }
        .position(
            x: node.x + displayWidth / 2,
            y: node.y + displayHeight / 2
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { value in
                    if !isResizingActive { onDragChanged(value) }
                }
                .onEnded { _ in onDragEnded() }
        )
    }

    private var displayHeight: CGFloat {
        switch node.type {
        case .shape:
            return node.height
        case .text:
            return max(40, node.height)
        case .note:
            return node.height
        case .standard:
            return node.height
        }
    }
    
    private var displayWidth: CGFloat {
        // Use the node's custom width property
        return node.width
    }
}
