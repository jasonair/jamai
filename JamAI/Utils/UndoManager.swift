//
//  UndoManager.swift
//  JamAI
//
//  Undo/Redo system for canvas operations
//

import Foundation
import SwiftUI
import Combine

enum CanvasAction: Equatable {
    case createNode(Node)
    case deleteNode(Node, connectedEdges: [Edge])
    case updateNode(oldNode: Node, newNode: Node)
    case moveNode(id: UUID, oldPosition: CGPoint, newPosition: CGPoint)
    case createEdge(Edge)
    case deleteEdge(Edge)
    case updateProject(oldProject: Project, newProject: Project)
    
    static func == (lhs: CanvasAction, rhs: CanvasAction) -> Bool {
        switch (lhs, rhs) {
        case (.createNode(let a), .createNode(let b)):
            return a.id == b.id
        case (.deleteNode(let a, _), .deleteNode(let b, _)):
            return a.id == b.id
        case (.updateNode(let a1, let b1), .updateNode(let a2, let b2)):
            return a1.id == a2.id && b1.id == b2.id
        case (.moveNode(let id1, _, _), .moveNode(let id2, _, _)):
            return id1 == id2
        case (.createEdge(let a), .createEdge(let b)):
            return a.id == b.id
        case (.deleteEdge(let a), .deleteEdge(let b)):
            return a.id == b.id
        case (.updateProject(let a1, _), .updateProject(let a2, _)):
            return a1.id == a2.id
        default:
            return false
        }
    }
}

class CanvasUndoManager: ObservableObject {
    private var undoStack: [CanvasAction] = []
    private var redoStack: [CanvasAction] = []
    private let maxSteps = Config.maxUndoSteps
    
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    
    // MARK: - Record Actions
    
    func record(_ action: CanvasAction) {
        print("📝 Recording action: \(action)")
        undoStack.append(action)
        redoStack.removeAll()
        
        // Limit stack size
        if undoStack.count > maxSteps {
            undoStack.removeFirst()
        }
        
        updateState()
        print("📊 Undo stack size: \(undoStack.count), canUndo: \(canUndo)")
    }
    
    // MARK: - Undo/Redo
    
    func undo() -> CanvasAction? {
        guard !undoStack.isEmpty else { return nil }
        
        let action = undoStack.removeLast()
        redoStack.append(action)
        
        updateState()
        return action
    }
    
    func redo() -> CanvasAction? {
        guard !redoStack.isEmpty else { return nil }
        
        let action = redoStack.removeLast()
        undoStack.append(action)
        
        updateState()
        return action
    }
    
    // MARK: - Clear
    
    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        updateState()
    }
    
    // MARK: - Coalescing
    
    func coalesceIfNeeded(_ action: CanvasAction) {
        // Coalesce consecutive move operations on the same node
        if case .moveNode(let id, _, _) = action,
           let lastAction = undoStack.last,
           case .moveNode(let lastId, let lastOldPos, _) = lastAction,
           id == lastId {
            // Remove last action and replace with coalesced version
            undoStack.removeLast()
            undoStack.append(.moveNode(id: id, oldPosition: lastOldPos, newPosition: action.newPosition))
        } else {
            record(action)
        }
    }
    
    private func updateState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}

// Helper extension for moveNode
extension CanvasAction {
    var newPosition: CGPoint {
        if case .moveNode(_, _, let pos) = self {
            return pos
        }
        return .zero
    }
}
