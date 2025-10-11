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
            // Sort by creation date so newest nodes appear on top
            ForEach(nodes.sorted(by: { $0.createdAt < $1.createdAt })) { node in
                nodeViewBuilder(node)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
