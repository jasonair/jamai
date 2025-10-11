//
//  CanvasView.swift
//  JamAI
//
//  Main infinite canvas view with pan/zoom and node rendering
//

import SwiftUI

struct CanvasView: View {
    @ObservedObject var viewModel: CanvasViewModel
    var onCommandClose: (() -> Void)? = nil
    
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var draggedNodeId: UUID?
    @State private var dragStartPosition: CGPoint = .zero
    @State private var lastZoom: CGFloat = 1.0
    // No live layout frames; we compute from model
    @State private var mouseLocation: CGPoint = .zero
    @State private var isResizingActive: Bool = false
    @State private var showOutline: Bool = true
    
    @Environment(\.colorScheme) var colorScheme
    
    // Precomputed helpers to reduce type-checking complexity
    private var edgesArray: [Edge] { Array(viewModel.edges.values) }
    private var nodesArray: [Node] { Array(viewModel.nodes.values) }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background (screen space, world-aligned tiling)
                WorldBackgroundLayer(
                    zoom: viewModel.zoom,
                    offset: viewModel.offset,
                    showDots: viewModel.showDots
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Full-screen edges overlay (renders in screen coords)
                EdgeLayer(
                    edges: edgesArray,
                    frames: nodeFrames,
                    zoom: viewModel.zoom,
                    offset: viewModel.offset
                )
                .id("edges-\(viewModel.positionsVersion)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                
                // World container: edges + nodes share the same transform
                WorldLayerView(
                    nodes: nodesArray,
                    nodeViewBuilder: { node in AnyView(nodeItemView(node)) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .scaleEffect(viewModel.zoom, anchor: .topLeading)
                .offset(viewModel.offset)
                
                // Toolbar overlay
                VStack {
                    toolbar
                    Spacer()
                    HStack {
                        Spacer()
                        gridToggle
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                    }
                }
                
                // Outline panel overlay (left side)
                if showOutline {
                    VStack(alignment: .leading) {
                        Spacer()
                            .frame(height: 80)
                        HStack(alignment: .top, spacing: 0) {
                            OutlineView(viewModel: viewModel, viewportSize: geometry.size)
                                .padding(.leading, 20)
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
            // Track mouse and capture two-finger pan scrolling
            .overlay(
                MouseTrackingView(position: $mouseLocation, onScroll: { dx, dy in
                    // Pan the canvas with fingers (Figma-style)
                    guard !isResizingActive else { return }
                    viewModel.offset.width += dx
                    viewModel.offset.height += dy
                    dragOffset = viewModel.offset
                }, onCommandClose: {
                    onCommandClose?()
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(canvasBackground)
            .contentShape(Rectangle())
            .onTapGesture {
                // Tap on background to deselect all nodes
                viewModel.selectedNodeId = nil
            }
            .contextMenu {
                Button("New Node Here") {
                    let centerX = (geometry.size.width / 2 - viewModel.offset.width) / viewModel.zoom
                    let centerY = (geometry.size.height / 2 - viewModel.offset.height) / viewModel.zoom
                    viewModel.createNode(at: CGPoint(x: centerX, y: centerY))
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        if draggedNodeId == nil && !isResizingActive {
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
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        guard !isResizingActive else { return }
                        // Cursor-anchored zoom: keep the world point under cursor fixed
                        let oldZoom = viewModel.zoom
                        let newZoom = max(Config.minZoom, min(Config.maxZoom, lastZoom * value))
                        let s = mouseLocation
                        // world point under cursor before zoom
                        let wx = (s.x - viewModel.offset.width) / max(oldZoom, 0.001)
                        let wy = (s.y - viewModel.offset.height) / max(oldZoom, 0.001)
                        let newOffset = CGSize(
                            width: s.x - wx * newZoom,
                            height: s.y - wy * newZoom
                        )
                        viewModel.zoom = newZoom
                        viewModel.offset = newOffset
                        dragOffset = newOffset
                    }
                    .onEnded { _ in
                        lastZoom = viewModel.zoom
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
            // Left section: Outline, Undo/Redo and Zoom controls
            HStack(spacing: 16) {
                // Outline toggle
                Button(action: { 
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showOutline.toggle()
                    }
                }) {
                    Image(systemName: showOutline ? "sidebar.left" : "sidebar.left.slash")
                        .foregroundColor(showOutline ? .accentColor : .secondary)
                }
                .help("Toggle Outline")
                
                Divider()
                    .frame(height: 20)
                
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
                
                Button(action: {
                    viewModel.zoom = Config.defaultZoom
                    lastZoom = viewModel.zoom
                }) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
            }
            
            Spacer()
            
            // Center: Project name
            Text(viewModel.project.name)
                .font(.headline)
            
            Spacer()
            
            // Right section: New node button
            Button(action: {
                // Create node at canvas origin (0,0) - user can drag to reposition
                // Or we estimate viewport center without needing geometry
                let centerX = -viewModel.offset.width / viewModel.zoom
                let centerY = -viewModel.offset.height / viewModel.zoom
                viewModel.createNode(at: CGPoint(x: centerX, y: centerY))
            }) {
                Label("New Node", systemImage: "plus.circle.fill")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(toolbarBackground)
        .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
    }
    
    private var dotBackground: some View {
        Canvas { context, size in
            let dotSize: CGFloat = 2
            let spacing = Config.gridSize
            let scaledSpacing = spacing * viewModel.zoom
            let centerX = size.width / 2
            let centerY = size.height / 2
            // Center-anchored transform: screen = C + (world - C) * z + offset * z
            // Tiled offset shift in screen space:
            var startX = ((1 - viewModel.zoom) * centerX + viewModel.offset.width * viewModel.zoom)
                .truncatingRemainder(dividingBy: scaledSpacing)
            var startY = ((1 - viewModel.zoom) * centerY + viewModel.offset.height * viewModel.zoom)
                .truncatingRemainder(dividingBy: scaledSpacing)
            if startX < 0 { startX += scaledSpacing }
            if startY < 0 { startY += scaledSpacing }
            
            var y = startY
            while y < size.height {
                var x = startX
                while x < size.width {
                    let rect = CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: rect), with: .color(gridColor))
                    x += scaledSpacing
                }
                y += scaledSpacing
            }
        }
    }
    
    private var gridBackground: some View {
        Canvas { context, size in
            let gridSize = Config.gridSize
            let scaledGridSize = gridSize * viewModel.zoom
            let centerX = size.width / 2
            let centerY = size.height / 2
            var startX = ((1 - viewModel.zoom) * centerX + viewModel.offset.width * viewModel.zoom)
                .truncatingRemainder(dividingBy: scaledGridSize)
            var startY = ((1 - viewModel.zoom) * centerY + viewModel.offset.height * viewModel.zoom)
                .truncatingRemainder(dividingBy: scaledGridSize)
            if startX < 0 { startX += scaledGridSize }
            if startY < 0 { startY += scaledGridSize }
            
            // Vertical lines
            var x = startX
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(gridColor), lineWidth: 1)
                x += scaledGridSize
            }
            
            // Horizontal lines
            var y = startY
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(gridColor), lineWidth: 1)
                y += scaledGridSize
            }
        }
    }
    
    private var gridToggle: some View {
        Button(action: {
            viewModel.showDots.toggle()
        }) {
            HStack(spacing: 6) {
                Image(systemName: viewModel.showDots ? "circle.grid.3x3.fill" : "square.grid.3x3.fill")
                    .font(.system(size: 14))
                Text(viewModel.showDots ? "Dots" : "Grid")
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(toolbarBackground)
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helpers
    
    private func binding(for nodeId: UUID) -> Binding<Node> {
        Binding(
            get: { viewModel.nodes[nodeId] ?? Node(projectId: viewModel.project.id) },
            set: { viewModel.updateNode($0) }
        )
    }

    private var backgroundLayer: AnyView {
        if viewModel.showDots { return AnyView(dotBackground) }
        else { return AnyView(gridBackground) }
    }

    @ViewBuilder
    private func nodeItemView(_ node: Node) -> some View {
        NodeItemWrapper(
            node: binding(for: node.id),
            isSelected: viewModel.selectedNodeId == node.id,
            isGenerating: viewModel.generatingNodeId == node.id,
            onTap: { viewModel.selectedNodeId = node.id },
            onPromptSubmit: { prompt in handlePromptSubmit(prompt, for: node.id) },
            onTitleEdit: { title in handleTitleEdit(title, for: node.id) },
            onDescriptionEdit: { desc in handleDescriptionEdit(desc, for: node.id) },
            onDelete: { handleDeleteNode(node.id) },
            onCreateChild: { handleCreateChildNode(node.id) },
            onColorChange: { colorId in handleColorChange(colorId, for: node.id) },
            onExpandSelection: { selectedText in handleExpandSelection(selectedText, for: node.id) },
            onMakeNote: { selectedText in handleMakeNote(selectedText, for: node.id) },
            onJamWithThis: { selectedText in handleJamWithThis(selectedText, for: node.id) },
            onExpandNote: { handleExpandNote(for: node.id) },
            onDragChanged: { value in handleNodeDrag(node.id, value: value) },
            onDragEnded: { draggedNodeId = nil },
            onHeightChange: { height in handleHeightChange(height, for: node.id) },
            onResizeActiveChanged: { active in isResizingActive = active }
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
            // Update position optimistically - UI updates immediately, DB write is debounced
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
    
    private func handleColorChange(_ colorId: String, for nodeId: UUID) {
        guard var node = viewModel.nodes[nodeId] else { return }
        node.color = colorId
        viewModel.updateNode(node)
        
        // Update all outgoing edges to match the new node color
        let edgeColor = colorId != "none" ? colorId : nil
        for (_, var edge) in viewModel.edges where edge.sourceId == nodeId {
            edge.color = edgeColor
            viewModel.updateEdge(edge)
        }
    }
    
    private func handleExpandSelection(_ selectedText: String, for nodeId: UUID) {
        viewModel.expandSelectedText(parentId: nodeId, selectedText: selectedText)
    }

    private func handleMakeNote(_ selectedText: String, for nodeId: UUID) {
        viewModel.createNoteFromSelection(parentId: nodeId, selectedText: selectedText)
    }

    private func handleExpandNote(for nodeId: UUID) {
        viewModel.expandFromNote(noteId: nodeId)
    }

    private func handleJamWithThis(_ selectedText: String, for nodeId: UUID) {
        viewModel.jamWithSelectedText(parentId: nodeId, selectedText: selectedText)
    }
    
    private func handleHeightChange(_ height: CGFloat, for nodeId: UUID) {
        guard var node = viewModel.nodes[nodeId] else { return }
        node.height = height
        viewModel.updateNode(node, immediate: true)
    }
    
    // Frames for nodes in world coordinates (before pan/zoom)
    private var nodeFrames: [UUID: CGRect] {
        var map: [UUID: CGRect] = [:]
        for node in viewModel.nodes.values {
            let height = node.isExpanded ? node.height : Node.collapsedHeight
            let width = Node.width(for: node.type)
            map[node.id] = CGRect(x: node.x, y: node.y, width: width, height: height)
        }
        return map
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
