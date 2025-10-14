//
//  ProjectTab.swift
//  JamAI
//
//  Model for managing project tabs
//

import Foundation

struct ProjectTab: Identifiable, Hashable {
    let id: UUID
    let projectURL: URL
    let projectName: String
    var viewModel: CanvasViewModel?
    var database: Database?
    
    init(id: UUID = UUID(), projectURL: URL, projectName: String, viewModel: CanvasViewModel? = nil, database: Database? = nil) {
        self.id = id
        self.projectURL = projectURL
        self.projectName = projectName
        self.viewModel = viewModel
        self.database = database
    }
    
    // For Hashable conformance (exclude viewModel and database)
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(projectURL)
    }
    
    static func == (lhs: ProjectTab, rhs: ProjectTab) -> Bool {
        lhs.id == rhs.id && lhs.projectURL == rhs.projectURL
    }
}
