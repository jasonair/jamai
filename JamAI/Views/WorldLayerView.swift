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
    
    var body: some View {
        ZStack {
            // Nodes are pre-sorted by creation date in CanvasView (newest appear on top)
            ForEach(nodes) { node in
                nodeViewBuilder(node)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
