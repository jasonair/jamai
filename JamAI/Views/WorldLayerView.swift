//
//  WorldLayerView.swift
//  JamAI
//
//  Hosts the edge layer and node items in world coordinates.
//

import SwiftUI

struct WorldLayerView: View {
    let edges: [Edge]
    let frames: [UUID: CGRect]
    let nodes: [Node]
    let zoom: CGFloat
    let positionsVersion: Int
    let nodeViewBuilder: (Node) -> AnyView
    
    var body: some View {
        ZStack {
            EdgeLayer(
                edges: edges,
                frames: frames,
                zoom: zoom
            )
            .id("edges-\(positionsVersion)")
            
            ForEach(nodes) { node in
                nodeViewBuilder(node)
            }
        }
    }
}
