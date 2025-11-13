//
//  ModalTrackingView.swift
//  JamAI
//
//  Tracks when a view's window appears/disappears and notifies ModalCoordinator
//

import SwiftUI
import AppKit

/// NSView that detects when it's added to/removed from a window
/// Used to track Settings and other system windows
private class WindowTrackingView: NSView {
    var onWindowAppear: (() -> Void)?
    var onWindowDisappear: (() -> Void)?
    private var hasTrackedAppear = false
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        if window != nil && !hasTrackedAppear {
            hasTrackedAppear = true
            onWindowAppear?()
        } else if window == nil && hasTrackedAppear {
            hasTrackedAppear = false
            onWindowDisappear?()
        }
    }
}

/// SwiftUI wrapper that tracks when view enters/exits window hierarchy
struct ModalTrackingView: NSViewRepresentable {
    
    func makeNSView(context: Context) -> NSView {
        let view = WindowTrackingView()
        view.onWindowAppear = {
            Task { @MainActor in
                ModalCoordinator.shared.modalDidOpen()
            }
        }
        view.onWindowDisappear = {
            Task { @MainActor in
                ModalCoordinator.shared.modalDidClose()
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // No updates needed
    }
}
