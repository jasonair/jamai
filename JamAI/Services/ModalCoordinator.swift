//
//  ModalCoordinator.swift
//  JamAI
//
//  Coordinates modal presentation using native macOS windows
//  Tracks ALL modal states to enable canvas blocking layer
//

import SwiftUI
import Combine
import AppKit

@MainActor
class ModalCoordinator: ObservableObject {
    static let shared = ModalCoordinator()
    
    @Published var isModalPresented = false
    private var currentTeamMemberWindow: TeamMemberModalWindow?
    private var currentSettingsWindow: SettingsModalWindow?
    private var currentUserSettingsWindow: UserSettingsModalWindow?
    private var currentSearchWindow: SearchModalWindow?
    
    // Track different modal types
    private var activeModalCount = 0
    
    func showTeamMemberModal(
        existingMember: TeamMember?,
        projectTeamMembers: [(nodeName: String, teamMember: TeamMember, role: Role?)],
        onSave: @escaping (TeamMember) -> Void,
        onRemove: (() -> Void)?
    ) {
        
        // Close existing modal if any
        dismissTeamMemberModal()
        
        // Create and show new modal window
        let modalWindow = TeamMemberModalWindow(
            existingMember: existingMember,
            projectTeamMembers: projectTeamMembers,
            onSave: onSave,
            onRemove: onRemove,
            onDismiss: { [weak self] in
                self?.modalDidClose()
            }
        )
        
        currentTeamMemberWindow = modalWindow
        modalDidOpen()
        modalWindow.show()
    }
    
    func dismissTeamMemberModal() {
        currentTeamMemberWindow?.close()
        currentTeamMemberWindow = nil
    }
    
    func showSettingsModal(viewModel: CanvasViewModel, appState: AppState) {
        // Close existing if any
        dismissSettingsModal()
        
        let modalWindow = SettingsModalWindow(
            viewModel: viewModel,
            appState: appState,
            onDismiss: { [weak self] in
                self?.modalDidClose()
            }
        )
        
        currentSettingsWindow = modalWindow
        modalDidOpen()
        modalWindow.show()
    }
    
    func dismissSettingsModal() {
        currentSettingsWindow?.close()
        currentSettingsWindow = nil
    }
    
    func showUserSettingsModal() {
        // Close existing if any
        dismissUserSettingsModal()
        
        let modalWindow = UserSettingsModalWindow(
            onDismiss: { [weak self] in
                self?.modalDidClose()
            }
        )
        
        currentUserSettingsWindow = modalWindow
        modalDidOpen()
        modalWindow.show()
    }
    
    func dismissUserSettingsModal() {
        currentUserSettingsWindow?.close()
        currentUserSettingsWindow = nil
    }
    
    func showSearchModal(viewModel: ConversationSearchViewModel) {
        // Close existing if any
        dismissSearchModal()
        
        let modalWindow = SearchModalWindow(
            viewModel: viewModel,
            onDismiss: { [weak self] in
                self?.modalDidClose()
            }
        )
        
        currentSearchWindow = modalWindow
        modalDidOpen()
        modalWindow.show()
    }
    
    func dismissSearchModal() {
        currentSearchWindow?.close()
        currentSearchWindow = nil
    }
    
    // Generic modal tracking for any window/sheet
    func modalDidOpen() {
        activeModalCount += 1
        updateModalState()
    }
    
    func modalDidClose() {
        activeModalCount = max(0, activeModalCount - 1)
        updateModalState()
    }
    
    private func updateModalState() {
        isModalPresented = activeModalCount > 0
    }
}

