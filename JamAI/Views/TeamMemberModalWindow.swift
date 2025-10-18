//
//  TeamMemberModalWindow.swift
//  JamAI
//
//  Native macOS modal window for team member selection
//

import SwiftUI
import AppKit

@MainActor
class TeamMemberModalWindow: NSObject, NSWindowDelegate {
    private var window: NSPanel?
    private let existingMember: TeamMember?
    private let onSave: (TeamMember) -> Void
    private let onRemove: (() -> Void)?
    
    init(
        existingMember: TeamMember?,
        onSave: @escaping (TeamMember) -> Void,
        onRemove: (() -> Void)?
    ) {
        self.existingMember = existingMember
        self.onSave = onSave
        self.onRemove = onRemove
        super.init()
    }
    
    func show() {
        
        // Create the SwiftUI content view
        let contentView = TeamMemberModal(
            existingMember: existingMember,
            onSave: { [weak self] member in
                self?.onSave(member)
                self?.close()
            },
            onRemove: onRemove != nil ? { [weak self] in
                self?.onRemove?()
                self?.close()
            } : nil,
            onDismiss: { [weak self] in
                self?.close()
            }
        )
        
        // Wrap in event-capturing container
        let wrappedContent = ZStack {
            // Background that captures all events
            Color.clear
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            contentView
        }
        
        // Wrap in NSHostingController
        let hostingController = NSHostingController(rootView: wrappedContent)
        
        // Use consistent size that works for both states
        let panelWidth: CGFloat = 600
        let panelHeight: CGFloat = 620 // Height that fits configuration section
        
        hostingController.view.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        
        // Make hosting view handle events properly
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.masksToBounds = false // Allow content to size properly
        
        // Create NSPanel
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        panel.title = existingMember == nil ? "Add Team Member" : "Edit Team Member"
        panel.contentView = hostingController.view
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        
        // Configure as proper modal panel
        panel.level = .modalPanel
        panel.isFloatingPanel = false
        panel.worksWhenModal = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        
        // Ensure it captures all mouse events
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        
        self.window = panel
        
        // CRITICAL: Make the panel the key window BEFORE showing as sheet
        panel.makeKeyAndOrderFront(nil)
        
        // Show as modal (blocks parent window)
        if let parentWindow = NSApp.mainWindow {
            
            // Ensure parent becomes inactive
            parentWindow.makeFirstResponder(nil)
            
            parentWindow.beginSheet(panel) { [weak self] response in
                self?.window = nil
            }
            
            // Make absolutely sure the sheet is key
            DispatchQueue.main.async {
                panel.makeKey()
            }
        } else {
            // Fallback to modal dialog if no parent window
            NSApp.runModal(for: panel)
            panel.orderOut(nil)
            self.window = nil
        }
    }
    
    func close() {
        guard let window = window else { return }
        
        if let parentWindow = NSApp.mainWindow, parentWindow.sheets.contains(window) {
            parentWindow.endSheet(window)
        } else {
            NSApp.stopModal()
        }
        
        window.orderOut(nil)
        self.window = nil
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        if let window = window {
            if let parentWindow = NSApp.mainWindow, parentWindow.sheets.contains(window) {
                // Already handled by sheet end
            } else {
                NSApp.stopModal()
            }
        }
        self.window = nil
    }
}
