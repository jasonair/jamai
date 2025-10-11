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
    let onExpandNote: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: () -> Void
    let onHeightChange: (CGFloat) -> Void
    
    var body: some View {
        Group {
            if node.type == .note {
                NoteView(
                    node: $node,
                    isSelected: isSelected,
                    onDelete: onDelete,
                    onExpandNote: onExpandNote,
                    onDescriptionEdit: onDescriptionEdit,
                    onTap: onTap
                )
            } else {
                NodeView(
                    node: $node,
                    isSelected: isSelected,
                    isGenerating: isGenerating,
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
                    onHeightChange: onHeightChange
                )
            }
        }
        .position(
            x: node.x + Node.width(for: node.type) / 2,
            y: node.y + (node.isExpanded ? node.height : Node.collapsedHeight) / 2
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 3)
                .onChanged(onDragChanged)
                .onEnded { _ in onDragEnded() }
        )
    }
}
