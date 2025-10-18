//
//  CanvasView.swift
//  JamAI
//
//  Main infinite canvas view with pan/zoom and node rendering
//

import SwiftUI

// FocusedValue key for canvas view model
struct CanvasViewModelKey: FocusedValueKey {
    typealias Value = CanvasViewModel
}

extension FocusedValues {
    var canvasViewModel: CanvasViewModel? {
        get { self[CanvasViewModelKey.self] }
        set { self[CanvasViewModelKey.self] = newValue }
    }
}

struct CanvasView: View {
    @ObservedObject var viewModel: CanvasViewModel
    var onCommandClose: (() -> Void)? = nil
    
    @StateObject private var modalCoordinator = ModalCoordinator()
    
    @GestureState private var canvasDragStart: CGSize? = nil
    @State private var lastZoom: CGFloat = 1.0
    @State private var draggedNodeId: UUID? = nil
    @State private var dragStartPosition: CGPoint = .zero
    @State private var mouseLocation: CGPoint = .zero
    @State private var isResizingActive: Bool = false
    @State private var showOutline: Bool = true
    @State private var viewportSize: CGSize = .zero
    
    // Local zoom state for smooth gesture tracking
    @State private var isZooming: Bool = false
    @State private var gestureZoom: CGFloat = 1.0
    @State private var gestureOffset: CGSize = .zero
    @State private var gestureStartZoom: CGFloat = 1.0
    @State private var gestureStartOffset: CGSize = .zero
    @State private var zoomStartLocation: CGPoint = .zero
    
    // Cached node frames to avoid rebuilding on every render
    @State private var cachedNodeFrames: [UUID: CGRect] = [:]
    @State private var lastFrameUpdateVersion: Int = -1
    
    @Environment(\.colorScheme) var colorScheme
    
    // Computed once per render - safer than @State modification
    // Pre-sorted by creation date so WorldLayerView doesn't need to sort every frame
    private var nodesArray: [Node] { 
        Array(viewModel.nodes.values).sorted(by: { $0.createdAt < $1.createdAt })
    }
    private var edgesArray: [Edge] { Array(viewModel.edges.values) }
    
    // Viewport culling: only render visible nodes (with generous margin)
    private var visibleNodes: [Node] {
        // Disable culling during navigation to prevent pop-in
        guard !viewModel.isNavigating else { return nodesArray }
        
        // Add 40% margin to viewport bounds to prevent pop-in during pan/zoom
        let margin: CGFloat = 0.4
        let zoom = currentZoom
        let offset = currentOffset
        
        let cullLeft = -viewportSize.width * margin
        let cullRight = viewportSize.width * (1 + margin)
        let cullTop = -viewportSize.height * margin
        let cullBottom = viewportSize.height * (1 + margin)
        
        return nodesArray.filter { node in
            // Calculate screen position and size
            let screenX = node.x * zoom + offset.width
            let screenY = node.y * zoom + offset.height
            let screenW = node.width * zoom
            let screenH = node.height * zoom
            
            // Check if node intersects viewport (with margin)
            return screenX + screenW >= cullLeft &&
                   screenX <= cullRight &&
                   screenY + screenH >= cullTop &&
                   screenY <= cullBottom
        }
    }
    
    // Smart edge culling: render edge if either endpoint is visible
    private var visibleEdges: [Edge] {
        guard !viewModel.isNavigating else { return edgesArray }
        
        let visibleNodeIds = Set(visibleNodes.map { $0.id })
        return edgesArray.filter { edge in
            visibleNodeIds.contains(edge.sourceId) || visibleNodeIds.contains(edge.targetId)
        }
    }
    
    // Use local gesture state during zoom, otherwise use viewModel values
    private var currentZoom: CGFloat { isZooming ? gestureZoom : viewModel.zoom }
    private var currentOffset: CGSize { isZooming ? gestureOffset : viewModel.offset }

    var body: some View {
        canvasContent
            .focusedValue(\.canvasViewModel, viewModel)
            .environmentObject(modalCoordinator)
    }
    
    private var canvasContent: some View {
        GeometryReader { geometry in
            canvasWithInteractions(geometry: geometry)
        }
        .canvasKeyboardHandlers(viewModel)
    }
    
    @ViewBuilder
    private func canvasWithInteractions(geometry: GeometryProxy) -> some View {
        let _ = DispatchQueue.main.async { 
            self.viewportSize = geometry.size
            self.viewModel.viewportSize = geometry.size
        }
        canvasLayers(geometry: geometry)
            // Track mouse and capture two-finger pan scrolling
            .overlay(
                MouseTrackingView(position: $mouseLocation, onScroll: { dx, dy in
                    // Pan the canvas with fingers (Figma-style)
                    guard !isResizingActive else { return }
                    viewModel.offset.width += dx
                    viewModel.offset.height += dy
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
                // Block if modal sheet is open
                if let window = NSApp.mainWindow, !window.sheets.isEmpty {
                    print("[DEBUG CanvasView] Tap blocked - sheet is active, sheets count: \(window.sheets.count)")
                    return
                }
                print("[DEBUG CanvasView] Tap NOT blocked - no sheets")
                // Place annotation if a tool is active; otherwise deselect
                switch viewModel.selectedTool {
                case .text:
                    let canvasPos = screenToCanvas(mouseLocation, in: geometry.size)
                    viewModel.createTextLabel(at: canvasPos)
                    viewModel.selectedTool = .select
                case .select:
                    viewModel.selectedNodeId = nil
                }
            }
            .contextMenu {
                Button("New Node Here") {
                    let centerX = (geometry.size.width / 2 - viewModel.offset.width) / viewModel.zoom
                    let centerY = (geometry.size.height / 2 - viewModel.offset.height) / viewModel.zoom
                    viewModel.createNode(at: CGPoint(x: centerX, y: centerY))
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .updating($canvasDragStart) { value, gestureState, transaction in
                        // Block if modal sheet is open
                        if let window = NSApp.mainWindow, !window.sheets.isEmpty {
                            return
                        }
                        // Store the initial offset when drag starts (only once per gesture)
                        if gestureState == nil {
                            gestureState = viewModel.offset
                        }
                    }
                    .onChanged { value in
                        // Block if modal sheet is open
                        if let window = NSApp.mainWindow, !window.sheets.isEmpty {
                            return
                        }
                        
                        if draggedNodeId == nil && !isResizingActive {
                            // Use the start offset captured by @GestureState
                            let startOffset = canvasDragStart ?? viewModel.offset
                            viewModel.offset = CGSize(
                                width: startOffset.width + value.translation.width,
                                height: startOffset.height + value.translation.height
                            )
                        }
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        // Block if modal sheet is open
                        if let window = NSApp.mainWindow, !window.sheets.isEmpty {
                            return
                        }
                        guard !isResizingActive else { return }
                        
                        // Initialize gesture state on first change
                        if !isZooming {
                            isZooming = true
                            gestureStartZoom = viewModel.zoom
                            gestureStartOffset = viewModel.offset
                            gestureZoom = viewModel.zoom
                            gestureOffset = viewModel.offset
                            zoomStartLocation = mouseLocation
                        }
                        
                        // Cursor-anchored zoom: keep the world point under cursor fixed
                        // Use ORIGINAL captured values for calculation
                        let baseZoom = gestureStartZoom
                        let baseOffset = gestureStartOffset
                        
                        // High sensitivity for fast zooming (was 0.1, now 0.5 for 5× faster)
                        let dampingFactor: CGFloat = 0.5
                        let zoomDelta = (value - 1.0) * dampingFactor
                        let newZoom = max(Config.minZoom, min(Config.maxZoom, baseZoom * (1.0 + zoomDelta)))
                        let s = zoomStartLocation
                        
                        // Calculate world point under cursor using ORIGINAL offset and zoom
                        let wx = (s.x - baseOffset.width) / max(baseZoom, 0.001)
                        let wy = (s.y - baseOffset.height) / max(baseZoom, 0.001)
                        
                        // Update local state only - no viewModel updates during gesture
                        gestureZoom = newZoom
                        gestureOffset = CGSize(
                            width: s.x - wx * newZoom,
                            height: s.y - wy * newZoom
                        )
                    }
                    .onEnded { _ in
                        // Block if modal sheet is open
                        if let window = NSApp.mainWindow, !window.sheets.isEmpty {
                            return
                        }
                        // Only update viewModel once at the end
                        viewModel.zoom = gestureZoom
                        viewModel.offset = gestureOffset
                        lastZoom = gestureZoom
                        isZooming = false
                    }
            )
            .onTapGesture(count: 2) { location in
                // Block if modal sheet is open
                if let window = NSApp.mainWindow, !window.sheets.isEmpty {
                    return
                }
                
                // Double-click to create new node
                let canvasPos = screenToCanvas(location, in: geometry.size)
                viewModel.createNode(at: canvasPos)
            }
            .onAppear {
                lastZoom = viewModel.zoom
                // Create a centered node for new projects once the canvas is laid out
                if viewModel.nodes.isEmpty {
                    // Outline occupies ~280pt width and is inset by 20pt when visible
                    let leftObstruction: CGFloat = showOutline ? (280 + 20) : 0
                    // Center of the visible canvas area in screen coordinates
                    let screenCenter = CGPoint(
                        x: leftObstruction + (geometry.size.width - leftObstruction) / 2,
                        y: geometry.size.height / 2
                    )
                    // Convert to world/canvas coordinates
                    let worldCenter = screenToCanvas(screenCenter, in: geometry.size)
                    // Adjust so that the node's center lands at the visible center
                    let topLeft = CGPoint(
                        x: worldCenter.x - Node.nodeWidth / 2,
                        y: worldCenter.y - Node.expandedHeight / 2
                    )
                    viewModel.createNode(at: topLeft)
                }
            }
            .onChange(of: viewModel.zoom) { oldValue, newValue in
                lastZoom = newValue
            }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private func canvasLayers(geometry: GeometryProxy) -> some View {
        ZStack {
            // Background
            WorldBackgroundLayer(
                zoom: currentZoom,
                offset: currentOffset,
                showDots: viewModel.showDots
            )
            .equatable()  // Only redraws when zoom/offset/showDots change
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Edges - transformed the same way as nodes
            // Only renders visible edges (connected to visible nodes)
            // Use compositingGroup + drawingGroup for GPU acceleration without clipping
            EdgeLayer(
                edges: visibleEdges,
                frames: nodeFrames
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .compositingGroup()  // Flatten the layer hierarchy first
            .scaleEffect(currentZoom, anchor: .topLeading)
            .offset(currentOffset)
            .drawingGroup(opaque: false, colorMode: .nonLinear)  // Rasterize after transforms
            .allowsHitTesting(false)
            
            // Nodes - only renders visible nodes (viewport culling with 40% margin)
            WorldLayerView(
                nodes: visibleNodes,
                nodeViewBuilder: { node in AnyView(nodeItemView(node)) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .scaleEffect(currentZoom, anchor: .topLeading)
            .offset(currentOffset)
            
            // Toolbar overlay
            overlayControls
            
            // Outline
            VStack(alignment: .leading) {
                Spacer().frame(height: 56)  // Space for tab bar (36) + padding (20)
                HStack(alignment: .top, spacing: 0) {
                    if showOutline {
                        OutlineView(viewModel: viewModel, viewportSize: geometry.size, isCollapsed: $showOutline)
                            .padding(.leading, 20)
                    } else {
                        // Collapsed state - show expand button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showOutline = true
                            }
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: "sidebar.left")
                                    .font(.system(size: 14))
                                Text("Outline")
                                    .font(.caption2)
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                            .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.leading, 20)
                        .help("Show Outline")
                    }
                    Spacer()
                }
                Spacer()
            }
        }
    }
    
    private var overlayControls: some View {
        ZStack {
            // Contextual formatting bar for text/shape (centered bottom)
            VStack {
                Spacer()
                if let binding = formattingBinding {
                    HStack {
                        Spacer()
                        FormattingBarView(node: binding)
                            .allowsHitTesting(true)
                        Spacer()
                    }
                    .padding(.bottom, 20)
                }
            }
            
            // Background toggle (bottom right, always visible)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    BackgroundToggleView(showDots: Binding(
                        get: { viewModel.showDots },
                        set: { viewModel.showDots = $0 }
                    ))
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .allowsHitTesting(true)
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
    
    
    // MARK: - Helpers
    
    private func binding(for nodeId: UUID) -> Binding<Node> {
        Binding(
            get: { viewModel.nodes[nodeId] ?? Node(projectId: viewModel.project.id) },
            set: { viewModel.updateNode($0) }
        )
    }

    private var formattingBinding: Binding<Node>? {
        guard let id = viewModel.selectedNodeId, let node = viewModel.nodes[id] else { return nil }
        guard node.type == .text else { return nil }
        return binding(for: id)
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
            onPromptSubmit: { prompt, imageData, imageMimeType in handlePromptSubmit(prompt, imageData: imageData, imageMimeType: imageMimeType, for: node.id) },
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
            onWidthChange: { width in handleWidthChange(width, for: node.id) },
            onResizeActiveChanged: { active in isResizingActive = active },
            onMaximizeAndCenter: { handleMaximizeAndCenter(for: node.id) },
            onTeamMemberChange: { member in handleTeamMemberChange(member, for: node.id) }
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
            let worldDelta = CGSize(
                width: value.translation.width / viewModel.zoom,
                height: value.translation.height / viewModel.zoom
            )
            let newPosition = CGPoint(
                x: dragStartPosition.x + worldDelta.width,
                y: dragStartPosition.y + worldDelta.height
            )
            // Update position optimistically - UI updates immediately, DB write is debounced
            viewModel.moveNode(nodeId, to: newPosition)
        }
    }
    
    private func handlePromptSubmit(_ prompt: String, imageData: Data?, imageMimeType: String?, for nodeId: UUID) {
        viewModel.generateResponse(for: nodeId, prompt: prompt, imageData: imageData, imageMimeType: imageMimeType)
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
        // Skip if no real change to avoid thrashing updates
        if node.description == description {
            return
        }
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
    
    private func handleWidthChange(_ width: CGFloat, for nodeId: UUID) {
        guard var node = viewModel.nodes[nodeId] else { return }
        node.width = width
        viewModel.updateNode(node, immediate: true)
    }
    
    private func handleMaximizeAndCenter(for nodeId: UUID) {
        viewModel.toggleNodeSize(nodeId, viewportSize: viewportSize)
    }
    
    private func handleTeamMemberChange(_ member: TeamMember?, for nodeId: UUID) {
        guard var node = viewModel.nodes[nodeId] else { return }
        node.setTeamMember(member)
        viewModel.updateNode(node)
    }
    
    // Frames for nodes in world coordinates (before pan/zoom)
    // Cached to avoid rebuilding on every render - only updates when positions change
    private var nodeFrames: [UUID: CGRect] {
        // Only rebuild if positions have changed
        if lastFrameUpdateVersion != viewModel.positionsVersion {
            var map: [UUID: CGRect] = [:]
            for node in viewModel.nodes.values {
                map[node.id] = CGRect(x: node.x, y: node.y, width: node.width, height: node.height)
            }
            // Update cache in next render cycle to avoid state modification during body
            DispatchQueue.main.async {
                self.cachedNodeFrames = map
                self.lastFrameUpdateVersion = viewModel.positionsVersion
            }
            return map
        }
        return cachedNodeFrames
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
    }
    
    private func zoomIn() {
        zoomToCenter(newZoom: min(Config.maxZoom, viewModel.zoom + 0.1))
    }
    
    private func zoomOut() {
        zoomToCenter(newZoom: max(Config.minZoom, viewModel.zoom - 0.1))
    }
    
    private func zoomToCenter(newZoom: CGFloat) {
        let oldZoom = viewModel.zoom
        // Calculate viewport center
        let centerX = viewportSize.width / 2
        let centerY = viewportSize.height / 2
        // Calculate world point at viewport center before zoom
        let worldX = (centerX - viewModel.offset.width) / max(oldZoom, 0.001)
        let worldY = (centerY - viewModel.offset.height) / max(oldZoom, 0.001)
        // Calculate new offset to keep that world point at viewport center after zoom
        let newOffset = CGSize(
            width: centerX - worldX * newZoom,
            height: centerY - worldY * newZoom
        )
        
        withAnimation(.easeOut(duration: 0.2)) {
            viewModel.zoom = newZoom
            viewModel.offset = newOffset
            lastZoom = newZoom
        }
    }
    
    // MARK: - Styling
    
    private var canvasBackground: Color {
        colorScheme == .dark
            ? Color(nsColor: .windowBackgroundColor)
            : Color(white: 0.95)
    }
    
    
    private var gridColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.05)
            : Color.black.opacity(0.05)
    }
}

// MARK: - View Extensions
extension View {
    @ViewBuilder
    func canvasKeyboardHandlers(_ viewModel: CanvasViewModel) -> some View {
        self
            .onKeyPress(.escape) {
                viewModel.selectedTool = .select
                viewModel.selectedNodeId = nil
                return .handled
            }
            .onKeyPress("n") {
                // Only create new node when no nodes are selected
                guard viewModel.selectedNodeId == nil else { return .ignored }
                
                // Calculate center of visible canvas area (accounting for outline if shown)
                // Note: We can't access geometry or showOutline here, so we approximate
                // Default window is 1200x800, tab bar is ~36, outline is ~300 when visible
                let viewportWidth: CGFloat = 1200
                let viewportHeight: CGFloat = 800
                let tabBarHeight: CGFloat = 36
                let outlineWidth: CGFloat = 0  // Approximate, we don't know if it's shown
                
                // Screen center
                let screenCenterX = outlineWidth + (viewportWidth - outlineWidth) / 2
                let screenCenterY = tabBarHeight + (viewportHeight - tabBarHeight) / 2
                
                // Convert screen to canvas coordinates
                let canvasCenterX = (screenCenterX - viewModel.offset.width) / viewModel.zoom
                let canvasCenterY = (screenCenterY - viewModel.offset.height) / viewModel.zoom
                
                // Adjust for node size so it appears centered
                let nodeX = canvasCenterX - Node.nodeWidth / 2
                let nodeY = canvasCenterY - Node.expandedHeight / 2
                
                viewModel.createNode(at: CGPoint(x: nodeX, y: nodeY))
                return .handled
            }
            // Undo/Redo through key events - alternative approach
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        // This doesn't prevent other gestures but ensures canvas is focused
                    }
            )
    }
}
