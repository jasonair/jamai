//
//  WorldLayerView.swift
//  JamAI
//
//  Hosts the edge layer and node items in world coordinates.
//

import SwiftUI

struct WorldLayerView: View {
    let nodes: [Node]
    let nodeViewBuilder: (Node) -> AnyView
    /// Set of multi-selected node IDs - triggers re-render when selection changes
    var selectedNodeIds: Set<UUID> = []
    /// Version counter to force re-renders without recreating views
    var selectionVersion: Int = 0
    
    var body: some View {
        ZStack {
            // Nodes are pre-sorted by creation date in CanvasView (newest appear on top)
            ForEach(nodes) { node in
                nodeViewBuilder(node)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Force re-render when selection changes without recreating views
        .onChange(of: selectedNodeIds) { _, _ in }
    }
}
