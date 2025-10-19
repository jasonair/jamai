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
    var onScroll: ((CGFloat, CGFloat) -> Void)? = nil
    var onCommandClose: (() -> Void)? = nil
    
    func makeNSView(context: Context) -> TrackingNSView {
        let v = TrackingNSView()
        v.onMove = { p in
            // Update binding on main thread
            DispatchQueue.main.async { self.position = p }
        }
        v.onScroll = { dx, dy in self.onScroll?(dx, dy) }
        v.onCommandClose = self.onCommandClose
        v.hasSelectedNode = self.hasSelectedNode
        return v
    }
    
    func updateNSView(_ nsView: TrackingNSView, context: Context) {
        nsView.onMove = { p in DispatchQueue.main.async { self.position = p } }
        nsView.onScroll = { dx, dy in self.onScroll?(dx, dy) }
        nsView.onCommandClose = self.onCommandClose
        nsView.hasSelectedNode = self.hasSelectedNode
    }
    
    final class TrackingNSView: NSView {
        var onMove: ((CGPoint) -> Void)?
        private var tracking: NSTrackingArea?
        var onScroll: ((CGFloat, CGFloat) -> Void)?
        var onCommandClose: (() -> Void)?
        var hasSelectedNode: Bool = false
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
            onMove?(p)
        }
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor = localMonitor { NSEvent.removeMonitor(monitor); localMonitor = nil }
            if let k = keyMonitor { NSEvent.removeMonitor(k); keyMonitor = nil }
            guard window != nil else { return }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                
                // If modal sheet is open, pass all scroll events to it
                if let mainWindow = NSApp.mainWindow, !mainWindow.sheets.isEmpty {
                    return event
                }
                
                // SIMPLE: Evaluate each scroll event independently
                // No mode locking, no state - just check the current situation
                if self.shouldLetSystemHandleScroll(for: event) {
                    // Mouse is over a node's scroll view AND node is selected
                    return event // Let the scroll view handle it
                } else {
                    // Otherwise, pan the canvas
                    let dxBase = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : CGFloat(event.deltaX)
                    let dyBase = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : CGFloat(event.deltaY)
                    let invertMult: CGFloat = event.isDirectionInvertedFromDevice ? 1.0 : -1.0
                    self.onScroll?(dxBase * invertMult, dyBase * invertMult)
                    return nil // Consume event
                }
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
        
        private func shouldLetSystemHandleScroll(for event: NSEvent) -> Bool {
            guard let window = self.window else { return false }
            let location = event.locationInWindow
            
            // CANVAS BACKGROUND STRATEGY:
            // Check if we're over SwiftUI content (nodes) or empty canvas
            // If over nodes → only scroll node if selected, otherwise do nothing
            // If over empty canvas → pan canvas
            
            guard let contentView = window.contentView,
                  let hitView = contentView.hitTest(location) else {
                return false // No hit, allow canvas pan
            }
            
            // Check if we're over SwiftUI-rendered content (NSHostingView indicates SwiftUI nodes/UI)
            // Walk up to find if this is inside a hosting view
            var currentView: NSView? = hitView
            var foundHostingView = false
            var foundScrollView: NSScrollView? = nil
            
            while currentView != nil {
                // Check for scroll view first
                if let scrollView = currentView as? NSScrollView {
                    foundScrollView = scrollView
                }
                
                // Check if we're in SwiftUI content
                let className = NSStringFromClass(type(of: currentView!))
                if className.contains("NSHostingView") {
                    foundHostingView = true
                    break
                }
                
                currentView = currentView?.superview
            }
            
            // If we didn't find SwiftUI hosting view, we're over empty canvas - allow pan
            if !foundHostingView {
                return false // Allow canvas pan
            }
            
            // We're over SwiftUI content (a node or UI element)
            // Only allow node scroll if node is selected AND we found a scroll view
            if hasSelectedNode, let scrollView = foundScrollView {
                let documentFrame = scrollView.documentView?.frame ?? .zero
                let contentSize = scrollView.contentSize
                let hasVerticalScroll = documentFrame.height > contentSize.height
                return hasVerticalScroll // Allow node scroll
            }
            
            // Over a node but node not selected, or no scroll view - block canvas pan
            return true
        }
        
        override var acceptsFirstResponder: Bool { true }
    }
}
#endif
