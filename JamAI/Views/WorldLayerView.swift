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
            ForEach(nodes) { node in
                nodeViewBuilder(node)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
