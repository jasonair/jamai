//
//  Edge.swift
//  JamAI
//
//  Represents connections between nodes
//

import Foundation
import SwiftUI

struct Edge: Identifiable, Codable, Equatable {
    let id: UUID
    var projectId: UUID
    var sourceId: UUID
    var targetId: UUID
    var color: String?
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        projectId: UUID,
        sourceId: UUID,
        targetId: UUID,
        color: String? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.sourceId = sourceId
        self.targetId = targetId
        self.color = color
        self.createdAt = Date()
    }
    
    static func == (lhs: Edge, rhs: Edge) -> Bool {
        lhs.id == rhs.id
    }
}
