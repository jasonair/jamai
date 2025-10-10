//
//  CanvasView.swift
//  JamAI
//
//  Main infinite canvas view with pan/zoom and node rendering
//

import SwiftUI

struct CanvasView: View {
    @ObservedObject var viewModel: CanvasViewModel
    
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var draggedNodeId: UUID?
    @State private var dragStartPosition: CGPoint = .zero
    @State private var lastZoom: CGFloat = 1.0
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background grid
                gridBackground
                
                // Edges layer
                EdgeLayer(
                    edges: Array(viewModel.edges.values),
                    nodes: viewModel.nodes,
                    zoom: viewModel.zoom
                )
                .offset(viewModel.offset)
                .scaleEffect(viewModel.zoom)
                
                // Nodes
                ForEach(Array(viewModel.nodes.values), id: \.id) { node in
                    NodeView(
                        node: binding(for: node.id),
                        isSelected: viewModel.selectedNodeId == node.id,
                        isGenerating: viewModel.generatingNodeId == node.id,
                        onTap: {
                            viewModel.selectedNodeId = node.id
                        },
                        onPromptSubmit: { prompt in
                            handlePromptSubmit(prompt, for: node.id)
                        },
                        onTitleEdit: { title in
                            handleTitleEdit(title, for: node.id)
                        },
                        onDescriptionEdit: { description in
                            handleDescriptionEdit(description, for: node.id)
                        },
                        onDelete: {
                            handleDeleteNode(node.id)
                        },
                        onCreateChild: {
                            handleCreateChildNode(node.id)
                        }
                    )
                    .position(
                        x: node.x + Node.nodeWidth / 2,
                        y: node.y + (node.isExpanded ? Node.expandedHeight : Node.collapsedHeight) / 2
                    )
                    .offset(viewModel.offset)
                    .scaleEffect(viewModel.zoom)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                handleNodeDrag(node.id, value: value)
                            }
                            .onEnded { _ in
                                draggedNodeId = nil
                            }
                    )
                }
                
                // Toolbar overlay
                VStack {
                    toolbar
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(canvasBackground)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if draggedNodeId == nil {
                            viewModel.offset = CGSize(
                                width: dragOffset.width + value.translation.width,
                                height: dragOffset.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { _ in
                        dragOffset = viewModel.offset
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let newZoom = max(Config.minZoom, min(Config.maxZoom, value))
                        
                        // Adjust offset to zoom from center
                        let zoomDelta = newZoom / lastZoom
                        let centerX = geometry.size.width / 2
                        let centerY = geometry.size.height / 2
                        
                        viewModel.offset.width = centerX + (viewModel.offset.width - centerX) * zoomDelta
                        viewModel.offset.height = centerY + (viewModel.offset.height - centerY) * zoomDelta
                        
                        viewModel.zoom = newZoom
                        lastZoom = newZoom
                    }
                    .onEnded { _ in
                        lastZoom = viewModel.zoom
                        dragOffset = viewModel.offset
                    }
            )
            .onTapGesture(count: 2) { location in
                // Double-click to create new node
                let canvasPos = screenToCanvas(location, in: geometry.size)
                viewModel.createNode(at: canvasPos)
            }
        }
        .onAppear {
            dragOffset = viewModel.offset
            lastZoom = viewModel.zoom
        }
    }
    
    // MARK: - Subviews
    
    private var toolbar: some View {
        HStack(spacing: 16) {
            // Undo/Redo
            Button(action: { viewModel.undo() }) {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!viewModel.undoManager.canUndo)
            
            Button(action: { viewModel.redo() }) {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!viewModel.undoManager.canRedo)
            
            Divider()
                .frame(height: 20)
            
            // Zoom controls
            Button(action: { viewModel.zoom = max(Config.minZoom, viewModel.zoom - 0.1) }) {
                Image(systemName: "minus.magnifyingglass")
            }
            
            Text("\(Int(viewModel.zoom * 100))%")
                .font(.caption)
                .frame(width: 50)
            
            Button(action: { viewModel.zoom = min(Config.maxZoom, viewModel.zoom + 0.1) }) {
                Image(systemName: "plus.magnifyingglass")
            }
            
            Button(action: { viewModel.zoom = Config.defaultZoom }) {
                Image(systemName: "1.magnifyingglass")
            }
            
            Divider()
                .frame(height: 20)
            
            // New node
            Button(action: {
                viewModel.createNode(at: CGPoint(x: -viewModel.offset.width, y: -viewModel.offset.height))
            }) {
                Label("New Node", systemImage: "plus.circle.fill")
            }
            
            Spacer()
            
            // Project name
            Text(viewModel.project.name)
                .font(.headline)
            
            Spacer()
            
            // Status indicator removed - now shown in individual nodes
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(toolbarBackground)
        .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
    }
    
    private var gridBackground: some View {
        Canvas { context, size in
            let gridSize = Config.gridSize * viewModel.zoom
            let offsetX = viewModel.offset.width.truncatingRemainder(dividingBy: gridSize)
            let offsetY = viewModel.offset.height.truncatingRemainder(dividingBy: gridSize)
            
            // Vertical lines
            var x = offsetX
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(gridColor), lineWidth: 1)
                x += gridSize
            }
            
            // Horizontal lines
            var y = offsetY
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(gridColor), lineWidth: 1)
                y += gridSize
            }
        }
    }
    
    // MARK: - Helpers
    
    private func binding(for nodeId: UUID) -> Binding<Node> {
        Binding(
            get: { viewModel.nodes[nodeId] ?? Node(projectId: viewModel.project.id) },
            set: { viewModel.updateNode($0) }
        )
    }
    
    private func handleNodeDrag(_ nodeId: UUID, value: DragGesture.Value) {
        if draggedNodeId == nil {
            draggedNodeId = nodeId
            if let node = viewModel.nodes[nodeId] {
                dragStartPosition = CGPoint(x: node.x, y: node.y)
            }
        }
        
        if draggedNodeId == nodeId {
            let newPosition = CGPoint(
                x: dragStartPosition.x + value.translation.width / viewModel.zoom,
                y: dragStartPosition.y + value.translation.height / viewModel.zoom
            )
            viewModel.moveNode(nodeId, to: newPosition)
        }
    }
    
    private func handlePromptSubmit(_ prompt: String, for nodeId: UUID) {
        viewModel.generateResponse(for: nodeId, prompt: prompt)
    }
    
    private func handleDeleteNode(_ nodeId: UUID) {
        viewModel.deleteNode(nodeId)
        // Deselect if this was the selected node
        if viewModel.selectedNodeId == nodeId {
            viewModel.selectedNodeId = nil
        }
    }
    
    private func handleCreateChildNode(_ nodeId: UUID) {
        viewModel.createChildNode(parentId: nodeId)
    }
    
    private func handleTitleEdit(_ title: String, for nodeId: UUID) {
        guard var node = viewModel.nodes[nodeId] else { return }
        node.title = title
        node.titleSource = .user
        viewModel.updateNode(node)
    }
    
    private func handleDescriptionEdit(_ description: String, for nodeId: UUID) {
        guard var node = viewModel.nodes[nodeId] else { return }
        node.description = description
        node.descriptionSource = .user
        viewModel.updateNode(node)
    }
    
    private func screenToCanvas(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x - viewModel.offset.width) / viewModel.zoom,
            y: (point.y - viewModel.offset.height) / viewModel.zoom
        )
    }
    
    private func adjustZoom(to newZoom: CGFloat, viewSize: CGSize) {
        let oldZoom = viewModel.zoom
        let zoomDelta = newZoom / oldZoom
        let centerX = viewSize.width / 2
        let centerY = viewSize.height / 2
        
        viewModel.offset.width = centerX + (viewModel.offset.width - centerX) * zoomDelta
        viewModel.offset.height = centerY + (viewModel.offset.height - centerY) * zoomDelta
        
        viewModel.zoom = newZoom
        lastZoom = newZoom
        dragOffset = viewModel.offset
    }
    
    // MARK: - Styling
    
    private var canvasBackground: Color {
        colorScheme == .dark
            ? Color(nsColor: .windowBackgroundColor)
            : Color(white: 0.95)
    }
    
    private var toolbarBackground: some View {
        colorScheme == .dark
            ? Color(nsColor: .controlBackgroundColor)
            : Color.white
    }
    
    private var gridColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.05)
            : Color.black.opacity(0.05)
    }
}
