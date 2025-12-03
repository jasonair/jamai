//
//  OutlineView.swift
//  JamAI
//
//  Left floating pane showing hierarchical outline of canvas nodes
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Event Blocking Container

/// NSView that intercepts all mouse events to prevent them from passing through
/// to views behind it (like canvas nodes). This is necessary because SwiftUI's
/// hit testing can leak through overlaid views.
class EventBlockingView: NSView {
    override var acceptsFirstResponder: Bool { true }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // If the point is within our bounds, check subviews first
        if bounds.contains(point) {
            // Check if any subview wants the event (this includes the NSHostingView)
            for subview in subviews.reversed() {
                let subviewPoint = convert(point, to: subview)
                if let hitView = subview.hitTest(subviewPoint) {
                    return hitView
                }
            }
            // No subview claimed it, return self to block it from going further
            return self
        }
        return nil
    }
    
    // Only swallow mouse events that reach us directly (not handled by subviews)
    // These are clicks on empty areas of the outline pane
    override func mouseDown(with event: NSEvent) {
        // Don't pass to super - this blocks the event from propagating to canvas
    }
    
    override func mouseUp(with event: NSEvent) {
        // Don't pass to super
    }
    
    override func rightMouseDown(with event: NSEvent) {
        // Don't pass to super
    }
    
    override func otherMouseDown(with event: NSEvent) {
        // Don't pass to super
    }
}

/// Wrapper that blocks all mouse events from passing through to views behind it
struct EventBlockingContainer<Content: View>: NSViewRepresentable {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    func makeNSView(context: Context) -> NSView {
        let blockingView = EventBlockingView()
        blockingView.wantsLayer = true
        
        let hostingView = NSHostingView(rootView: content)
        // Use autoresizing mask instead of constraints - let SwiftUI drive the size
        hostingView.autoresizingMask = [.width, .height]
        blockingView.addSubview(hostingView)
        
        return blockingView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let hostingView = nsView.subviews.first as? NSHostingView<Content> {
            hostingView.rootView = content
            // Ensure hosting view fills the blocking view
            hostingView.frame = nsView.bounds
        }
    }
}

// MARK: - Outline Scroll View (NSScrollView wrapper to capture scroll events)

/// Custom scroll view that properly captures scroll events and prevents them from
/// propagating to the canvas behind the outline pane.
struct OutlineScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        
        // Create hosting view for SwiftUI content
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        // Use a flipped document view for proper top-to-bottom layout
        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(hostingView)
        
        scrollView.documentView = documentView
        
        // Constrain hosting view to document view
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: documentView.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            // Make document view match scroll view width
            documentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Update the hosting view's root view
        if let documentView = scrollView.documentView,
           let hostingView = documentView.subviews.first as? NSHostingView<Content> {
            hostingView.rootView = content
        }
    }
}

/// Flipped NSView for proper top-to-bottom content layout in scroll view
private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

struct OutlineView: View {
    @ObservedObject var viewModel: CanvasViewModel
    let viewportSize: CGSize
    @Binding var isCollapsed: Bool
    @Environment(\.colorScheme) var colorScheme
    
    @State private var hoveredNodeId: UUID?
    @State private var draggedNodeId: UUID?
    @State private var dropTargetIndex: Int?
    
    // Hierarchical node structure for the outline
    fileprivate struct OutlineNode: Identifiable {
        let id: UUID
        let node: Node
        let level: Int
        var children: [OutlineNode]
    }
    
    var body: some View {
        // Wrap in EventBlockingContainer to intercept all mouse events at AppKit level
        // This prevents clicks from leaking through to canvas nodes behind the outline
        EventBlockingContainer {
            outlineContent
        }
        .frame(width: 280)
        .frame(maxHeight: viewportSize.height - 120)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.2), radius: 12, x: 2, y: 0)
    }
    
    private var outlineContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 14))
                Text("Outline")
                    .font(.headline)
                Spacer()
                
                // Collapse button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isCollapsed.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Hide Outline")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(headerBackground)
            
            Divider()
            
            // Outline content - wrapped in NSScrollView to properly capture scroll events
            OutlineScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    let outlineTree = buildOutlineTree()
                    ForEach(Array(outlineTree.enumerated()), id: \.element.id) { index, outlineNode in
                        OutlineItemView(
                            outlineNode: outlineNode,
                            selectedNodeId: viewModel.selectedNodeId,
                            hoveredNodeId: $hoveredNodeId,
                            onNavigate: { navigateToNode($0) },
                            isDraggable: true,
                            isDropTarget: dropTargetIndex == index
                        )
                        .onDrag {
                            draggedNodeId = outlineNode.id
                            let provider = NSItemProvider()
                            provider.suggestedName = outlineNode.node.title.isEmpty ? "Untitled" : outlineNode.node.title
                            provider.registerDataRepresentation(forTypeIdentifier: UTType.text.identifier, visibility: .all) { completion in
                                let data = outlineNode.id.uuidString.data(using: .utf8) ?? Data()
                                completion(data, nil)
                                return nil
                            }
                            return provider
                        }
                        .onDrop(of: [.text], delegate: DropViewDelegate(
                            destinationIndex: index,
                            outlineNodes: outlineTree.map { $0.node },
                            draggedNodeId: $draggedNodeId,
                            dropTargetIndex: $dropTargetIndex,
                            viewModel: viewModel
                        ))
                    }
                    
                    if viewModel.nodes.isEmpty {
                        Text("No nodes yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    }
                    
                    // Spacer at bottom to ensure last item is fully clickable
                    // Need enough space so the last item isn't at the very bottom edge
                    Spacer()
                        .frame(height: 40)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
            }
        }
        .background(panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.3), lineWidth: 0.5)
        )
    }
    
    // MARK: - Outline Tree Building
    
    private func getRootNodeIds() -> [UUID] {
        let rootNodes = viewModel.nodes.values.filter { node in
            node.parentId == nil || viewModel.nodes[node.parentId!] == nil
        }
        .sorted { node1, node2 in
            // Sort by displayOrder if both have it, otherwise by createdAt
            if let order1 = node1.displayOrder, let order2 = node2.displayOrder {
                return order1 < order2
            } else if node1.displayOrder != nil {
                return true
            } else if node2.displayOrder != nil {
                return false
            }
            return node1.createdAt < node2.createdAt
        }
        return rootNodes.map { $0.id }
    }
    
    private func buildOutlineTree() -> [OutlineNode] {
        // Find root nodes (nodes without parents or with non-existent parents)
        let rootNodes = viewModel.nodes.values.filter { node in
            node.parentId == nil || viewModel.nodes[node.parentId!] == nil
        }
        .sorted { node1, node2 in
            // Sort by displayOrder if both have it, otherwise by createdAt
            if let order1 = node1.displayOrder, let order2 = node2.displayOrder {
                return order1 < order2
            } else if node1.displayOrder != nil {
                return true
            } else if node2.displayOrder != nil {
                return false
            }
            return node1.createdAt < node2.createdAt
        }
        
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
    let isDraggable: Bool
    let isDropTarget: Bool
    
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
                
                // Bullet/icon
                if outlineNode.node.type == .note {
                    Image(systemName: "note.text")
                        .font(.system(size: 10))
                        .foregroundColor(nodeColor)
                } else if outlineNode.node.type == .text || outlineNode.node.type == .title {
                    Text("T")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(nodeColor)
                } else {
                    Circle()
                        .fill(nodeColor)
                        .frame(width: 6, height: 6)
                }
                
                // Node title
                Text(nodeTitle)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Spacer()
                
                // Drag indicator for root-level draggable items
                if isDraggable && outlineNode.level == 0 {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                }
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
            
            // Children (recursive) - not draggable as they're connected
            if isExpanded {
                ForEach(outlineNode.children) { child in
                    OutlineItemView(
                        outlineNode: child,
                        selectedNodeId: selectedNodeId,
                        hoveredNodeId: $hoveredNodeId,
                        onNavigate: onNavigate,
                        isDraggable: false,
                        isDropTarget: false
                    )
                }
            }
        }
    }
    
    private var nodeTitle: String {
        // For regular nodes, use the title
        if !outlineNode.node.title.isEmpty {
            return outlineNode.node.title
        }
        
        // For text/title nodes without a title, show preview of description (which holds the text content)
        if outlineNode.node.type == .text || outlineNode.node.type == .title {
            let text = outlineNode.node.description.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                // Show first 30 characters with ellipsis if longer
                if text.count > 30 {
                    return String(text.prefix(30)) + "..."
                }
                return text
            }
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
        } else if isDropTarget {
            Color.blue.opacity(0.2)
        } else if isHovered {
            Color.gray.opacity(colorScheme == .dark ? 0.2 : 0.1)
        } else {
            Color.clear
        }
    }
}

// MARK: - Drop Delegate

private struct DropViewDelegate: DropDelegate {
    let destinationIndex: Int
    let outlineNodes: [Node]
    @Binding var draggedNodeId: UUID?
    @Binding var dropTargetIndex: Int?
    let viewModel: CanvasViewModel
    
    func dropEntered(info: DropInfo) {
        dropTargetIndex = destinationIndex
    }
    
    func dropExited(info: DropInfo) {
        dropTargetIndex = nil
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        // Return move operation to prevent the plus icon (copy indicator)
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedNodeId = nil
            dropTargetIndex = nil
        }
        
        guard let draggedId = draggedNodeId else { return false }
        guard let sourceIndex = outlineNodes.firstIndex(where: { $0.id == draggedId }) else { return false }
        
        // Don't allow dropping on self
        if sourceIndex == destinationIndex {
            return false
        }
        
        // Reorder nodes
        viewModel.reorderNode(draggedId, from: sourceIndex, to: destinationIndex, in: outlineNodes.map { $0.id })
        
        return true
    }
}
