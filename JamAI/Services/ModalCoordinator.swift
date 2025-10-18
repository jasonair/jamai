//
//  ModalCoordinator.swift
//  JamAI
//
//  Coordinates modal presentation using native macOS windows
//

import SwiftUI
import Combine

@MainActor
class ModalCoordinator: ObservableObject {
    private var currentModalWindow: TeamMemberModalWindow?
    
    func showTeamMemberModal(
        existingMember: TeamMember?,
        onSave: @escaping (TeamMember) -> Void,
        onRemove: (() -> Void)?
    ) {
        print("[ModalCoordinator] Showing team member modal window")
        
        // Close existing modal if any
        dismissTeamMemberModal()
        
        // Create and show new modal window
        let modalWindow = TeamMemberModalWindow(
            existingMember: existingMember,
            onSave: onSave,
            onRemove: onRemove
        )
        
        currentModalWindow = modalWindow
        modalWindow.show()
    }
    
    func dismissTeamMemberModal() {
        print("[ModalCoordinator] Dismissing team member modal window")
        currentModalWindow?.close()
        currentModalWindow = nil
    }
}
