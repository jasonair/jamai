//
//  OutlineView.swift
//  JamAI
//
//  Left floating pane showing hierarchical outline of canvas nodes
//

import SwiftUI

struct OutlineView: View {
    @ObservedObject var viewModel: CanvasViewModel
    let viewportSize: CGSize
    @Environment(\.colorScheme) var colorScheme
    
    @State private var hoveredNodeId: UUID?
    
    // Hierarchical node structure for the outline
    fileprivate struct OutlineNode: Identifiable {
        let id: UUID
        let node: Node
        let level: Int
        var children: [OutlineNode]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 14))
                Text("Outline")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(headerBackground)
            
            Divider()
            
            // Outline content
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(buildOutlineTree()) { outlineNode in
                        OutlineItemView(
                            outlineNode: outlineNode,
                            selectedNodeId: viewModel.selectedNodeId,
                            hoveredNodeId: $hoveredNodeId,
                            onNavigate: { navigateToNode($0) }
                        )
                    }
                    
                    if viewModel.nodes.isEmpty {
                        Text("No nodes yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 280)
        .frame(maxHeight: viewportSize.height - 120)
        .background(panelBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 2, y: 0)
    }
    
    // MARK: - Outline Tree Building
    
    private func buildOutlineTree() -> [OutlineNode] {
        // Find root nodes (nodes without parents or with non-existent parents)
        let rootNodes = viewModel.nodes.values.filter { node in
            node.parentId == nil || viewModel.nodes[node.parentId!] == nil
        }
        .sorted { $0.createdAt < $1.createdAt }
        
        return rootNodes.map { buildOutlineNode(from: $0, level: 0) }
    }
    
    private func buildOutlineNode(from node: Node, level: Int) -> OutlineNode {
        // Find children of this node
        let children = viewModel.nodes.values
            .filter { $0.parentId == node.id }
            .sorted { $0.createdAt < $1.createdAt }
            .map { buildOutlineNode(from: $0, level: level + 1) }
        
        return OutlineNode(id: node.id, node: node, level: level, children: children)
    }
    
    // MARK: - Navigation
    
    private func navigateToNode(_ nodeId: UUID) {
        viewModel.navigateToNode(nodeId, viewportSize: viewportSize)
    }
    
    // MARK: - Styling
    
    private var panelBackground: some View {
        colorScheme == .dark
            ? Color(nsColor: .controlBackgroundColor)
            : Color.white
    }
    
    private var headerBackground: some View {
        colorScheme == .dark
            ? Color(nsColor: .windowBackgroundColor)
            : Color(white: 0.96)
    }
}

// MARK: - Outline Item View

private struct OutlineItemView: View {
    let outlineNode: OutlineView.OutlineNode
    let selectedNodeId: UUID?
    @Binding var hoveredNodeId: UUID?
    let onNavigate: (UUID) -> Void
    
    @State private var isExpanded: Bool = true
    @Environment(\.colorScheme) var colorScheme
    
    private var isSelected: Bool {
        selectedNodeId == outlineNode.id
    }
    
    private var isHovered: Bool {
        hoveredNodeId == outlineNode.id
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Node item
            HStack(spacing: 6) {
                // Indent based on level
                if outlineNode.level > 0 {
                    Color.clear
                        .frame(width: CGFloat(outlineNode.level * 16))
                }
                
                // Expand/collapse chevron for nodes with children
                if !outlineNode.children.isEmpty {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(width: 12, height: 12)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    // Placeholder to maintain alignment
                    Color.clear.frame(width: 12, height: 12)
                }
                
                // Bullet point
                Circle()
                    .fill(nodeColor)
                    .frame(width: 6, height: 6)
                
                // Node title
                Text(nodeTitle)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(itemBackground)
            .cornerRadius(6)
            .contentShape(Rectangle())
            .onTapGesture {
                onNavigate(outlineNode.id)
            }
            .onHover { hovering in
                hoveredNodeId = hovering ? outlineNode.id : nil
            }
            
            // Children (recursive)
            if isExpanded {
                ForEach(outlineNode.children) { child in
                    OutlineItemView(
                        outlineNode: child,
                        selectedNodeId: selectedNodeId,
                        hoveredNodeId: $hoveredNodeId,
                        onNavigate: onNavigate
                    )
                }
            }
        }
    }
    
    private var nodeTitle: String {
        if !outlineNode.node.title.isEmpty {
            return outlineNode.node.title
        }
        return "Untitled"
    }
    
    private var nodeColor: Color {
        let colorString = outlineNode.node.color
        if colorString == "none" || colorString.isEmpty {
            return Color.gray.opacity(0.5)
        }
        if let nodeColor = NodeColor.color(for: colorString) {
            return nodeColor.color.opacity(0.8)
        }
        return Color.gray.opacity(0.5)
    }
    
    @ViewBuilder
    private var itemBackground: some View {
        if isSelected {
            Color.accentColor
        } else if isHovered {
            Color.gray.opacity(colorScheme == .dark ? 0.2 : 0.1)
        } else {
            Color.clear
        }
    }
}
