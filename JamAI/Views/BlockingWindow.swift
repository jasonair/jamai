//
//  BlockingWindow.swift
//  JamAI
//
//  Created by Cascade on 11/16/25.
//

import AppKit

/// A custom NSWindow subclass that can be configured to block all mouse events.
/// This is used to completely disable interaction with the main canvas when a modal
/// window is presented, preventing any clicks or scrolls from leaking through.
class BlockingWindow: NSWindow {
    
    /// When true, all mouse-related events (clicks, drags, scrolls) are ignored.
    /// Keyboard events are still processed to allow shortcuts.
    var isBlockingMouseEvents = false
    
    override func sendEvent(_ event: NSEvent) {
        // If blocking is enabled and the event is mouse-related, swallow it.
        if isBlockingMouseEvents && event.type.isMouseEvent {
            return // Do not process or forward the event
        }
        
        // For all other events (like keyboard input) or when not blocking,
        // proceed as normal.
        super.sendEvent(event)
    }
}

extension NSEvent.EventType {
    /// Returns true if the event is a mouse-related event that should be blocked.
    var isMouseEvent: Bool {
        switch self {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged,
             .otherMouseDragged, .mouseMoved, .scrollWheel, .magnify, .swipe:
            return true
        default:
            return false
        }
    }
}
