//
//  MouseTrackingView.swift
//  JamAI
//
//  Tracks mouse location within the view and publishes it via a Binding.
//

import SwiftUI
#if os(macOS)
import AppKit

struct MouseTrackingView: NSViewRepresentable {
    @Binding var position: CGPoint
    var hasSelectedNode: Bool = false
    var hasOpenModal: Bool = false
    // Returns true if the scroll was handled (consumed) by the canvas, false to
    // let the normal NSResponder chain handle it (e.g. node ScrollViews).
    var onScroll: ((CGFloat, CGFloat) -> Bool)? = nil
    var onCommandClose: (() -> Void)? = nil
    
    func makeNSView(context: Context) -> TrackingNSView {
        let v = TrackingNSView()
        v.onMove = { p in
            // Update binding on main thread
            DispatchQueue.main.async { self.position = p }
        }
        v.onScroll = { dx, dy in self.onScroll?(dx, dy) ?? false }
        v.onCommandClose = self.onCommandClose
        v.hasSelectedNode = self.hasSelectedNode
        v.hasOpenModal = self.hasOpenModal
        return v
    }
    
    func updateNSView(_ nsView: TrackingNSView, context: Context) {
        nsView.onMove = { p in DispatchQueue.main.async { self.position = p } }
        nsView.onScroll = { dx, dy in self.onScroll?(dx, dy) ?? false }
        nsView.onCommandClose = self.onCommandClose
        nsView.hasSelectedNode = self.hasSelectedNode
        nsView.hasOpenModal = self.hasOpenModal
    }
    
    final class TrackingNSView: NSView {
        var onMove: ((CGPoint) -> Void)?
        private var tracking: NSTrackingArea?
        // Returns true if the scroll event was handled by the canvas.
        var onScroll: ((CGFloat, CGFloat) -> Bool)?
        var onCommandClose: (() -> Void)?
        var hasSelectedNode: Bool = false
        var hasOpenModal: Bool = false
        private var localMonitor: Any?
        private var keyMonitor: Any?
        
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking = tracking { removeTrackingArea(tracking) }
            let options: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect]
            tracking = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(tracking!)
            window?.acceptsMouseMovedEvents = true
        }
        
        override func mouseMoved(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            let flipped = CGPoint(x: p.x, y: bounds.height - p.y)
            onMove?(flipped)
        }
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor = localMonitor { NSEvent.removeMonitor(monitor); localMonitor = nil }
            if let k = keyMonitor { NSEvent.removeMonitor(k); keyMonitor = nil }
            guard window != nil else { return }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                
                // If a modal is open, pass all scroll events to it
                if self.hasOpenModal {
                    return event
                }
                
                // Forward scroll deltas to SwiftUI. If the handler returns true,
                // the canvas consumed the event (pan). Otherwise, let the normal
                // NSResponder chain handle it so node-internal scrolling works.
                if let handler = self.onScroll {
                    let handled = handler(event.scrollingDeltaX, event.scrollingDeltaY)
                    return handled ? nil : event
                }
                
                return event
            }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "w" {
                    self.onCommandClose?()
                    return nil
                }
                return event
            }
        }
        
        deinit {
            if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
            if let k = keyMonitor { NSEvent.removeMonitor(k) }
        }

        override var acceptsFirstResponder: Bool { true }
    }
}
#endif
