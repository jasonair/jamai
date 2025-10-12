//
//  Edge.swift
//  JamAI
//
//  Represents connections between nodes
//

import Foundation
import SwiftUI

struct Edge: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var projectId: UUID
    var sourceId: UUID
    var targetId: UUID
    var color: String?
    var createdAt: Date
    
    nonisolated init(
        id: UUID = UUID(),
        projectId: UUID,
        sourceId: UUID,
        targetId: UUID,
        color: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.sourceId = sourceId
        self.targetId = targetId
        self.color = color
        self.createdAt = createdAt
    }
    
    static func == (lhs: Edge, rhs: Edge) -> Bool {
        lhs.id == rhs.id
    }
}
