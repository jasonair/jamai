//
//  TapThroughOverlay.swift
//  JamAI
//
//  Transparent overlay that captures taps while allowing text selection
//

import SwiftUI
import AppKit

struct TapThroughOverlay: NSViewRepresentable {
    let onTap: () -> Void
    let shouldFocusOnTap: Bool
    let isNodeSelected: Bool
    /// Closure to check if this node should process the tap (z-order check)
    /// Returns true if this is the topmost node at the click point
    let shouldProcessTap: ((NSPoint) -> Bool)?
    
    init(
        onTap: @escaping () -> Void,
        shouldFocusOnTap: Bool = true,
        isNodeSelected: Bool = true,
        shouldProcessTap: ((NSPoint) -> Bool)? = nil
    ) {
        self.onTap = onTap
        self.shouldFocusOnTap = shouldFocusOnTap
        self.isNodeSelected = isNodeSelected
        self.shouldProcessTap = shouldProcessTap
    }
    
    func makeNSView(context: Context) -> TapThroughView {
        let view = TapThroughView()
        view.onTap = onTap
        view.shouldFocusOnTap = shouldFocusOnTap
        view.isNodeSelected = isNodeSelected
        view.shouldProcessTap = shouldProcessTap
        return view
    }
    
    func updateNSView(_ nsView: TapThroughView, context: Context) {
        nsView.onTap = onTap
        nsView.shouldFocusOnTap = shouldFocusOnTap
        nsView.isNodeSelected = isNodeSelected
        nsView.shouldProcessTap = shouldProcessTap
    }
}

final class TapThroughView: NSView {
    var onTap: (() -> Void)?
    var shouldFocusOnTap: Bool = true
    var isNodeSelected: Bool = true
    /// Closure to check if this node should process the tap (z-order check)
    var shouldProcessTap: ((NSPoint) -> Bool)?
    private var clickMonitor: Any?
    private var scrollMonitor: Any?
    private var scrollView: NSScrollView?
    private var isActive: Bool = false
    private static weak var activeInstance: TapThroughView?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupMonitors()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMonitors()
    }
    
    private func setupMonitors() {
        // Monitor for clicks to activate scrolling
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self else { return event }
            
            // If a native modal is open, never activate or change focus state.
            // Let the modal window own all interactions.
            if ModalCoordinator.shared.isModalPresented {
                return event
            }
            
            // Check if event is within our bounds
            let locationInWindow = event.locationInWindow
            let locationInSelf = self.convert(locationInWindow, from: nil)
            
            if self.bounds.contains(locationInSelf) {
                // Before triggering tap, check if there's a higher-z view (like outline pane)
                // that should receive this click instead.
                if let window = self.window,
                   let contentView = window.contentView {
                    // Use the content view's frame height for coordinate conversion
                    let contentHeight = contentView.frame.height
                    // Convert window coordinates (origin at bottom-left) to flipped coordinates (origin at top-left)
                    let flippedY = contentHeight - locationInWindow.y
                    
                    // Direct coordinate check for outline pane area
                    // Outline pane: x=20 to 300, y=56 (from top) to bottom
                    // This is a reliable fallback since hitTest may not work correctly with SwiftUI hosting views
                    #if DEBUG
                    print("[TapThroughView] Click at window: (\(locationInWindow.x), \(locationInWindow.y)), flippedY: \(flippedY), contentHeight: \(contentHeight)")
                    #endif
                    if locationInWindow.x >= 20 && locationInWindow.x <= 300 && flippedY >= 56 {
                        // Click is in the outline pane area - don't process this tap
                        #if DEBUG
                        print("[TapThroughView] Blocked - in outline pane area")
                        #endif
                        return event
                    }
                    
                    // Also check zoom controls area (top center) and background toggle (bottom right)
                    // Zoom controls: roughly centered, y < 100 from top
                    let centerX = contentView.frame.width / 2
                    if flippedY >= 60 && flippedY <= 100 && abs(locationInWindow.x - centerX) < 150 {
                        // Click is in zoom controls area
                        return event
                    }
                    
                    // Background toggle: bottom right corner
                    if flippedY >= contentHeight - 80 && locationInWindow.x >= contentView.frame.width - 200 {
                        // Click is in background toggle area
                        return event
                    }
                    
                    // Fallback: use hitTest to check for other overlays
                    let locationInContent = contentView.convert(locationInWindow, from: nil)
                    if let hitView = contentView.hitTest(locationInContent) {
                        // Check if the hit view is NOT related to this TapThroughView
                        let isHitViewRelatedToSelf = (hitView === self) || hitView.isDescendant(of: self) || self.isDescendant(of: hitView)
                        
                        if !isHitViewRelatedToSelf {
                            // The click hit a different view - don't process this tap
                            return event
                        }
                    }
                }
                
                // Z-ORDER CHECK: Before triggering tap, verify this is the topmost node
                // at the click point. This prevents clicks from tunneling through to
                // nodes that are visually behind the topmost node.
                if let shouldProcess = self.shouldProcessTap {
                    // Convert window coordinates to screen-like coordinates for the check
                    // The callback expects coordinates relative to the canvas view
                    if !shouldProcess(locationInWindow) {
                        #if DEBUG
                        print("[TapThroughView] Blocked - not topmost node at click point")
                        #endif
                        return event
                    }
                }
                
                // Trigger the tap callback
                self.onTap?()
                
                // Activate scroll capturing and ensure scroll view is found
                if self.shouldFocusOnTap {
                    // Deactivate previous active instance to avoid multiple interceptors
                    if let prev = TapThroughView.activeInstance, prev !== self {
                        prev.isActive = false
                    }
                    TapThroughView.activeInstance = self
                    self.isActive = true
                    // Find scroll view immediately on click
                    if self.scrollView == nil { self.scrollView = self.findScrollView() }
                }
            }
            // Note: Removed "click outside" deactivation to prevent stampede effect
            // when multiple TapThroughView instances exist. Each click inside a view
            // will naturally activate only that instance.
            
            // Always return the event to allow text selection and other interactions
            return event
        }
        
        // Monitor for scroll wheel events and forward them when active
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self else { return event }
            
            // If a native modal is open, never capture or forward scroll events.
            // This prevents node scroll from hijacking scroll intended for dialogs.
            if ModalCoordinator.shared.isModalPresented {
                return event
            }
            
            // Early exit if not active or node is not selected to reduce processing overhead
            guard self.isActive, self.isNodeSelected else { return event }
            
            // Check if scroll is happening over our bounds
            guard self.window != nil else { return event }
            let locationInWindow = event.locationInWindow
            let locationInSelf = self.convert(locationInWindow, from: nil)
            
            // Only intercept if the scroll is over our bounds
            if self.bounds.contains(locationInSelf) {
                // Resolve an appropriate scroll view under the pointer, or fall back to cached one
                guard let scrollView = self.findScrollView(atWindowLocation: locationInWindow) ?? self.scrollView else {
                    return event
                }

                // If the window's first responder is no longer inside this scroll view's
                // view hierarchy (for example, because another node is now selected),
                // don't hijack scroll events - let the system handle them instead.
                if let window = self.window,
                   let responderView = window.firstResponder as? NSView,
                   !responderView.isDescendant(of: scrollView) {
                    return event
                }

                self.scrollView = scrollView
                scrollView.scrollWheel(with: event)
                return nil // Consume the event so the canvas doesn't pan
            }
            
            return event
        }
    }
    
    private func findScrollView() -> NSScrollView? {
        // Try to find any NSScrollView in the view hierarchy
        var currentView: NSView? = self.superview
        while let view = currentView {
            // Check if this view is a scroll view
            if let scrollView = view as? NSScrollView { return scrollView }
            // Also check subviews recursively
            if let scrollView = findScrollViewInSubviews(of: view) { return scrollView }
            currentView = view.superview
        }
        return nil
    }

    private func findScrollView(atWindowLocation locationInWindow: NSPoint) -> NSScrollView? {
        guard let window = self.window, let contentView = window.contentView else { return nil }
        guard let hitView = contentView.hitTest(locationInWindow) else { return nil }
        var currentView: NSView? = hitView
        while let view = currentView {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            currentView = view.superview
        }
        return nil
    }
    
    private func findScrollViewInSubviews(of view: NSView) -> NSScrollView? {
        for subview in view.subviews {
            if let scrollView = subview as? NSScrollView {
                return scrollView
            }
            if let scrollView = findScrollViewInSubviews(of: subview) {
                return scrollView
            }
        }
        return nil
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMonitors()
        } else if clickMonitor == nil {
            setupMonitors()
        }
    }
    
    deinit {
        removeMonitors()
    }
    
    private func removeMonitors() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
        if TapThroughView.activeInstance === self {
            TapThroughView.activeInstance = nil
        }
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Never intercept hit testing - stay transparent
        return nil
    }
}
