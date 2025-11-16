//
//  AppDelegate.swift
//  JamAI
//
//  Created by Cascade on 11/16/25.
//

import AppKit
import SwiftUI

/// Custom App Delegate with a global mouse-event monitor.
/// When any modal is open, this swallows mouse/scroll events for
/// non-modal windows at the NSEvent level so they never reach the
/// canvas or nodes.
class AppDelegate: NSObject, NSApplicationDelegate {
    private var modalMouseBlocker: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Install a local monitor for mouse-related events. This runs
        // before normal event dispatch, so we can consume events for
        // the canvas while leaving modal NSPanel windows fully interactive.
        modalMouseBlocker = NSEvent.addLocalMonitorForEvents(
            matching: [
                .leftMouseDown, .rightMouseDown, .otherMouseDown,
                .leftMouseUp, .rightMouseUp, .otherMouseUp,
                .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                .mouseMoved,
                .scrollWheel, .magnify, .swipe
            ]
        ) { event in
            // Only intervene when a modal is actually presented
            if ModalCoordinator.shared.isModalPresented {
                // If the event is targeting a modal panel window, allow it.
                if let window = event.window, window is NSPanel {
                    return event
                }
                // Otherwise, swallow the event so it never reaches the
                // canvas or any background window.
                return nil
            }
            
            // No active modal: let events flow normally.
            return event
        }
    }
}
