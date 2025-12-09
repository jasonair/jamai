//
//  CanvasViewModel.swift
//  JamAI
//
//  Main view model coordinating canvas state and operations
//

import Foundation
import SwiftUI
import Combine
import AppKit
import FirebaseAuth

@MainActor
class CanvasViewModel: ObservableObject {
    // MARK: - Published State
    
    @Published var project: Project
    @Published var nodes: [UUID: Node] = [:]
    @Published var edges: [UUID: Edge] = [:]
    @Published var selectedNodeId: UUID? {
        didSet {
            // Clear unread indicator when node is selected
            if let nodeId = selectedNodeId {
                nodesWithUnreadResponse.remove(nodeId)
            }
        }
    }
    @Published var generatingNodeId: UUID?
    @Published var errorNodeId: UUID? // Node that encountered an error during generation
    @Published var nodesWithUnreadResponse: Set<UUID> = [] // Nodes with new AI responses not yet viewed
    @Published var errorMessage: String?
    @Published var orchestratingNodeIds: Set<UUID> = [] // Nodes involved in active orchestration
    
    // Credit error state - published so NodeView can show inline message
    @Published var creditErrorNodeId: UUID? // Node where credit error occurred
    @Published var creditCheckResult: CreditCheckResult? // Last credit check result for UI display
    
    // Canvas state
    @Published var offset: CGSize = .zero
    @Published var zoom: CGFloat = Config.defaultZoom
    @Published var showDots: Bool = false
    @Published var backgroundStyle: CanvasBackgroundStyle = .blank {
        didSet {
            showDots = (backgroundStyle == .dots)
        }
    }
    @Published var backgroundColorId: String? = nil
    @Published var positionsVersion: Int = 0 // increment to force connector refresh
    @Published var isNavigating: Bool = false // true during animated navigation
    @Published var isZooming: Bool = false // true during active zoom gesture for performance optimization
    @Published var isPanning: Bool = false // true during active pan gesture for performance optimization
    @Published var selectedTool: CanvasTool = .select
    @Published var viewportSize: CGSize = CGSize(width: 1200, height: 800) // updated by CanvasView
    @Published var mousePosition: CGPoint = .zero // updated by CanvasView, in screen coordinates
    @Published var zOrder: [UUID: Double] = [:]
    private var zCounter: Double = 0
    
    // Manual wiring state
    @Published var isWiring: Bool = false
    @Published var wireSourceNodeId: UUID?
    @Published var wireSourceSide: ConnectionSide?
    @Published var wireEndPoint: CGPoint? // Mouse position during drag (in canvas coordinates)
    @Published var hoveredNodeId: UUID? // Node currently hovered for connection point visibility
    
    // Multi-select state
    @Published var selectedNodeIds: Set<UUID> = []  // Multiple selected nodes (shift-click)
    @Published var isShiftPressed: Bool = false  // Track shift key state
    
    // Snap-to-align state
    @Published var snapGuides: [SnapGuide] = []  // Active snap guide lines to display
    @Published var isSnapEnabled: Bool = Config.snapEnabled  // Can be toggled by user
    @Published var isControlPressed: Bool = false  // Control key temporarily disables snapping
    
    // Forward undo manager state for UI binding
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    
    // Search
    @Published var searchHighlight: NodeSearchHighlight?
    let searchIndex = ConversationSearchIndex()
    lazy var searchViewModel: ConversationSearchViewModel = {
        let vm = ConversationSearchViewModel(index: searchIndex)
        vm.onSelectResult = { [weak self] result in
            self?.handleSearchResultSelected(result)
        }
        return vm
    }()
    
    // Services
    let geminiClient: GeminiClient
    let ragService: RAGService
    let embeddingService: NodeEmbeddingService
    let database: Database
    let dbActor: DatabaseActor
    let undoManager: CanvasUndoManager
    
    // Project URL for backup service
    var projectURL: URL?
    
    private var cancellables = Set<AnyCancellable>()
    private var autosaveTimer: Timer?
    
    // Debounced write queue
    private var pendingNodeWrites: Set<UUID> = []
    private var pendingEdgeWrites: Set<UUID> = []
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.3 // 300ms debounce
    
    // MARK: - Initialization
    
    init(project: Project, database: Database) {
        self.project = project
        self.database = database
        self.dbActor = DatabaseActor(db: database)
        self.geminiClient = GeminiClient()
        self.ragService = RAGService(geminiClient: geminiClient, database: database)
        self.embeddingService = NodeEmbeddingService(geminiClient: geminiClient)
        self.undoManager = CanvasUndoManager()
        if AIProviderManager.shared.activeProvider == .local {
            let model = AIProviderManager.shared.activeModelName ?? AIProviderManager.availableLocalModels.first
            if let name = model {
                AIProviderManager.shared.setClient(LlamaCppClient(modelId: name))
            } else {
                AIProviderManager.shared.setClient(LlamaCppClient(modelId: "deepseek-r1:1.5b"))
            }
        } else {
            AIProviderManager.shared.setClient(GeminiClientAdapter(geminiClient: geminiClient))
        }
        Task { await AIProviderManager.shared.refreshHealth() }
        
        // Forward undo manager state changes with logging
        undoManager.$canUndo
            .sink { [weak self] value in
                if Config.enableVerboseLogging { print("🟢 ViewModel: canUndo changed to \(value)") }
                self?.canUndo = value
                // Force UI update
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        undoManager.$canRedo
            .sink { [weak self] value in
                if Config.enableVerboseLogging { print("🟢 ViewModel: canRedo changed to \(value)") }
                self?.canRedo = value
                // Force UI update
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        loadProjectData()
        setupAutosave()
    }
    
    deinit {
        // Cleanup GeminiClient to prevent hanging on app quit
        autosaveTimer?.invalidate()
    }

    func createNoteFromSelection(parentId: UUID, selectedText: String) {
        guard let parent = nodes[parentId] else { return }
        let noteCountBefore = self.nodes.values.filter { $0.type == .note }.count
        if Config.enableVerboseLogging { print("📝 [NoteCreate] begin parent=\(parentId) notes_before=\(noteCountBefore) len=\(selectedText.count)") }

        let noteX = parent.x + parent.width + 50
        let noteY = parent.y + 40
        
        // Inherit color from parent node (including "none" for default styling)
        let inheritedColor = parent.color
        
        var note = Node(
            projectId: project.id,
            parentId: parentId,
            x: noteX,
            y: noteY,
            height: Node.noteWidth,
            title: "Note",
            titleSource: .user,
            description: selectedText,
            descriptionSource: .user,
            isExpanded: true,
            isFrozenContext: false,
            color: inheritedColor,
            type: .note
        )
        var ancestry = parent.ancestry
        ancestry.append(parentId)
        note.setAncestry(ancestry)
        note.systemPromptSnapshot = self.project.systemPrompt
        if Config.enableVerboseLogging { print("📝 [NoteCreate] note id=\(note.id) x=\(note.x) y=\(note.y)") }
        
        self.nodes[note.id] = note
        self.bringToFront([note.id])
        self.selectedNodeId = note.id
        self.undoManager.record(.createNode(note))
        
        // Create edge with parent's color
        let parentColor = self.nodes[parentId]?.color
        let edgeColor = (parentColor != nil && parentColor != "none") ? parentColor : nil
        let edge = Edge(projectId: self.project.id, sourceId: parentId, targetId: note.id, color: edgeColor)
        self.edges[edge.id] = edge
        self.undoManager.record(.createEdge(edge))
        if Config.enableVerboseLogging { print("📝 [NoteCreate] edge id=\(edge.id) color=\(String(describing: edge.color))") }
        
        // Force edge refresh immediately to ensure wire appears
        Task { @MainActor in
            self.positionsVersion += 1
        }
        
        // Use debounced write system for reliable persistence
        self.scheduleDebouncedWrite(edgeId: edge.id)
        
        // Save node atomically
        let dbActor = self.dbActor
        Task { [dbActor, note] in
            do {
                if Config.enableVerboseLogging { print("📝 [NoteCreate] save begin node=\(note.id)") }
                try await dbActor.saveNode(note)
                if Config.enableVerboseLogging { print("📝 [NoteCreate] save node ok=\(note.id)") }
                
                // Track note creation analytics
                if let userId = FirebaseAuthService.shared.currentUser?.uid {
                    await AnalyticsService.shared.trackNodeCreation(
                        userId: userId,
                        projectId: note.projectId,
                        nodeId: note.id,
                        nodeType: "note",
                        creationMethod: .note,
                        parentNodeId: parentId,
                        teamMemberRoleId: note.teamMember?.roleId
                    )
                }
            } catch {
                if Config.enableVerboseLogging { print("⚠️ Failed to save note: \(error.localizedDescription)") }
            }
        }
    }

    func createTitleLabel(at position: CGPoint) {
        // Defer state changes to avoid publishing during view updates
        // Use .userInitiated QoS to match the calling context and avoid priority inversion
        Task(priority: .userInitiated) { @MainActor in
            let node = Node(
                projectId: self.project.id,
                parentId: nil,
                // For titles, treat x/y as the top-left of the node so the
                // text is visually pinned to the click location.
                x: position.x,
                y: position.y,
                height: 100,
                title: "",
                titleSource: .user,
                description: "",
                descriptionSource: .user,
                isExpanded: false,
                color: "none",
                type: .title,
                fontSize: 48,
                isBold: true,
                fontFamily: nil,
                shapeKind: nil
            )
            self.nodes[node.id] = node
            self.bringToFront([node.id])
            self.selectedNodeId = node.id
            self.undoManager.record(.createNode(node))
            let dbActor = self.dbActor
            Task { [weak self, dbActor, node] in
                do {
                    try await dbActor.saveNode(node)
                } catch {
                    await MainActor.run {
                        self?.errorMessage = "Failed to save title: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    func expandFromNote(noteId: UUID) {
        guard let note = nodes[noteId] else { return }
        let text = note.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        expandSelectedText(parentId: noteId, selectedText: text)
    }
    
    // MARK: - Data Loading
    
    private func loadProjectData() {
        do {
            let loadedNodes = try database.loadNodes(projectId: project.id)
            let loadedEdges = try database.loadEdges(projectId: project.id)
            
            nodes = Dictionary(uniqueKeysWithValues: loadedNodes.map { ($0.id, $0) })
            var initialZ: [UUID: Double] = [:]
            var counter: Double = 0
            for n in loadedNodes.sorted(by: { $0.createdAt < $1.createdAt }) {
                counter += 1
                initialZ[n.id] = counter
            }
            zOrder = initialZ
            zCounter = counter
            
            // Filter out orphaned edges (edges that reference non-existent nodes)
            let validEdges = loadedEdges.filter { edge in
                nodes[edge.sourceId] != nil && nodes[edge.targetId] != nil
            }
            edges = Dictionary(uniqueKeysWithValues: validEdges.map { ($0.id, $0) })
            
            // Clean up orphaned edges from database
            let orphanedEdges = loadedEdges.filter { edge in
                nodes[edge.sourceId] == nil || nodes[edge.targetId] == nil
            }
            if !orphanedEdges.isEmpty {
                let dbActor = self.dbActor
                Task.detached(priority: .utility) { [dbActor, orphanedEdges] in
                    for edge in orphanedEdges {
                        try? await dbActor.deleteEdge(id: edge.id)
                    }
                }
            }
            
            // Restore canvas view state
            offset = CGSize(width: project.canvasOffsetX, height: project.canvasOffsetY)
            zoom = project.canvasZoom
            backgroundStyle = project.backgroundStyle
            backgroundColorId = project.backgroundColorId
            showDots = (backgroundStyle == .dots)
            
            // Force edge refresh to ensure wires render correctly on load
            positionsVersion += 1
            
            // Build search index from loaded nodes
            searchIndex.rebuild(from: Array(nodes.values))
        } catch {
            errorMessage = "Failed to load project: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Node Operations
    
    func calculateCenterPosition(viewportSize: CGSize = CGSize(width: 1200, height: 800)) -> CGPoint {
        // Calculate the canvas center position accounting for offset and zoom
        // Formula from CanvasView contextMenu
        let centerX = (viewportSize.width / 2 - offset.width) / zoom
        let centerY = (viewportSize.height / 2 - offset.height) / zoom
        return CGPoint(x: centerX, y: centerY)
    }
    
    // MARK: - Z-Order
    func zIndex(for id: UUID) -> Double {
        zOrder[id] ?? 0
    }
    
    func bringToFront(_ ids: [UUID]) {
        for id in ids {
            zCounter += 1
            zOrder[id] = zCounter
        }
        objectWillChange.send()
    }
    
    /// Check if a node is the topmost node at a given screen position
    /// Used for z-order-aware hit testing to prevent click-through to lower nodes
    func isTopmostNodeAtPoint(_ nodeId: UUID, screenPoint: CGPoint, viewportSize: CGSize) -> Bool {
        guard let targetNode = nodes[nodeId] else { 
            #if DEBUG
            print("[Z-Order] Node \(nodeId) not found")
            #endif
            return true // Allow tap if node not found (shouldn't happen)
        }
        
        // Convert screen point to canvas coordinates
        let canvasX = (screenPoint.x - offset.width) / zoom
        let canvasY = (screenPoint.y - offset.height) / zoom
        let canvasPoint = CGPoint(x: canvasX, y: canvasY)
        
        #if DEBUG
        print("[Z-Order] Screen: \(screenPoint), Canvas: \(canvasPoint), Offset: \(offset), Zoom: \(zoom)")
        print("[Z-Order] Target node '\(targetNode.title)' at (\(targetNode.x), \(targetNode.y)) size (\(targetNode.width)x\(targetNode.height))")
        #endif
        
        // Find all nodes that contain this canvas point
        let nodesAtPoint = nodes.values.filter { node in
            let frame = CGRect(x: node.x, y: node.y, width: node.width, height: node.height)
            return frame.contains(canvasPoint)
        }
        
        #if DEBUG
        print("[Z-Order] Nodes at point: \(nodesAtPoint.map { $0.title })")
        #endif
        
        // If no overlapping nodes found, allow the tap (TapThroughOverlay already confirmed bounds)
        // This handles coordinate conversion edge cases
        if nodesAtPoint.isEmpty {
            #if DEBUG
            print("[Z-Order] No nodes at canvas point - allowing tap (trusting TapThroughOverlay bounds check)")
            #endif
            return true
        }
        
        // If only this node is at the point, allow tap
        if nodesAtPoint.count == 1 && nodesAtPoint.first?.id == nodeId {
            return true
        }
        
        // Multiple nodes overlap - find the one with highest z-index
        let topmostNode = nodesAtPoint.max { zIndex(for: $0.id) < zIndex(for: $1.id) }
        
        let isTopmost = topmostNode?.id == nodeId
        #if DEBUG
        if !isTopmost {
            print("[Z-Order] BLOCKED - topmost is '\(topmostNode?.title ?? "nil")' with z=\(zIndex(for: topmostNode?.id ?? UUID())), this node z=\(zIndex(for: nodeId))")
        }
        #endif
        
        return isTopmost
    }
    
    /// Get the topmost node ID at a given screen position
    func topmostNodeAtPoint(screenPoint: CGPoint, viewportSize: CGSize) -> UUID? {
        // Convert screen point to canvas coordinates
        let canvasX = (screenPoint.x - offset.width) / zoom
        let canvasY = (screenPoint.y - offset.height) / zoom
        let canvasPoint = CGPoint(x: canvasX, y: canvasY)
        
        // Find all nodes that contain this point
        let nodesAtPoint = nodes.values.filter { node in
            let frame = CGRect(x: node.x, y: node.y, width: node.width, height: node.height)
            return frame.contains(canvasPoint)
        }
        
        // Return the node with highest z-index
        return nodesAtPoint.max { zIndex(for: $0.id) < zIndex(for: $1.id) }?.id
    }
    
    // MARK: - Manual Wiring
    
    /// Start a wiring operation from a connection point
    func startWiring(from nodeId: UUID, side: ConnectionSide) {
        guard nodes[nodeId] != nil else { return }
        isWiring = true
        wireSourceNodeId = nodeId
        wireSourceSide = side
        wireEndPoint = nil
        if Config.enableVerboseLogging {
            print("🔌 Started wiring from node \(nodeId) side \(side)")
        }
    }
    
    /// Update the wire endpoint during drag
    func updateWireEndpoint(_ point: CGPoint) {
        wireEndPoint = point
    }
    
    /// Complete wiring by connecting to a target node
    func completeWiring(to targetNodeId: UUID) {
        guard let sourceId = wireSourceNodeId else {
            resetWiringState()
            return
        }
        
        // Prevent self-connection
        guard sourceId != targetNodeId else {
            if Config.enableVerboseLogging {
                print("🔌 Cannot wire node to itself")
            }
            resetWiringState()
            return
        }
        
        // Prevent duplicate edges (same source → target)
        let existingEdge = edges.values.first { edge in
            edge.sourceId == sourceId && edge.targetId == targetNodeId
        }
        guard existingEdge == nil else {
            if Config.enableVerboseLogging {
                print("🔌 Edge already exists between these nodes")
            }
            resetWiringState()
            return
        }
        
        // Get source node color for the edge
        let sourceColor = nodes[sourceId]?.color
        let edgeColor = (sourceColor != nil && sourceColor != "none") ? sourceColor : nil
        
        // Create the edge
        let edge = Edge(
            projectId: project.id,
            sourceId: sourceId,
            targetId: targetNodeId,
            color: edgeColor
        )
        
        edges[edge.id] = edge
        undoManager.record(.createEdge(edge))
        
        // Save edge IMMEDIATELY (not debounced) to prevent loss on quick quit
        let dbActor = self.dbActor
        Task { [dbActor, edge] in
            try? await dbActor.saveEdge(edge)
            if Config.enableVerboseLogging {
                print("🔌 Edge saved to database: \(edge.id)")
            }
        }
        
        // Force edge refresh
        positionsVersion += 1
        
        if Config.enableVerboseLogging {
            print("🔌 Created edge from \(sourceId) to \(targetNodeId)")
        }
        
        resetWiringState()
    }
    
    /// Cancel the current wiring operation
    func cancelWiring() {
        if Config.enableVerboseLogging && isWiring {
            print("🔌 Wiring cancelled")
        }
        resetWiringState()
    }
    
    /// Reset all wiring state
    private func resetWiringState() {
        isWiring = false
        wireSourceNodeId = nil
        wireSourceSide = nil
        wireEndPoint = nil
    }
    
    /// Find node at a given canvas position (for drop target detection)
    func nodeAt(canvasPosition: CGPoint) -> UUID? {
        for (id, node) in nodes {
            let frame = CGRect(
                x: node.x,
                y: node.y,
                width: node.width,
                height: node.height
            )
            if frame.contains(canvasPosition) {
                return id
            }
        }
        return nil
    }
    
    /// Check if a node has a connection on a specific side
    func hasConnection(nodeId: UUID, side: ConnectionSide) -> Bool {
        guard let node = nodes[nodeId] else { return false }
        let nodeFrame = CGRect(x: node.x, y: node.y, width: node.width, height: node.height)
        
        for edge in edges.values {
            // Check if this node is the source
            if edge.sourceId == nodeId {
                guard let targetNode = nodes[edge.targetId] else { continue }
                let targetFrame = CGRect(x: targetNode.x, y: targetNode.y, width: targetNode.width, height: targetNode.height)
                let exitSide = determineExitSide(from: nodeFrame, to: targetFrame)
                if exitSide == side {
                    return true
                }
            }
            // Check if this node is the target
            if edge.targetId == nodeId {
                guard let sourceNode = nodes[edge.sourceId] else { continue }
                let sourceFrame = CGRect(x: sourceNode.x, y: sourceNode.y, width: sourceNode.width, height: sourceNode.height)
                let entrySide = determineEntrySide(from: sourceFrame, to: nodeFrame)
                if entrySide == side {
                    return true
                }
            }
        }
        return false
    }
    
    /// Determine which side an edge exits from the source node
    private func determineExitSide(from source: CGRect, to target: CGRect) -> ConnectionSide {
        let sc = CGPoint(x: source.midX, y: source.midY)
        let tc = CGPoint(x: target.midX, y: target.midY)
        let dx = tc.x - sc.x
        let dy = tc.y - sc.y
        
        if abs(dx) >= abs(dy) {
            return dx >= 0 ? .right : .left
        } else {
            return dy >= 0 ? .bottom : .top
        }
    }
    
    /// Determine which side an edge enters the target node
    private func determineEntrySide(from source: CGRect, to target: CGRect) -> ConnectionSide {
        let sc = CGPoint(x: source.midX, y: source.midY)
        let tc = CGPoint(x: target.midX, y: target.midY)
        let dx = tc.x - sc.x
        let dy = tc.y - sc.y
        
        if abs(dx) >= abs(dy) {
            return dx >= 0 ? .left : .right
        } else {
            return dy >= 0 ? .top : .bottom
        }
    }
    
    /// Delete all edges connected to a node on a specific side
    func deleteEdgesForNode(_ nodeId: UUID, side: ConnectionSide) {
        guard let node = nodes[nodeId] else { return }
        let nodeFrame = CGRect(x: node.x, y: node.y, width: node.width, height: node.height)
        
        var edgesToDelete: [Edge] = []
        
        for edge in edges.values {
            // Check if this node is the source and the edge exits from this side
            if edge.sourceId == nodeId {
                guard let targetNode = nodes[edge.targetId] else { continue }
                let targetFrame = CGRect(x: targetNode.x, y: targetNode.y, width: targetNode.width, height: targetNode.height)
                let exitSide = determineExitSide(from: nodeFrame, to: targetFrame)
                if exitSide == side {
                    edgesToDelete.append(edge)
                }
            }
            // Check if this node is the target and the edge enters from this side
            if edge.targetId == nodeId {
                guard let sourceNode = nodes[edge.sourceId] else { continue }
                let sourceFrame = CGRect(x: sourceNode.x, y: sourceNode.y, width: sourceNode.width, height: sourceNode.height)
                let entrySide = determineEntrySide(from: sourceFrame, to: nodeFrame)
                if entrySide == side {
                    edgesToDelete.append(edge)
                }
            }
        }
        
        for edge in edgesToDelete {
            edges.removeValue(forKey: edge.id)
            pendingEdgeWrites.remove(edge.id)
            undoManager.record(.deleteEdge(edge))
            
            // Delete from database
            let dbActor = self.dbActor
            Task { [dbActor, edgeId = edge.id] in
                try? await dbActor.deleteEdge(id: edgeId)
            }
            
            if Config.enableVerboseLogging {
                print("🔌 Deleted edge \(edge.id)")
            }
        }
        
        // Force edge refresh
        positionsVersion += 1
    }
    
    func createNode(at position: CGPoint, parentId: UUID? = nil, inheritContext: Bool = false) {
        // Defer state changes to avoid publishing during view updates
        // Use .userInitiated QoS to match the calling context and avoid priority inversion
        Task(priority: .userInitiated) { @MainActor in
            _ = self.createNodeImmediate(at: position, parentId: parentId, inheritContext: inheritContext)
        }
    }
    
    /// Creates a new node at the specified position and navigates to center it in viewport
    /// Used by right-click context menu to create node at cursor then focus on it
    func createNodeAndNavigate(at position: CGPoint, viewportSize: CGSize) {
        Task(priority: .userInitiated) { @MainActor in
            let nodeId = self.createNodeImmediate(at: position)
            // Navigate to center the new node in viewport
            self.navigateToNode(nodeId, viewportSize: viewportSize)
        }
    }
    
    /// Creates a new node centered in the viewport and navigates to it
    /// Used by the toolbar + button to create a node in the visible center
    func createNodeCenteredInViewport(viewportSize: CGSize, leftObstruction: CGFloat = 0) {
        Task(priority: .userInitiated) { @MainActor in
            // Calculate visible center accounting for left panel obstruction
            let visibleWidth = viewportSize.width - leftObstruction
            let screenCenterX = leftObstruction + (visibleWidth / 2)
            let screenCenterY = viewportSize.height / 2
            
            // Convert to canvas coordinates
            let canvasCenterX = (screenCenterX - self.offset.width) / self.zoom
            let canvasCenterY = (screenCenterY - self.offset.height) / self.zoom
            
            // Adjust for node size so the node CENTER lands at the visible center
            let nodeTopLeftX = canvasCenterX - Node.nodeWidth / 2
            let nodeTopLeftY = canvasCenterY - Node.expandedHeight / 2
            
            let position = CGPoint(x: nodeTopLeftX, y: nodeTopLeftY)
            let nodeId = self.createNodeImmediate(at: position)
            
            // Navigate to center the new node in viewport
            self.navigateToNode(nodeId, viewportSize: viewportSize)
        }
    }

    @discardableResult
    private func createNodeImmediate(at position: CGPoint, parentId: UUID? = nil, inheritContext: Bool = false) -> UUID {
        var node = Node(
            projectId: self.project.id,
            parentId: parentId,
            x: position.x,
            y: position.y
        )
        
        // Attach default Expert Research Analyst with Generalist personality if none is set
        if node.teamMember == nil {
            if let defaultRole = RoleManager.shared.role(withId: "research-analyst") {
                let member = TeamMember(
                    roleId: defaultRole.id,
                    name: nil,
                    experienceLevel: .expert,
                    promptAddendum: nil,
                    knowledgePackIds: nil
                )
                node.setTeamMember(member)
            }
        }
        node.personality = .balanced
        
        // Set up ancestry, context, and inherit visual styling from parent when present
        if let parentId = parentId, let parent = self.nodes[parentId] {
            var ancestry = parent.ancestry
            ancestry.append(parentId)
            node.setAncestry(ancestry)
            node.systemPromptSnapshot = self.project.systemPrompt

            // Inherit parent node color so branches stay visually grouped
            node.color = parent.color

            // Create edge to parent with parent's color
            let parentColor = parent.color != "none" ? parent.color : nil
            let edge = Edge(projectId: self.project.id, sourceId: parentId, targetId: node.id, color: parentColor)
            self.edges[edge.id] = edge
            self.undoManager.record(.createEdge(edge))
            // Use debounced write system to ensure reliable persistence
            self.scheduleDebouncedWrite(edgeId: edge.id)
        }

        self.nodes[node.id] = node
        self.bringToFront([node.id])
        // Auto-select newly created node
        self.selectedNodeId = node.id
        self.undoManager.record(.createNode(node))
        
        // Force positions refresh so edges render immediately
        self.positionsVersion += 1

        let dbActor = self.dbActor
        Task { [weak self, dbActor, node] in
            do {
                try await dbActor.saveNode(node)
                
                // Track node creation analytics
                if let userId = FirebaseAuthService.shared.currentUser?.uid {
                    await AnalyticsService.shared.trackNodeCreation(
                        userId: userId,
                        projectId: node.projectId,
                        nodeId: node.id,
                        nodeType: "standard",
                        creationMethod: parentId != nil ? .childNode : .manual,
                        parentNodeId: parentId,
                        teamMemberRoleId: node.teamMember?.roleId
                    )
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Failed to save node: \(error.localizedDescription)"
                }
            }
        }

        return node.id
    }
    
    // MARK: - Node Duplication
    func duplicateNode(_ nodeId: UUID) {
        guard let original = nodes[nodeId] else { return }
        
        // Place duplicate to the right of original with 50px gap between them
        let gap: CGFloat = 50
        let newX = original.x + original.width + gap
        
        // Create a new node with a new ID but copy most properties
        let duplicate = Node(
            id: UUID(),
            projectId: original.projectId,
            parentId: original.parentId,
            x: newX,
            y: original.y,
            width: original.width,
            height: original.height,
            title: original.title.isEmpty ? "" : "\(original.title) (Copy)",
            titleSource: original.titleSource,
            description: original.description,
            descriptionSource: original.descriptionSource,
            conversationJSON: original.conversationJSON,
            prompt: original.prompt,
            response: original.response,
            ancestryJSON: original.ancestryJSON,
            summary: original.summary,
            systemPromptSnapshot: original.systemPromptSnapshot,
            teamMemberJSON: original.teamMemberJSON,
            personalityRawValue: original.personalityRawValue,
            isExpanded: original.isExpanded,
            isFrozenContext: original.isFrozenContext,
            color: original.color,
            type: original.type,
            fontSize: original.fontSize,
            isBold: original.isBold,
            fontFamily: original.fontFamily,
            shapeKind: original.shapeKind,
            imageData: original.imageData,
            embeddingJSON: original.embeddingJSON, // Copy embeddings from original
            embeddingUpdatedAt: original.embeddingUpdatedAt,
            displayOrder: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        nodes[duplicate.id] = duplicate
        bringToFront([duplicate.id])
        selectedNodeId = duplicate.id
        undoManager.record(.createNode(duplicate))
        
        // Force positions refresh
        positionsVersion += 1
        
        let dbActor = self.dbActor
        Task { [weak self, dbActor, duplicate] in
            do {
                try await dbActor.saveNode(duplicate)
                
                // Track node creation analytics
                if let userId = FirebaseAuthService.shared.currentUser?.uid {
                    await AnalyticsService.shared.trackNodeCreation(
                        userId: userId,
                        projectId: duplicate.projectId,
                        nodeId: duplicate.id,
                        nodeType: duplicate.type.rawValue,
                        creationMethod: .duplicate,
                        parentNodeId: duplicate.parentId,
                        teamMemberRoleId: duplicate.teamMember?.roleId
                    )
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Failed to save duplicated node: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Annotation Creation
    func createTextLabel(at position: CGPoint) {
        // Defer state changes to avoid publishing during view updates
        // Use .userInitiated QoS to match the calling context and avoid priority inversion
        Task(priority: .userInitiated) { @MainActor in
            let node = Node(
                projectId: self.project.id,
                parentId: nil,
                x: position.x,
                y: position.y,
                height: 60,
                title: "",
                titleSource: .user,
                description: "",
                descriptionSource: .user,
                isExpanded: false,
                color: "none",
                type: .text,
                fontSize: 18,
                isBold: false,
                fontFamily: nil,
                shapeKind: nil
            )
            self.nodes[node.id] = node
            self.bringToFront([node.id])
            self.selectedNodeId = node.id
            self.undoManager.record(.createNode(node))
            let dbActor = self.dbActor
            Task { [weak self, dbActor, node] in
                do { try await dbActor.saveNode(node) }
                catch {
                    await MainActor.run { self?.errorMessage = "Failed to save text: \(error.localizedDescription)" }
                }
            }
        }
    }

    func createFreeformNote(at position: CGPoint) {
        // Defer state changes to avoid publishing during view updates
        // Use .userInitiated QoS to match the calling context and avoid priority inversion
        Task(priority: .userInitiated) { @MainActor in
            var note = Node(
                projectId: self.project.id,
                parentId: nil,
                x: position.x,
                y: position.y,
                height: Node.noteWidth,
                title: "Note",
                titleSource: .user,
                description: "",
                descriptionSource: .user,
                isExpanded: true,
                isFrozenContext: false,
                color: "none",
                type: .note
            )
            note.systemPromptSnapshot = self.project.systemPrompt
            self.nodes[note.id] = note
            self.bringToFront([note.id])
            self.selectedNodeId = note.id
            self.undoManager.record(.createNode(note))

            let dbActor = self.dbActor
            Task { [weak self, dbActor, note] in
                do {
                    try await dbActor.saveNode(note)

                    // Track note creation analytics
                    if let userId = FirebaseAuthService.shared.currentUser?.uid {
                        await AnalyticsService.shared.trackNodeCreation(
                            userId: userId,
                            projectId: note.projectId,
                            nodeId: note.id,
                            nodeType: "note",
                            creationMethod: .note,
                            parentNodeId: nil,
                            teamMemberRoleId: note.teamMember?.roleId
                        )
                    }
                } catch {
                    await MainActor.run {
                        self?.errorMessage = "Failed to save note: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    func createShape(at position: CGPoint, kind: ShapeKind) {
        // Defer state changes to avoid publishing during view updates
        // Use .userInitiated QoS to match the calling context and avoid priority inversion
        Task(priority: .userInitiated) { @MainActor in
            let node = Node(
                projectId: self.project.id,
                parentId: nil,
                x: position.x,
                y: position.y,
                height: 120,
                title: "",
                titleSource: .user,
                description: "",
                descriptionSource: .user,
                isExpanded: false,
                color: "lightGray",
                type: .shape,
                fontSize: 16,
                isBold: false,
                fontFamily: nil,
                shapeKind: kind
            )
            self.nodes[node.id] = node
            self.bringToFront([node.id])
            self.selectedNodeId = node.id
            self.undoManager.record(.createNode(node))
            let dbActor = self.dbActor
            Task { [weak self, dbActor, node] in
                do { try await dbActor.saveNode(node) }
                catch {
                    await MainActor.run { self?.errorMessage = "Failed to save shape: \(error.localizedDescription)" }
                }
            }
        }
    }
    
    // MARK: - Image Paste
    func pasteImageFromClipboard(at position: CGPoint? = nil) {
        let pasteboard = NSPasteboard.general
        
        // Check if clipboard contains an image
        guard let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage else {
            return
        }
        
        guard let tiffData = image.tiffRepresentation else {
            return
        }
        
        guard let bitmap = NSBitmapImageRep(data: tiffData) else {
            return
        }
        
        guard let imageData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }
        
        // Determine position - use provided position or convert mouse position to canvas coordinates
        let nodePosition: CGPoint
        if let position = position {
            nodePosition = position
        } else {
            // Convert screen coordinates (mousePosition) to canvas coordinates
            // Formula: canvasCoord = (screenCoord - offset) / zoom
            let canvasX = (mousePosition.x - offset.width) / zoom
            let canvasY = (mousePosition.y - offset.height) / zoom
            nodePosition = CGPoint(x: canvasX, y: canvasY)
        }
        
        // Calculate image dimensions while maintaining aspect ratio
        let imageSize = image.size
        let maxDimension: CGFloat = 400
        var width = imageSize.width
        var height = imageSize.height
        
        if width > maxDimension || height > maxDimension {
            let aspectRatio = width / height
            if width > height {
                width = maxDimension
                height = maxDimension / aspectRatio
            } else {
                height = maxDimension
                width = maxDimension * aspectRatio
            }
        }
        
        // Create image node
        Task(priority: .userInitiated) { @MainActor in
            let node = Node(
                projectId: self.project.id,
                parentId: nil,
                x: nodePosition.x,
                y: nodePosition.y,
                width: width,
                height: height,
                title: "",
                titleSource: .user,
                description: "",
                descriptionSource: .user,
                isExpanded: false,
                color: "none",
                type: .image,
                imageData: imageData
            )
            
            self.nodes[node.id] = node
            self.bringToFront([node.id])
            self.selectedNodeId = node.id
            self.undoManager.record(.createNode(node))
            
            let dbActor = self.dbActor
            Task { [weak self, dbActor, node] in
                do {
                    try await dbActor.saveNode(node)
                } catch {
                    await MainActor.run {
                        self?.errorMessage = "Failed to save image: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    func createChildNode(parentId: UUID) {
        guard let parent = nodes[parentId] else { return }
        
        // Calculate position for child node (offset to the right and down)
        let childX = parent.x + parent.width + 50
        let childY = parent.y + 100
        
        // Create branch without inheriting conversation (inheritContext: false)
        // The parent's summary will be used as context instead
        let childId = createNodeImmediate(at: CGPoint(x: childX, y: childY), parentId: parentId, inheritContext: false)
        
        // Inherit team member from parent if present
        if let parentTeamMember = parent.teamMember {
            if var child = nodes[childId] {
                child.setTeamMember(parentTeamMember)
                updateNode(child, immediate: true)
            }
        }
        
        // Generate TLDR summary asynchronously to provide context for the branch
        Task {
            await generateTLDRSummary(for: parent.id)
        }
    }
    
    func expandSelectedText(parentId: UUID, selectedText: String) {
        guard let parent = nodes[parentId] else { return }
        
        // Calculate position for child node (offset to the right and down)
        let childX = parent.x + parent.width + 50
        let childY = parent.y + 100
        
        // Create branch without inheriting conversation immediately to avoid race with async creation
        let childId = createNodeImmediate(at: CGPoint(x: childX, y: childY), parentId: parentId, inheritContext: false)
        
        // Inherit team member from parent if present
        if let parentTeamMember = parent.teamMember {
            if var child = nodes[childId] {
                child.setTeamMember(parentTeamMember)
                updateNode(child, immediate: true)
            }
        }
        
        // Indicate generation immediately so UI shows spinner
        generatingNodeId = childId
        
        // Start tasks in parallel: title generation + TLDR context
        Task { [weak self] in
            guard let self = self else { return }
            await self.autoGenerateTitleFromSelectedText(for: childId, selectedText: selectedText)
        }
        Task { [weak self] in
            guard let self = self else { return }
            await self.generateTLDRSummary(for: parent.id)
        }
        
        // Build context-aware prompt for expansion (this won't be shown to user)
        let expansionPrompt = "Expand on this: \"\(selectedText)\". Provide a short, concise explanation with additional context."
        
        // Generate response without adding the prompt to conversation first
        Task { @MainActor [weak self] in
            self?.generateExpandedResponse(for: childId, prompt: expansionPrompt, selectedText: selectedText)

            // Track expand action analytics
            if let userId = FirebaseAuthService.shared.currentUser?.uid {
                await FirebaseDataService.shared.incrementUserMetadata(userId: userId, field: "totalExpandActions")
            }
        }
    }

    func jamWithSelectedText(parentId: UUID, selectedText: String) {
        guard let parent = nodes[parentId] else { return }
        
        // Calculate position for child node (offset to the right and down)
        let childX = parent.x + parent.width + 50
        let childY = parent.y + 100
        
        // Create branch immediately to avoid race; do not inherit conversation
        let childId = createNodeImmediate(at: CGPoint(x: childX, y: childY), parentId: parentId, inheritContext: false)
        
        // Get the newly created child
        guard var child = self.nodes[childId] else { return }
        
        // Inherit team member from parent if present
        if let parentTeamMember = parent.teamMember {
            child.setTeamMember(parentTeamMember)
        }
        
        // Set selected text as description; no auto response
        child.description = selectedText
        child.descriptionSource = .user
        child.prompt = ""
        child.response = ""
        updateNode(child, immediate: true)
        
        // Auto-generate a concise title from the selected text
        Task { [weak self] in
            await self?.autoGenerateTitleFromSelectedText(for: childId, selectedText: selectedText)
        }
        
        // Prepare context for future conversations: TLDR parent
        Task { [weak self] in
            await self?.generateTLDRSummary(for: parentId)
        }
    }
    

    private func generateExpandedResponse(for nodeId: UUID, prompt: String, selectedText: String) {
        guard let node = nodes[nodeId] else { return }
        
        // Check credits for cloud providers
        if AIProviderManager.shared.activeProvider != .local {
            let result = CreditTracker.shared.checkCredits()
            if !result.allowed {
                // Set credit error state for this node so UI can show inline message
                creditErrorNodeId = nodeId
                creditCheckResult = result
                errorMessage = result.userMessage
                return
            }
        }
        
        // Clear any previous credit error for this node
        if creditErrorNodeId == nodeId {
            creditErrorNodeId = nil
            creditCheckResult = nil
        }
        
        generatingNodeId = nodeId
        
        // Capture team member info for this response BEFORE async work
        let teamMemberRoleId = node.teamMember?.roleId
        let teamMemberRoleName: String?
        if let teamMember = node.teamMember,
           let role = RoleManager.shared.roles.first(where: { $0.id == teamMember.roleId }) {
            teamMemberRoleName = role.name
        } else {
            teamMemberRoleName = nil
        }
        let teamMemberExperienceLevel = node.teamMember?.experienceLevel.rawValue
        
        // Do not store user prompt; expansions keep the conversation clean
        
        Task { [teamMemberRoleId, teamMemberRoleName, teamMemberExperienceLevel] in
            do {
                let aiContext = self.buildAIContext(for: node)
                let contextTextsForBilling = aiContext.map { $0.content }
                var streamedResponse = ""
                
                // Assemble system prompt - use team member's prompt if available
                let baseSystemPrompt = node.systemPromptSnapshot ?? project.systemPrompt
                let effectiveBaseSystemPrompt: String
                if AIProviderManager.shared.activeProvider == .local {
                    effectiveBaseSystemPrompt = baseSystemPrompt + "\n\nWhen answering, be concise and concrete. Focus on specific numbers, tradeoffs, and examples. Base your answer primarily on the most recent user message, and treat earlier messages only as background context. Avoid repeating the same high-level outline in every reply."
                } else {
                    effectiveBaseSystemPrompt = baseSystemPrompt
                }
                let finalSystemPrompt: String
                if let teamMember = node.teamMember,
                   let role = RoleManager.shared.roles.first(where: { $0.id == teamMember.roleId }) {
                    finalSystemPrompt = teamMember.assembleSystemPrompt(
                        with: role,
                        personality: node.personality,
                        baseSystemPrompt: effectiveBaseSystemPrompt
                    )
                    
                    // Track team member usage in generation
                    self.trackTeamMemberUsage(
                        nodeId: nodeId,
                        roleId: role.id,
                        roleName: role.name,
                        roleCategory: role.category.rawValue,
                        experienceLevel: teamMember.experienceLevel.rawValue,
                        actionType: .used
                    )
                } else {
                    finalSystemPrompt = effectiveBaseSystemPrompt
                }
                
                AIProviderManager.shared.client?.generateStreaming(
                    prompt: prompt,
                    systemPrompt: finalSystemPrompt,
                    context: aiContext,
                    onChunk: { [weak self] chunk in
                        Task { @MainActor in
                            streamedResponse += chunk
                            // Temporarily show streaming response
                            guard var currentNode = self?.nodes[nodeId] else { return }
                            currentNode.response = streamedResponse
                            self?.nodes[nodeId] = currentNode
                        }
                    },
                    onComplete: { [weak self] result in
                        Task { @MainActor in
                            self?.generatingNodeId = nil
                            // Also clear from orchestrating set if present (cleanup for edge cases)
                            self?.orchestratingNodeIds.remove(nodeId)
                            
                            switch result {
                            case .success(let fullResponse):
                                guard var finalNode = self?.nodes[nodeId] else { return }
                                // Only add assistant response to conversation (not the prompt) with team member info
                                finalNode.addMessage(
                                    role: .assistant,
                                    content: fullResponse,
                                    teamMemberRoleId: teamMemberRoleId,
                                    teamMemberRoleName: teamMemberRoleName,
                                    teamMemberExperienceLevel: teamMemberExperienceLevel
                                )
                                finalNode.response = fullResponse
                                finalNode.updatedAt = Date()
                                self?.nodes[nodeId] = finalNode
                                if let dbActor = self?.dbActor {
                                    Task { [dbActor, finalNode] in
                                        try? await dbActor.saveNode(finalNode)
                                    }
                                }
                                
                                // Mark as unread if node is not currently selected
                                if self?.selectedNodeId != nodeId {
                                    self?.nodesWithUnreadResponse.insert(nodeId)
                                }
                                
                                // Track credit usage and analytics (backend handles actual deduction)
                                if AIProviderManager.shared.activeProvider != .local {
                                    await CreditTracker.shared.trackGeneration(
                                        promptText: prompt,
                                        responseText: fullResponse,
                                        contextTexts: contextTextsForBilling,
                                        nodeId: nodeId,
                                        projectId: self?.project.id ?? UUID(),
                                        teamMemberRoleId: finalNode.teamMember?.roleId,
                                        teamMemberExperienceLevel: finalNode.teamMember?.experienceLevel.rawValue,
                                        generationType: "expand"
                                    )
                                }
                                
                                // Auto-generate title based on selected text
                                await self?.autoGenerateTitleForExpansion(for: nodeId, selectedText: selectedText)
                                
                            case .failure(let error):
                                self?.errorNodeId = nodeId
                                self?.errorMessage = error.localizedDescription
                                // Clear error state after brief display
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    if self?.errorNodeId == nodeId {
                                        self?.errorNodeId = nil
                                    }
                                }
                            }
                        }
                    }
                )
            }
        }
    }
    
    private func autoGenerateTitleFromSelectedText(for nodeId: UUID, selectedText: String) async {
        guard var node = nodes[nodeId] else { return }
        do {
            let prompt = "Create a short, clear title (max 40 chars) based only on this text: \"\(selectedText)\". Return only the title."
            guard let client = AIProviderManager.shared.client else { return }
            let result = try await client.generate(
                prompt: prompt,
                systemPrompt: "You are a helpful assistant that writes concise, descriptive titles.",
                context: []
            )
            let title = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                node.title = String(title.prefix(40))
                node.titleSource = .ai
                updateNode(node, immediate: true)
            }
        } catch {
            // Non-fatal if title generation fails
        }
    }
    
    private func autoGenerateTitleForExpansion(for nodeId: UUID, selectedText: String) async {
        // Backwards-compatible helper that now only auto-generates a title for expansion nodes.
        guard var node = nodes[nodeId] else { return }
        guard node.title.isEmpty else { return }
        
        do {
            let prompt = """
            Based on this expansion request about "\(selectedText)", and the response:
            \(node.response)
            
            Generate a concise title (max 50 chars).
            Return only the title text.
            """
            
            guard let client = AIProviderManager.shared.client else { return }
            let result = try await client.generate(
                prompt: prompt,
                systemPrompt: "You are a helpful assistant that creates concise titles.",
                context: []
            )
            
            let trimmedTitle = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                node.title = String(trimmedTitle.prefix(50))
                node.titleSource = .ai
            }
            
            updateNode(node, immediate: true)
        } catch {
            if Config.enableVerboseLogging { print("Failed to auto-generate title: \(error)") }
        }
    }
    
    private func generateTLDRSummary(for parentId: UUID) async {
        guard var parent = nodes[parentId] else { return }
        
        // Get the last few conversation turns
        let recentConversation = Array(parent.conversation.suffix(6)) // Last 3 exchanges
        
        if recentConversation.isEmpty {
            return
        }
        
        // Build summary prompt
        var conversationText = ""
        for msg in recentConversation {
            let role = msg.role == .user ? "User" : "Jam"
            conversationText += "\(role): \(msg.content)\n\n"
        }
        
        let prompt = """
        Provide a concise TLDR summary (2-3 sentences max) of this conversation context:
        
        \(conversationText)
        
        Focus on key points and decisions. This will be used as hidden context for branching conversations.
        """
        
        do {
            let summary = try await geminiClient.generate(
                prompt: prompt,
                systemPrompt: "You are a helpful assistant that creates concise summaries."
            )
            
            parent.summary = summary
            nodes[parentId] = parent
            let dbActor = self.dbActor
            Task { [weak self, dbActor, parent] in
                do {
                    try await dbActor.saveNode(parent)
                } catch {
                    await MainActor.run {
                        self?.errorMessage = "Failed to save summary: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            if Config.enableVerboseLogging { print("Failed to generate TLDR summary: \(error)") }
        }
    }
    
    func updateNode(_ node: Node, immediate: Bool = false) {
        guard let oldNode = nodes[node.id] else { return }
        
        var updatedNode = node
        updatedNode.updatedAt = Date()
        if Config.enableVerboseLogging && updatedNode.type == .note {
            print("📝 [NoteUpdate] node=\(updatedNode.id) immediate=\(immediate) desc_len=\(updatedNode.description.count)")
        }
        
        // Explicitly trigger objectWillChange before mutation
        objectWillChange.send()
        nodes[node.id] = updatedNode
        
        // If geometry changed, force an edge refresh immediately
        let geometryChanged =
            oldNode.x != updatedNode.x ||
            oldNode.y != updatedNode.y ||
            oldNode.width != updatedNode.width ||
            oldNode.height != updatedNode.height
        if geometryChanged {
            positionsVersion &+= 1
        }
        
        undoManager.record(.updateNode(oldNode: oldNode, newNode: updatedNode))
        
        // Check if a team member was removed
        if oldNode.teamMember != nil && updatedNode.teamMember == nil {
            if let userId = FirebaseAuthService.shared.currentUser?.uid {
                Task {
                    await FirebaseDataService.shared.decrementUserMetadata(userId: userId, field: "totalTeamMembersUsed")
                }
            }
        }
        
        // Update search index if content changed
        let contentChanged = oldNode.title != updatedNode.title ||
            oldNode.description != updatedNode.description ||
            oldNode.conversationJSON != updatedNode.conversationJSON
        if contentChanged {
            searchIndex.indexNode(updatedNode)
        } else if geometryChanged {
            // Just update metadata (position) if only geometry changed
            searchIndex.updateNodeMetadata(updatedNode)
        }

        // Debounce database write unless immediate
        if immediate {
            let dbActor = self.dbActor
            Task { [weak self, dbActor, updatedNode] in
                do {
                    try await dbActor.saveNode(updatedNode)
                } catch {
                    await MainActor.run {
                        self?.errorMessage = "Failed to update node: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            scheduleDebouncedWrite(nodeId: node.id)
        }
    }

    // Live geometry update during resize/drag: no DB, no undo — just refresh edges immediately
    func updateNodeGeometryDuringDrag(_ nodeId: UUID, width: CGFloat?, height: CGFloat?) {
        guard var node = nodes[nodeId] else { return }
        var changed = false
        if let w = width, w != node.width { node.width = w; changed = true }
        if let h = height, h != node.height { node.height = h; changed = true }
        guard changed else { return }
        objectWillChange.send()
        nodes[nodeId] = node
        positionsVersion &+= 1
    }
    
    func updateEdge(_ edge: Edge, immediate: Bool = false) {
        guard edges[edge.id] != nil else { return }
        
        // Explicitly trigger objectWillChange before mutation
        objectWillChange.send()
        edges[edge.id] = edge
        positionsVersion += 1
        
        // Always use debounced write for reliable persistence
        scheduleDebouncedWrite(edgeId: edge.id)
    }
    
    /// Add a new edge to the canvas
    func addEdge(_ edge: Edge) {
        // Prevent duplicate edges
        let existingEdge = edges.values.first { 
            $0.sourceId == edge.sourceId && $0.targetId == edge.targetId 
        }
        guard existingEdge == nil else { return }
        
        objectWillChange.send()
        edges[edge.id] = edge
        undoManager.record(.createEdge(edge))
        positionsVersion += 1
        
        // Use debounced write for reliable persistence
        scheduleDebouncedWrite(edgeId: edge.id)
    }
    
    func deleteNode(_ nodeId: UUID) {
        guard let node = nodes[nodeId] else { return }
        
        // Delete connected edges (remove from pending writes and schedule deletion)
        let connectedEdges = edges.values.filter { $0.sourceId == nodeId || $0.targetId == nodeId }
        for edge in connectedEdges {
            edges.removeValue(forKey: edge.id)
            // Remove from pending writes if queued
            pendingEdgeWrites.remove(edge.id)
            // Immediate delete for node deletion
            let dbActor = self.dbActor
            Task { [dbActor, edgeId = edge.id] in
                try? await dbActor.deleteEdge(id: edgeId)
            }
        }
        
        nodes.removeValue(forKey: nodeId)
        
        // Remove from search index
        searchIndex.removeNode(nodeId: nodeId)
        
        // Record node deletion with connected edges for proper undo
        undoManager.record(.deleteNode(node, connectedEdges: Array(connectedEdges)))
        let dbActor = self.dbActor
        Task { [weak self, dbActor, nodeId, node] in
            do {
                try await dbActor.deleteNode(id: nodeId)

                // Decrement the user-facing metadata stat
                if let userId = FirebaseAuthService.shared.currentUser?.uid {
                    var fieldToDecrement: String?
                    switch node.type {
                    case .standard:
                        if node.parentId != nil {
                            fieldToDecrement = "totalChildNodesCreated"
                        } else {
                            fieldToDecrement = "totalNodesCreated"
                        }
                    case .note:
                        fieldToDecrement = "totalNotesCreated"
                    default:
                        break // Other types don't have counters
                    }

                    if let field = fieldToDecrement {
                        await FirebaseDataService.shared.decrementUserMetadata(userId: userId, field: field)
                    }

                    // Also decrement team member count if one was assigned
                    if node.teamMember != nil {
                        await FirebaseDataService.shared.decrementUserMetadata(userId: userId, field: "totalTeamMembersUsed")
                    }
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Failed to delete node: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func moveNode(_ nodeId: UUID, to position: CGPoint) {
        guard var node = nodes[nodeId] else { return }
        
        let oldPosition = CGPoint(x: node.x, y: node.y)
        node.x = position.x
        node.y = position.y
        node.updatedAt = Date()
        
        // Explicitly trigger objectWillChange before mutation
        objectWillChange.send()
        nodes[nodeId] = node
        positionsVersion &+= 1 // signal to views that positions changed
        
        undoManager.coalesceIfNeeded(.moveNode(id: nodeId, oldPosition: oldPosition, newPosition: position))
        
        // Debounce database write during drag
        scheduleDebouncedWrite(nodeId: nodeId)
    }
    
    /// Move multiple nodes by a delta (for multi-select drag)
    func moveNodes(_ nodeIds: Set<UUID>, delta: CGSize) {
        objectWillChange.send()
        
        for nodeId in nodeIds {
            guard var node = nodes[nodeId] else { continue }
            let oldPosition = CGPoint(x: node.x, y: node.y)
            node.x += delta.width
            node.y += delta.height
            node.updatedAt = Date()
            nodes[nodeId] = node
            
            undoManager.coalesceIfNeeded(.moveNode(id: nodeId, oldPosition: oldPosition, newPosition: CGPoint(x: node.x, y: node.y)))
            scheduleDebouncedWrite(nodeId: nodeId)
        }
        
        positionsVersion &+= 1
    }
    
    // MARK: - Multi-Select
    
    /// Toggle a node in the multi-select set
    func toggleNodeInSelection(_ nodeId: UUID) {
        objectWillChange.send()  // Force UI update
        if selectedNodeIds.contains(nodeId) {
            selectedNodeIds.remove(nodeId)
            #if DEBUG
            print("[MultiSelect] Removed node from selection, now \(selectedNodeIds.count) nodes")
            #endif
        } else {
            selectedNodeIds.insert(nodeId)
            #if DEBUG
            print("[MultiSelect] Added node to selection, now \(selectedNodeIds.count) nodes")
            #endif
        }
    }
    
    /// Add a node to the multi-select set
    func addNodeToSelection(_ nodeId: UUID) {
        selectedNodeIds.insert(nodeId)
    }
    
    /// Remove a node from the multi-select set
    func removeNodeFromSelection(_ nodeId: UUID) {
        selectedNodeIds.remove(nodeId)
    }
    
    /// Clear all multi-selections
    func clearMultiSelection() {
        #if DEBUG
        if !selectedNodeIds.isEmpty {
            print("[MultiSelect] CLEARING selection! Had \(selectedNodeIds.count) nodes")
            Thread.callStackSymbols.prefix(10).forEach { print("  \($0)") }
        }
        #endif
        selectedNodeIds.removeAll()
    }
    
    /// Check if a node is in the multi-select set
    func isNodeInMultiSelection(_ nodeId: UUID) -> Bool {
        return selectedNodeIds.contains(nodeId)
    }
    
    /// Select all nodes
    func selectAllNodes() {
        selectedNodeIds = Set(nodes.keys)
        selectedNodeId = nil  // Clear single selection
    }
    
    /// Clear snap guides
    func clearSnapGuides() {
        snapGuides.removeAll()
    }
    
    /// Get all team members from nodes in the current project, excluding a specific node
    func getProjectTeamMembers(excludingNodeId: UUID? = nil) -> [(nodeName: String, teamMember: TeamMember, role: Role?)] {
        let roleManager = RoleManager.shared
        return nodes.values
            .filter { node in
                // Exclude the specified node if provided
                if let excludeId = excludingNodeId, node.id == excludeId {
                    return false
                }
                // Only include nodes with team members
                return node.teamMember != nil
            }
            .compactMap { node in
                guard let teamMember = node.teamMember else { return nil }
                let role = roleManager.role(withId: teamMember.roleId)
                let nodeName = node.title.isEmpty ? "Untitled" : node.title
                return (nodeName: nodeName, teamMember: teamMember, role: role)
            }
    }
    
    // MARK: - AI Generation
    
    /// Flag to prevent recursive routing checks
    private var isRoutingInProgress = false
    
    /// Minimum prompt length to consider for expert routing (saves tokens on simple questions)
    private let minPromptLengthForRouting = 20
    
    func generateResponse(for nodeId: UUID, prompt: String, imageData: Data? = nil, imageMimeType: String? = nil, webSearchEnabled: Bool = false, skipRouting: Bool = false) {
        guard let node = nodes[nodeId] else { return }
        
        // Check credits for cloud providers
        if AIProviderManager.shared.activeProvider != .local {
            let result = CreditTracker.shared.checkCredits()
            if !result.allowed {
                // Set credit error state for this node so UI can show inline message
                creditErrorNodeId = nodeId
                creditCheckResult = result
                errorMessage = result.userMessage
                return
            }
        }
        
        // Clear any previous credit error for this node
        if creditErrorNodeId == nodeId {
            creditErrorNodeId = nil
            creditCheckResult = nil
        }
        
        // Check if this is a master orchestrator node that should route to an expert
        // Safeguards:
        // 1. skipRouting flag prevents recursion when called from routeToExpert
        // 2. isRoutingInProgress prevents concurrent routing operations
        // 3. Minimum prompt length check saves tokens on simple questions
        // 4. No routing for image prompts
        let shouldCheckRouting = node.orchestratorRole == .master 
            && !skipRouting 
            && !isRoutingInProgress
            && imageData == nil
            && prompt.count >= minPromptLengthForRouting
        
        if shouldCheckRouting {
            isRoutingInProgress = true
            Task { @MainActor in
                defer { self.isRoutingInProgress = false }
                
                do {
                    let routingResult = try await OrchestratorService.shared.checkForExpertRouting(
                        masterNodeId: nodeId,
                        prompt: prompt,
                        viewModel: self
                    )
                    
                    if routingResult.shouldRoute,
                       let delegateId = routingResult.delegateNodeId {
                        // Route to the expert delegate
                        let questionToAsk = routingResult.refinedQuestion ?? prompt
                        try await OrchestratorService.shared.routeToExpert(
                            masterNodeId: nodeId,
                            delegateNodeId: delegateId,
                            question: questionToAsk,
                            viewModel: self
                        )
                        return
                    }
                } catch {
                    print("⚠️ Expert routing check failed: \(error)")
                    // Fall through to normal generation
                }
                
                // No routing needed, proceed with normal generation
                self.generateResponseDirect(for: nodeId, prompt: prompt, imageData: imageData, imageMimeType: imageMimeType, webSearchEnabled: webSearchEnabled)
            }
            return
        }
        
        generateResponseDirect(for: nodeId, prompt: prompt, imageData: imageData, imageMimeType: imageMimeType, webSearchEnabled: webSearchEnabled)
    }
    
    /// Direct response generation without expert routing check
    private func generateResponseDirect(for nodeId: UUID, prompt: String, imageData: Data? = nil, imageMimeType: String? = nil, webSearchEnabled: Bool = false) {
        guard var node = nodes[nodeId] else { return }
        
        generatingNodeId = nodeId
        // Web search path is currently disabled; always fall through to plain AI generation.
        
        // Capture team member info for this response BEFORE async work
        // This preserves which persona was used even if user changes it mid-generation
        let teamMemberRoleId = node.teamMember?.roleId
        let teamMemberRoleName: String?
        if let teamMember = node.teamMember,
           let role = RoleManager.shared.roles.first(where: { $0.id == teamMember.roleId }) {
            teamMemberRoleName = role.name
        } else {
            teamMemberRoleName = nil
        }
        let teamMemberExperienceLevel = node.teamMember?.experienceLevel.rawValue
        
        // Add user message to conversation without search
        node.addMessage(role: .user, content: prompt, imageData: imageData, imageMimeType: imageMimeType)
        // Also update legacy prompt field for backwards compatibility
        node.prompt = prompt
        nodes[nodeId] = node
        
        Task { [weak self, teamMemberRoleId, teamMemberRoleName, teamMemberExperienceLevel] in
            guard let self = self else { return }
            
            do {
                let aiContext = self.buildAIContext(for: node)
                let contextTextsForBilling = aiContext.map { $0.content }
                var streamedResponse = ""
                
                // Assemble system prompt
                let baseSystemPrompt = node.systemPromptSnapshot ?? self.project.systemPrompt
                let effectiveBaseSystemPrompt: String
                if AIProviderManager.shared.activeProvider == .local {
                    effectiveBaseSystemPrompt = baseSystemPrompt + "\n\nWhen answering, be concise and concrete. Focus on specific numbers, tradeoffs, and examples, and avoid repeating the same high-level outline in every reply."
                } else {
                    effectiveBaseSystemPrompt = baseSystemPrompt
                }
                let finalSystemPrompt: String
                if let teamMember = node.teamMember,
                   let role = RoleManager.shared.roles.first(where: { $0.id == teamMember.roleId }) {
                    finalSystemPrompt = teamMember.assembleSystemPrompt(
                    with: role,
                    personality: node.personality,
                    baseSystemPrompt: effectiveBaseSystemPrompt
                )
                    
                    // Track team member usage
                    self.trackTeamMemberUsage(
                        nodeId: nodeId,
                        roleId: role.id,
                        roleName: role.name,
                        roleCategory: role.category.rawValue,
                        experienceLevel: teamMember.experienceLevel.rawValue,
                        actionType: .used
                    )
                } else {
                    finalSystemPrompt = baseSystemPrompt
                }
                
                AIProviderManager.shared.client?.generateStreaming(
                    prompt: prompt,
                    systemPrompt: finalSystemPrompt,
                    context: aiContext,
                    onChunk: { [weak self] chunk in
                        Task { @MainActor in
                            streamedResponse += chunk
                            // Temporarily show streaming response
                            guard var currentNode = self?.nodes[nodeId] else { return }
                            currentNode.response = streamedResponse
                            self?.nodes[nodeId] = currentNode
                        }
                    },
                    onComplete: { [weak self] result in
                        Task { @MainActor in
                            self?.generatingNodeId = nil
                            // Also clear from orchestrating set if present (cleanup for edge cases)
                            self?.orchestratingNodeIds.remove(nodeId)
                            
                            switch result {
                            case .success(let fullResponse):
                                guard var finalNode = self?.nodes[nodeId] else { return }
                                // Add assistant message to conversation with team member info
                                finalNode.addMessage(
                                    role: .assistant,
                                    content: fullResponse,
                                    teamMemberRoleId: teamMemberRoleId,
                                    teamMemberRoleName: teamMemberRoleName,
                                    teamMemberExperienceLevel: teamMemberExperienceLevel
                                )
                                // Also update legacy response field for backwards compatibility
                                finalNode.response = fullResponse
                                finalNode.updatedAt = Date()
                                self?.nodes[nodeId] = finalNode
                                if let dbActor = self?.dbActor {
                                    Task { [dbActor, finalNode] in
                                        try? await dbActor.saveNode(finalNode)
                                    }
                                }
                                
                                // Mark as unread if node is not currently selected
                                if self?.selectedNodeId != nodeId {
                                    self?.nodesWithUnreadResponse.insert(nodeId)
                                }
                                
                                // Track credit usage and analytics (backend handles actual deduction)
                                if AIProviderManager.shared.activeProvider != .local {
                                    await CreditTracker.shared.trackGeneration(
                                        promptText: prompt,
                                        responseText: fullResponse,
                                        contextTexts: contextTextsForBilling,
                                        nodeId: nodeId,
                                        projectId: self?.project.id ?? UUID(),
                                        teamMemberRoleId: teamMemberRoleId,
                                        teamMemberExperienceLevel: teamMemberExperienceLevel,
                                        generationType: "chat"
                                    )
                                }
                                
                                await self?.autoGenerateTitleAndDescription(for: nodeId)
                                
                                // Auto-generate embedding for RAG (background, non-blocking)
                                await self?.updateNodeEmbedding(for: nodeId)
                                
                            case .failure(let error):
                                self?.errorNodeId = nodeId
                                self?.errorMessage = error.localizedDescription
                                // Clear error state after brief display
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    if self?.errorNodeId == nodeId {
                                        self?.errorNodeId = nil
                                    }
                                }
                            }
                        }
                    }
                )
            }
        }
    }
    
    /// Update node embedding for RAG-based context retrieval
    private func updateNodeEmbedding(for nodeId: UUID) async {
        guard var node = nodes[nodeId] else { return }
        
        // Skip if using local provider (no embedding API)
        guard AIProviderManager.shared.activeProvider != .local else { return }
        
        do {
            let updated = try await embeddingService.updateEmbeddingIfNeeded(for: &node)
            if updated {
                nodes[nodeId] = node
                let dbActor = self.dbActor
                Task { [dbActor, node] in
                    try? await dbActor.saveNode(node)
                }
            }
        } catch {
            if Config.enableVerboseLogging {
                print("⚠️ Failed to update embedding for node \(nodeId): \(error.localizedDescription)")
            }
        }
    }
    
    private func continueGenerationWithSearch(
        nodeId: UUID,
        prompt: String,
        imageData: Data?,
        imageMimeType: String?,
        searchResults: [SearchResult]?
    ) async {
        guard let node = nodes[nodeId] else { return }
        
        // Capture team member info for this response
        let teamMemberRoleId = node.teamMember?.roleId
        let teamMemberRoleName: String?
        if let teamMember = node.teamMember,
           let role = RoleManager.shared.roles.first(where: { $0.id == teamMember.roleId }) {
            teamMemberRoleName = role.name
        } else {
            teamMemberRoleName = nil
        }
        let teamMemberExperienceLevel = node.teamMember?.experienceLevel.rawValue
        
        // Build enhanced prompt with search context
        var enhancedPrompt = prompt
        if let results = searchResults, !results.isEmpty {
            let searchContext = results.enumerated().map { index, result in
                "[\(index + 1)] **\(result.title)** (\(result.source))\n\(result.snippet)\nURL: \(result.url)"
            }.joined(separator: "\n\n")
            
            enhancedPrompt = """
            Based on the following web search results:
            
            \(searchContext)
            
            User question: \(prompt)
            
            Please provide a comprehensive answer using the information from these sources. Do not include citation numbers or brackets in your response - the sources are shown separately to the user.
            """
        }
        
        do {
            let aiContext = buildAIContext(for: node)
            var contextTextsForBilling = aiContext.map { $0.content }
            // Also include the search context in billing if present
            if enhancedPrompt != prompt {
                contextTextsForBilling.append(enhancedPrompt)
            }
            var streamedResponse = ""
            
            // Assemble system prompt
            let baseSystemPrompt = node.systemPromptSnapshot ?? project.systemPrompt
            let effectiveBaseSystemPrompt: String
            if AIProviderManager.shared.activeProvider == .local {
                effectiveBaseSystemPrompt = baseSystemPrompt + "\n\nWhen answering, be concise and concrete. Focus on specific numbers, tradeoffs, and examples, and avoid repeating the same high-level outline in every reply."
            } else {
                effectiveBaseSystemPrompt = baseSystemPrompt
            }
            let finalSystemPrompt: String
            if let teamMember = node.teamMember,
               let role = RoleManager.shared.roles.first(where: { $0.id == teamMember.roleId }) {
                finalSystemPrompt = teamMember.assembleSystemPrompt(
                    with: role,
                    personality: node.personality,
                    baseSystemPrompt: effectiveBaseSystemPrompt
                )
                
                // Track team member usage
                trackTeamMemberUsage(
                    nodeId: nodeId,
                    roleId: role.id,
                    roleName: role.name,
                    roleCategory: role.category.rawValue,
                    experienceLevel: teamMember.experienceLevel.rawValue,
                    actionType: .used
                )
            } else {
                finalSystemPrompt = effectiveBaseSystemPrompt
            }
            
            AIProviderManager.shared.client?.generateStreaming(
                prompt: enhancedPrompt,
                systemPrompt: finalSystemPrompt,
                context: aiContext,
                onChunk: { [weak self] chunk in
                    Task { @MainActor in
                        streamedResponse += chunk
                        guard var currentNode = self?.nodes[nodeId] else { return }
                        currentNode.response = streamedResponse
                        self?.nodes[nodeId] = currentNode
                    }
                },
                onComplete: { [weak self, teamMemberRoleId, teamMemberRoleName, teamMemberExperienceLevel] result in
                    Task { @MainActor in
                        self?.generatingNodeId = nil
                        // Also clear from orchestrating set if present (cleanup for edge cases)
                        self?.orchestratingNodeIds.remove(nodeId)
                        
                        switch result {
                        case .success(let fullResponse):
                            guard var finalNode = self?.nodes[nodeId] else { return }
                            // Add assistant message to conversation with team member info
                            finalNode.addMessage(
                                role: .assistant,
                                content: fullResponse,
                                teamMemberRoleId: teamMemberRoleId,
                                teamMemberRoleName: teamMemberRoleName,
                                teamMemberExperienceLevel: teamMemberExperienceLevel
                            )
                            finalNode.response = fullResponse
                            finalNode.updatedAt = Date()
                            self?.nodes[nodeId] = finalNode
                            if let dbActor = self?.dbActor {
                                Task { [dbActor, finalNode] in
                                    try? await dbActor.saveNode(finalNode)
                                }
                            }
                            
                            // Mark as unread if node is not currently selected
                            if self?.selectedNodeId != nodeId {
                                self?.nodesWithUnreadResponse.insert(nodeId)
                            }
                            
                            if AIProviderManager.shared.activeProvider != .local {
                                await CreditTracker.shared.trackGeneration(
                                    promptText: prompt,
                                    responseText: fullResponse,
                                    contextTexts: contextTextsForBilling,
                                    nodeId: nodeId,
                                    projectId: self?.project.id ?? UUID(),
                                    teamMemberRoleId: finalNode.teamMember?.roleId,
                                    teamMemberExperienceLevel: finalNode.teamMember?.experienceLevel.rawValue,
                                    generationType: "chat_with_search"
                                )
                            }
                            
                            await self?.autoGenerateTitleAndDescription(for: nodeId)
                            
                        case .failure(let error):
                            self?.errorNodeId = nodeId
                            self?.errorMessage = error.localizedDescription
                            // Clear error state after brief display
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                if self?.errorNodeId == nodeId {
                                    self?.errorNodeId = nil
                                }
                            }
                        }
                    }
                }
            )
        }
    }
    
    private func buildContext(for node: Node) -> [Message] {
        var messages: [Message] = []
        if let parentId = node.parentId,
           let parent = nodes[parentId],
           let summary = parent.summary,
           !summary.isEmpty {
            messages.append(Message(role: "user", content: "Context from previous conversation: \(summary)"))
        }
        if !node.conversation.isEmpty {
            let recentMessages = Array(node.conversation.suffix(project.kTurns * 2))
            for msg in recentMessages {
                messages.append(Message(
                    role: msg.role == .user ? "user" : "model",
                    content: msg.content,
                    imageData: msg.imageData,
                    imageMimeType: msg.imageMimeType
                ))
            }
        }
        return messages
    }

private func buildAIContext(for node: Node) -> [AIChatMessage] {
    var messages: [AIChatMessage] = []
    
    // 1. Context from parent node (existing behavior)
    if let parentId = node.parentId,
       let parent = nodes[parentId],
       let summary = parent.summary,
       !summary.isEmpty {
        messages.append(AIChatMessage(role: .user, content: "Context from parent conversation: \(summary)"))
    }
    
    // 2. Context from connected nodes via edges (RAG-based)
    // Find all incoming edges (edges where this node is the target)
    let incomingEdges = edges.values.filter { $0.targetId == node.id }
    
    if Config.enableVerboseLogging {
        print("🔗 Building AI context for node '\(node.title)' (id: \(node.id))")
        print("🔗 Total edges: \(edges.count), incoming edges: \(incomingEdges.count)")
    }
    
    if !incomingEdges.isEmpty {
        var connectedContextParts: [String] = []
        
        for edge in incomingEdges {
            guard let sourceNode = nodes[edge.sourceId] else {
                if Config.enableVerboseLogging {
                    print("🔗 Source node \(edge.sourceId) not found for edge")
                }
                continue
            }
            
            if Config.enableVerboseLogging {
                print("🔗 Found connected source node: '\(sourceNode.title)' (id: \(sourceNode.id))")
            }
            
            // Build context snippet from connected node
            let snippet = embeddingService.buildContextSnippet(from: sourceNode)
            if !snippet.isEmpty {
                let nodeName = sourceNode.title.isEmpty ? "Connected Node" : sourceNode.title
                connectedContextParts.append("[\(nodeName)]: \(snippet)")
            } else if Config.enableVerboseLogging {
                print("🔗 Empty snippet from node '\(sourceNode.title)'")
            }
        }
        
        if !connectedContextParts.isEmpty {
            let connectedContext = connectedContextParts.joined(separator: "\n\n")
            if Config.enableVerboseLogging {
                print("🔗 Adding connected context to AI (\(connectedContext.count) chars)")
            }
            messages.append(AIChatMessage(
                role: .user,
                content: "Context from connected knowledge sources:\n\n\(connectedContext)"
            ))
        }
    }
    
    // 3. Node's own conversation history
    if !node.conversation.isEmpty {
        let recentMessages = Array(node.conversation.suffix(project.kTurns * 2))
        let isLocal = AIProviderManager.shared.activeProvider == .local
        for msg in recentMessages {
            if isLocal && msg.role != .user {
                continue
            }
            let mappedRole: AIChatMessage.Role = msg.role == .user ? .user : .assistant
            messages.append(AIChatMessage(
                role: mappedRole,
                content: msg.content,
                imageData: msg.imageData,
                imageMimeType: msg.imageMimeType
            ))
        }
    }
    return messages
}

    
    private func autoGenerateTitleAndDescription(for nodeId: UUID) async {
        // Backwards-compatible helper that now only auto-generates a title.
        // Descriptions are no longer auto-generated; they remain user-authored.
        guard var node = nodes[nodeId] else { return }
        guard node.title.isEmpty else { return }
        
        do {
            let prompt = """
            Based on this conversation:
            User: \(node.prompt)
            Jam: \(node.response)
            
            Generate a concise title (max 50 chars).
            Return only the title text.
            """
            
            guard let client = AIProviderManager.shared.client else { return }
            let result = try await client.generate(
                prompt: prompt,
                systemPrompt: "You are a helpful assistant that creates concise titles.",
                context: []
            )
            
            let trimmedTitle = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                node.title = String(trimmedTitle.prefix(50))
                node.titleSource = .ai
            }
            
            nodes[nodeId] = node
            let dbActor = self.dbActor
            Task { [weak self, dbActor, node] in
                do {
                    try await dbActor.saveNode(node)
                } catch {
                    await MainActor.run {
                        self?.errorMessage = "Failed to auto-save node: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            if Config.enableVerboseLogging { print("Failed to auto-generate title: \(error)") }
        }
    }
    
    // MARK: - Copy/Paste
    
    func copyNode(_ nodeId: UUID) {
        guard let node = nodes[nodeId] else { return }
        
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(node),
           let jsonString = String(data: data, encoding: .utf8) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(jsonString, forType: .string)
        }
    }
    
    func pasteNode(at position: CGPoint) {
        let pasteboard = NSPasteboard.general
        guard let jsonString = pasteboard.string(forType: .string),
              let data = jsonString.data(using: .utf8) else { return }
        
        let decoder = JSONDecoder()
        if let originalNode = try? decoder.decode(Node.self, from: data) {
            // Create new node with new ID
            let newNode = Node(
                id: UUID(),
                projectId: originalNode.projectId,
                parentId: nil,
                x: position.x,
                y: position.y,
                height: originalNode.height,
                title: originalNode.title,
                titleSource: originalNode.titleSource,
                description: originalNode.description,
                descriptionSource: originalNode.descriptionSource,
                conversationJSON: originalNode.conversationJSON,
                prompt: originalNode.prompt,
                response: originalNode.response,
                ancestryJSON: "[]",
                summary: originalNode.summary,
                systemPromptSnapshot: originalNode.systemPromptSnapshot,
                isExpanded: originalNode.isExpanded,
                isFrozenContext: originalNode.isFrozenContext
            )
            
            nodes[newNode.id] = newNode
            
            let dbActor = self.dbActor
            undoManager.record(.createNode(newNode))
            Task { [weak self, dbActor, newNode] in
                do {
                    try await dbActor.saveNode(newNode)
                } catch {
                    await MainActor.run {
                        self?.errorMessage = "Failed to paste node: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    // MARK: - Undo/Redo
    
    func undo() {
        if Config.enableVerboseLogging { print("🔄 Undo called - canUndo: \(undoManager.canUndo)") }
        guard let action = undoManager.undo() else {
            if Config.enableVerboseLogging { print("⚠️ No action to undo") }
            return
        }
        if Config.enableVerboseLogging { print("✅ Undoing action: \(action)") }
        applyAction(action, reverse: true)
    }
    
    func redo() {
        if Config.enableVerboseLogging { print("🔄 Redo called - canRedo: \(undoManager.canRedo)") }
        guard let action = undoManager.redo() else {
            if Config.enableVerboseLogging { print("⚠️ No action to redo") }
            return
        }
        if Config.enableVerboseLogging { print("✅ Redoing action: \(action)") }
        applyAction(action, reverse: false)
    }
    
    private func applyAction(_ action: CanvasAction, reverse: Bool) {
        switch action {
        case .createNode(let node):
            if reverse {
                nodes.removeValue(forKey: node.id)
                let dbActor = self.dbActor
                Task { [dbActor, nodeId = node.id] in
                    try? await dbActor.deleteNode(id: nodeId)
                }
            } else {
                nodes[node.id] = node
                let dbActor = self.dbActor
                Task { [dbActor, node] in
                    try? await dbActor.saveNode(node)
                }
            }
            
        case .deleteNode(let node, let connectedEdges):
            if reverse {
                // Undo: restore node and all connected edges
                nodes[node.id] = node
                let dbActor = self.dbActor
                Task { [dbActor, node] in
                    try? await dbActor.saveNode(node)
                }
                // Restore all connected edges using debounced write
                for edge in connectedEdges {
                    edges[edge.id] = edge
                    scheduleDebouncedWrite(edgeId: edge.id)
                }
            } else {
                // Redo: delete node and connected edges
                nodes.removeValue(forKey: node.id)
                let dbActor = self.dbActor
                Task { [dbActor, nodeId = node.id] in
                    try? await dbActor.deleteNode(id: nodeId)
                }
                // Delete all connected edges
                for edge in connectedEdges {
                    edges.removeValue(forKey: edge.id)
                    pendingEdgeWrites.remove(edge.id)
                    Task { [dbActor, edgeId = edge.id] in
                        try? await dbActor.deleteEdge(id: edgeId)
                    }
                }
            }
            
        case .updateNode(let oldNode, let newNode):
            let nodeToApply = reverse ? oldNode : newNode
            nodes[nodeToApply.id] = nodeToApply
            let dbActor = self.dbActor
            Task { [dbActor, nodeToApply] in
                try? await dbActor.saveNode(nodeToApply)
            }
            
        case .moveNode(let id, let oldPos, let newPos):
            guard var node = nodes[id] else { return }
            let position = reverse ? oldPos : newPos
            node.x = position.x
            node.y = position.y
            nodes[id] = node
            let dbActor = self.dbActor
            Task { [dbActor, node] in
                try? await dbActor.saveNode(node)
            }
            
        case .createEdge(let edge):
            if reverse {
                edges.removeValue(forKey: edge.id)
                pendingEdgeWrites.remove(edge.id)
                let dbActor = self.dbActor
                Task { [dbActor, edgeId = edge.id] in
                    try? await dbActor.deleteEdge(id: edgeId)
                }
            } else {
                edges[edge.id] = edge
                scheduleDebouncedWrite(edgeId: edge.id)
            }
            
        case .deleteEdge(let edge):
            if reverse {
                edges[edge.id] = edge
                scheduleDebouncedWrite(edgeId: edge.id)
            } else {
                edges.removeValue(forKey: edge.id)
                pendingEdgeWrites.remove(edge.id)
                let dbActor = self.dbActor
                Task { [dbActor, edgeId = edge.id] in
                    try? await dbActor.deleteEdge(id: edgeId)
                }
            }
            
        case .updateProject(let oldProj, let newProj):
            project = reverse ? oldProj : newProj
            let snapshotProject = project
            let dbActor = self.dbActor
            Task { [dbActor, snapshotProject] in
                try? await dbActor.saveProject(snapshotProject)
            }
        }
    }
    
    // MARK: - Navigation
    
    func navigateToNode(_ nodeId: UUID, viewportSize: CGSize = CGSize(width: 1200, height: 800)) {
        guard let node = nodes[nodeId] else { return }
        
        // Select the node
        selectedNodeId = nodeId
        
        // Calculate node center in world coordinates
        let nodeWidth = node.width
        let nodeHeight = node.height
        let nodeCenterX = node.x + nodeWidth / 2
        let nodeCenterY = node.y + nodeHeight / 2
        
        // Calculate target offset to center the node in viewport
        let targetZoom: CGFloat = 1.0
        let targetOffset = CGSize(
            width: viewportSize.width / 2 - nodeCenterX * targetZoom,
            height: viewportSize.height / 2 - nodeCenterY * targetZoom
        )
        
        // Animate the navigation
        withAnimation(.easeInOut(duration: 0.5)) {
            zoom = targetZoom
            offset = targetOffset
        }
        
        // Update edges after animation completes to ensure they're correctly positioned
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 550_000_000) // 0.55s (0.5s animation + 0.05s buffer)
            positionsVersion &+= 1
        }
    }
    
    func toggleNodeSize(_ nodeId: UUID, viewportSize: CGSize = CGSize(width: 1200, height: 800)) {
        guard var node = nodes[nodeId] else { return }
        
        // Determine if node is currently at max size
        let maxWidth = node.type == .note ? Node.maxNoteWidth : Node.maxWidth
        let minWidth = node.type == .note ? Node.minNoteWidth : Node.minWidth
        let maxHeight = node.type == .note ? Node.maxNoteHeight : Node.maxHeight
        let minHeight = node.type == .note ? Node.minNoteHeight : Node.minHeight
        let isMaximized = node.width >= maxWidth && node.height >= maxHeight
        
        // Toggle between min and max size with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            if isMaximized {
                // Minimize: set to minimum dimensions (square-friendly for notes)
                node.width = minWidth
                node.height = minHeight
            } else {
                // Maximize: set to maximum dimensions
                node.width = maxWidth
                node.height = maxHeight
            }
            
            // Ensure node is expanded when resizing
            if !node.isExpanded {
                node.isExpanded = true
            }
            
            nodes[nodeId] = node
        }
        
        updateNode(node, immediate: true)
        
        // Calculate node center in world coordinates with new dimensions
        let nodeCenterX = node.x + node.width / 2
        let nodeCenterY = node.y + node.height / 2
        
        // Calculate target offset to center the node in viewport at 100% zoom
        let targetZoom: CGFloat = 1.0
        let targetOffset = CGSize(
            width: viewportSize.width / 2 - nodeCenterX * targetZoom,
            height: viewportSize.height / 2 - nodeCenterY * targetZoom
        )
        
        // Animate the navigation
        withAnimation(.easeInOut(duration: 0.5)) {
            zoom = targetZoom
            offset = targetOffset
        }
        
        // Update edges after animation completes to ensure they're correctly positioned
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 550_000_000) // 0.55s (0.5s animation + 0.05s buffer)
            positionsVersion &+= 1
        }
    }
    
    // MARK: - Zoom Controls
    
    /// Standard zoom presets (same as design apps like Figma/Sketch)
    private static let zoomPresets: [CGFloat] = [0.1, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5]
    
    func zoomIn() {
        // Find the next preset level above current zoom
        let nextPreset = Self.zoomPresets.first { $0 > zoom + 0.001 } ?? Config.maxZoom
        let newZoom = min(Config.maxZoom, nextPreset)
        zoomToCenter(newZoom: newZoom)
    }
    
    func zoomOut() {
        // Find the next preset level below current zoom
        let prevPreset = Self.zoomPresets.last { $0 < zoom - 0.001 } ?? Config.minZoom
        let newZoom = max(Config.minZoom, prevPreset)
        zoomToCenter(newZoom: newZoom)
    }
    
    func resetZoom() {
        zoomToCenter(newZoom: Config.defaultZoom)
    }
    
    func zoomTo(_ level: CGFloat) {
        let clampedZoom = max(Config.minZoom, min(Config.maxZoom, level))
        zoomToCenter(newZoom: clampedZoom)
    }
    
    func zoomToFit() {
        guard !nodes.isEmpty else {
            resetZoom()
            return
        }
        
        // Calculate bounding box of all nodes
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        
        for node in nodes.values {
            let nodeWidth = node.width
            let nodeHeight = node.height
            
            minX = min(minX, node.x)
            minY = min(minY, node.y)
            maxX = max(maxX, node.x + nodeWidth)
            maxY = max(maxY, node.y + nodeHeight)
        }
        
        let contentWidth = maxX - minX
        let contentHeight = maxY - minY
        let contentCenterX = (minX + maxX) / 2
        let contentCenterY = (minY + maxY) / 2
        
        // Add padding (20% of content size)
        let padding: CGFloat = 1.2
        
        // Calculate zoom to fit content with padding
        let zoomX = viewportSize.width / (contentWidth * padding)
        let zoomY = viewportSize.height / (contentHeight * padding)
        let newZoom = max(Config.minZoom, min(Config.maxZoom, min(zoomX, zoomY)))
        
        // Calculate offset to center content
        let viewportCenterX = viewportSize.width / 2
        let viewportCenterY = viewportSize.height / 2
        let newOffset = CGSize(
            width: viewportCenterX - contentCenterX * newZoom,
            height: viewportCenterY - contentCenterY * newZoom
        )
        
        withAnimation(.easeOut(duration: 0.3)) {
            zoom = newZoom
            offset = newOffset
        }
    }
    
    private func zoomToCenter(newZoom: CGFloat) {
        let oldZoom = zoom
        // Calculate viewport center
        let centerX = viewportSize.width / 2
        let centerY = viewportSize.height / 2
        // Calculate world point at viewport center before zoom
        let worldX = (centerX - offset.width) / max(oldZoom, 0.001)
        let worldY = (centerY - offset.height) / max(oldZoom, 0.001)
        // Calculate new offset to keep that world point at viewport center after zoom
        let newOffset = CGSize(
            width: centerX - worldX * newZoom,
            height: centerY - worldY * newZoom
        )
        
        withAnimation(.easeOut(duration: 0.2)) {
            zoom = newZoom
            offset = newOffset
        }
    }
    
    // MARK: - Search
    
    /// Show the search modal
    func showSearchModal() {
        // Update viewport center for proximity-based ranking
        let viewportCenterX = (viewportSize.width / 2 - offset.width) / zoom
        let viewportCenterY = (viewportSize.height / 2 - offset.height) / zoom
        searchViewModel.updateViewportCenter(CGPoint(x: viewportCenterX, y: viewportCenterY))
        
        // Show the modal
        ModalCoordinator.shared.showSearchModal(viewModel: searchViewModel)
    }
    
    /// Handle when a search result is selected
    func handleSearchResultSelected(_ result: ConversationSearchResult) {
        // Navigate to the node
        navigateToNode(result.nodeId, viewportSize: viewportSize)
        
        // Set the search highlight so NodeView can scroll to and highlight the message
        searchHighlight = NodeSearchHighlight(
            nodeId: result.nodeId,
            messageId: result.messageId,
            query: searchViewModel.query
        )
        
        // Clear highlight after a delay to allow re-searching the same term
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            if self.searchHighlight?.nodeId == result.nodeId &&
               self.searchHighlight?.messageId == result.messageId {
                self.searchHighlight = nil
            }
        }
    }
    
    /// Update search index when a node changes
    func updateSearchIndex(for node: Node) {
        searchIndex.indexNode(node)
    }
    
    /// Remove a node from the search index
    func removeFromSearchIndex(nodeId: UUID) {
        searchIndex.removeNode(nodeId: nodeId)
    }
    
    // MARK: - Outline Ordering
    
    func reorderNode(_ nodeId: UUID, from sourceIndex: Int, to destinationIndex: Int, in nodeIds: [UUID]) {
        guard sourceIndex != destinationIndex else { return }
        
        // Reassign display orders for all affected nodes
        var updates: [(UUID, Int)] = []
        
        if sourceIndex < destinationIndex {
            // Moving down: shift items between source and destination up
            for i in 0..<nodeIds.count {
                let id = nodeIds[i]
                if i == sourceIndex {
                    updates.append((id, destinationIndex))
                } else if i > sourceIndex && i <= destinationIndex {
                    updates.append((id, i - 1))
                } else {
                    updates.append((id, i))
                }
            }
        } else {
            // Moving up: shift items between destination and source down
            for i in 0..<nodeIds.count {
                let id = nodeIds[i]
                if i == sourceIndex {
                    updates.append((id, destinationIndex))
                } else if i >= destinationIndex && i < sourceIndex {
                    updates.append((id, i + 1))
                } else {
                    updates.append((id, i))
                }
            }
        }
        
        // Apply all updates
        for (id, newOrder) in updates {
            guard var node = nodes[id] else { continue }
            node.displayOrder = newOrder
            updateNode(node)
        }
    }
    
    // MARK: - Auto-save
    
    private func setupAutosave() {
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: Config.autoSaveInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.save()
            }
        }
    }
    
    func save() {
        // Flush any pending debounced writes first
        flushPendingWrites()
        
        // Create periodic backup if needed (every 5 minutes)
        if let url = projectURL {
            BackupService.shared.createPeriodicBackupIfNeeded(projectURL: url)
        }
        
        // Update project's canvas state before saving
        project.canvasOffsetX = offset.width
        project.canvasOffsetY = offset.height
        project.canvasZoom = zoom
        project.backgroundStyle = backgroundStyle
        project.backgroundColorId = backgroundColorId
        project.showDots = (backgroundStyle == .dots)
        
        let snapshotProject = project
        let snapshotNodes = Array(nodes.values)
        let snapshotEdges = Array(edges.values)
        let dbActor = self.dbActor
        Task { [weak self, dbActor, snapshotProject, snapshotNodes, snapshotEdges] in
            do {
                try await dbActor.saveProject(snapshotProject)
                for node in snapshotNodes {
                    try await dbActor.saveNode(node)
                }
                for edge in snapshotEdges {
                    try await dbActor.saveEdge(edge)
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Auto-save failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func saveAndWait() async {
        project.canvasOffsetX = offset.width
        project.canvasOffsetY = offset.height
        project.canvasZoom = zoom
        project.backgroundStyle = backgroundStyle
        project.backgroundColorId = backgroundColorId
        project.showDots = (backgroundStyle == .dots)
        let snapshotProject = project
        let snapshotNodes = Array(nodes.values)
        let snapshotEdges = Array(edges.values)
        let nodeIds = pendingNodeWrites
        let edgeIds = pendingEdgeWrites
        pendingNodeWrites.removeAll()
        pendingEdgeWrites.removeAll()
        let nodesToSave = nodeIds.compactMap { nodes[$0] }
        let edgesToSave = edgeIds.compactMap { edges[$0] }
        let dbActor = self.dbActor
        do {
            try await dbActor.saveProject(snapshotProject)
            for node in nodesToSave { try await dbActor.saveNode(node) }
            for edge in edgesToSave { try await dbActor.saveEdge(edge) }
            for node in snapshotNodes { try await dbActor.saveNode(node) }
            for edge in snapshotEdges { try await dbActor.saveEdge(edge) }
        } catch {
            self.errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Debounced Writes
    
    private func scheduleDebouncedWrite(nodeId: UUID) {
        pendingNodeWrites.insert(nodeId)
        
        // Cancel previous debounce
        debounceWorkItem?.cancel()
        
        // Schedule new debounce
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.flushPendingWrites()
            }
        }
        debounceWorkItem = workItem
        
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
    
    private func scheduleDebouncedWrite(edgeId: UUID) {
        pendingEdgeWrites.insert(edgeId)
        
        // Cancel previous debounce
        debounceWorkItem?.cancel()
        
        // Schedule new debounce
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.flushPendingWrites()
            }
        }
        debounceWorkItem = workItem
        
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
    
    private func flushPendingWrites() {
        // Snapshot pending IDs and clear sets on main actor
        let nodeIds = pendingNodeWrites
        let edgeIds = pendingEdgeWrites
        pendingNodeWrites.removeAll()
        pendingEdgeWrites.removeAll()

        // Capture models to save
        let nodesToSave = nodeIds.compactMap { nodes[$0] }
        let edgesToSave = edgeIds.compactMap { edges[$0] }
        let dbActor = self.dbActor
        
        // Perform I/O off the main actor
        Task { [weak self, dbActor, nodesToSave, edgesToSave] in
            do {
                for node in nodesToSave {
                    try await dbActor.saveNode(node)
                }
                for edge in edgesToSave {
                    try await dbActor.saveEdge(edge)
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Failed to save pending changes: \(error.localizedDescription)"
                }
            }
        }
        
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
    }
    
    // MARK: - Analytics Tracking
    
    /// Track team member attachment/change for analytics
    func trackTeamMemberUsage(
        nodeId: UUID,
        roleId: String,
        roleName: String,
        roleCategory: String,
        experienceLevel: String,
        actionType: TeamMemberUsageEvent.ActionType
    ) {
        guard let userId = FirebaseAuthService.shared.currentUser?.uid else { return }
        guard nodes[nodeId] != nil else { return }
        
        Task {
            await AnalyticsService.shared.trackTeamMemberUsage(
                userId: userId,
                projectId: project.id,
                nodeId: nodeId,
                roleId: roleId,
                roleName: roleName,
                roleCategory: roleCategory,
                experienceLevel: experienceLevel,
                actionType: actionType
            )
            
            // If team member was used in generation, update metadata
            if actionType == .used {
                if var metadata = FirebaseDataService.shared.userAccount?.metadata {
                    metadata.totalTeamMembersUsed += 1
                    await FirebaseDataService.shared.updateUserMetadata(userId: userId, metadata: metadata)
                }
            }
        }
    }
}
