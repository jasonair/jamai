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
    @Published var isModalPresented = false
    private var currentModalWindow: TeamMemberModalWindow?
    
    func showTeamMemberModal(
        existingMember: TeamMember?,
        onSave: @escaping (TeamMember) -> Void,
        onRemove: (() -> Void)?
    ) {
        
        // Close existing modal if any
        dismissTeamMemberModal()
        
        // Create and show new modal window
        let modalWindow = TeamMemberModalWindow(
            existingMember: existingMember,
            onSave: onSave,
            onRemove: onRemove,
            onDismiss: { [weak self] in
                self?.isModalPresented = false
            }
        )
        
        currentModalWindow = modalWindow
        isModalPresented = true
        modalWindow.show()
    }
    
    func dismissTeamMemberModal() {
        currentModalWindow?.close()
        currentModalWindow = nil
        isModalPresented = false
    }
}
