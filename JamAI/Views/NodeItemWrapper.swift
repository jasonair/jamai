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
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: () -> Void
    
    var body: some View {
        NodeView(
            node: $node,
            isSelected: isSelected,
            isGenerating: isGenerating,
            onTap: onTap,
            onPromptSubmit: onPromptSubmit,
            onTitleEdit: onTitleEdit,
            onDescriptionEdit: onDescriptionEdit,
            onDelete: onDelete,
            onCreateChild: onCreateChild
        )
        .position(
            x: node.x + Node.nodeWidth / 2,
            y: node.y + (node.isExpanded ? node.height : Node.collapsedHeight) / 2
        )
        .gesture(
            DragGesture()
                .onChanged(onDragChanged)
                .onEnded { _ in onDragEnded() }
        )
    }
}
