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
        return v
    }
    
    func updateNSView(_ nsView: TrackingNSView, context: Context) {
        nsView.onMove = { p in DispatchQueue.main.async { self.position = p } }
        nsView.onScroll = { dx, dy in self.onScroll?(dx, dy) }
        nsView.onCommandClose = self.onCommandClose
    }
    
    final class TrackingNSView: NSView {
        var onMove: ((CGPoint) -> Void)?
        private var tracking: NSTrackingArea?
        var onScroll: ((CGFloat, CGFloat) -> Void)?
        var onCommandClose: (() -> Void)?
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
                
                // CRITICAL: If sheet is attached, don't process scroll at all
                // Let the sheet window handle ALL scrolling
                if let window = self.window, !window.sheets.isEmpty {
                    print("[MouseTrackingView] Sheet active - scroll event ignored completely")
                    return event // Pass to system (sheet will handle)
                }
                
                if self.shouldLetSystemHandleScroll(for: event) { return event }
                let dxBase = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : CGFloat(event.deltaX)
                let dyBase = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : CGFloat(event.deltaY)
                let invertMult: CGFloat = event.isDirectionInvertedFromDevice ? 1.0 : -1.0
                self.onScroll?(dxBase * invertMult, dyBase * invertMult)
                return nil // consume so the system doesn't double-handle
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
            
            // If a text view (or view inside an NSScrollView) is first responder AND the cursor is inside its scroll region, let system handle.
            if let responderView = window.firstResponder as? NSView {
                let scrollView = (responderView as? NSTextView)?.enclosingScrollView ?? responderView.enclosingScrollView
                if let container = scrollView ?? responderView as NSView? {
                    let rectInWindow = container.convert(container.bounds, to: nil)
                    if rectInWindow.contains(location) { return true }
                }
            }
            
            // Otherwise, allow canvas to pan.
            return false
        }
        
        override var acceptsFirstResponder: Bool { true }
    }
}
#endif
