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
    /// Callback to update shift state before tap fires (true if shift was held at click time)
    let onModifiersAtClick: ((Bool) -> Void)?
    
    init(
        onTap: @escaping () -> Void,
        shouldFocusOnTap: Bool = true,
        isNodeSelected: Bool = true,
        shouldProcessTap: ((NSPoint) -> Bool)? = nil,
        onModifiersAtClick: ((Bool) -> Void)? = nil
    ) {
        self.onTap = onTap
        self.shouldFocusOnTap = shouldFocusOnTap
        self.isNodeSelected = isNodeSelected
        self.shouldProcessTap = shouldProcessTap
        self.onModifiersAtClick = onModifiersAtClick
    }
    
    func makeNSView(context: Context) -> TapThroughView {
        let view = TapThroughView()
        view.onTap = onTap
        view.shouldFocusOnTap = shouldFocusOnTap
        view.isNodeSelected = isNodeSelected
        view.shouldProcessTap = shouldProcessTap
        view.onModifiersAtClick = onModifiersAtClick
        return view
    }
    
    func updateNSView(_ nsView: TapThroughView, context: Context) {
        nsView.onTap = onTap
        nsView.shouldFocusOnTap = shouldFocusOnTap
        nsView.isNodeSelected = isNodeSelected
        nsView.shouldProcessTap = shouldProcessTap
        nsView.onModifiersAtClick = onModifiersAtClick
    }
}

final class TapThroughView: NSView {
    var onTap: (() -> Void)?
    var shouldFocusOnTap: Bool = true
    var isNodeSelected: Bool = true
    /// Closure to check if this node should process the tap (z-order check)
    var shouldProcessTap: ((NSPoint) -> Bool)?
    private var clickMonitor: Any?
    private var mouseUpMonitor: Any?
    private var scrollMonitor: Any?
    private var scrollView: NSScrollView?
    private var isActive: Bool = false
    private static weak var activeInstance: TapThroughView?
    
    // Track mouseDown to distinguish tap from drag
    private var pendingClickLocation: NSPoint?
    private var pendingClickInSelf: Bool = false
    private var pendingClickModifiers: NSEvent.ModifierFlags = []
    private let dragThreshold: CGFloat = 5.0  // Match SwiftUI drag gesture minimumDistance
    
    /// Callback to update shift state in CanvasViewModel before tap fires
    var onModifiersAtClick: ((Bool) -> Void)?
    
    /// Static property to store if the last tap had shift held - accessible from anywhere
    /// This is set just before onTap is called, so handlers can check this value
    static var lastTapWasShiftClick: Bool = false
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupMonitors()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMonitors()
    }
    
    private func setupMonitors() {
        // Monitor for mouseDown - just record location, don't trigger tap yet
        // This allows distinguishing between tap (click and release) and drag (click and move)
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self else { return event }
            
            // If a native modal is open, never activate or change focus state.
            if ModalCoordinator.shared.isModalPresented {
                self.pendingClickInSelf = false
                return event
            }
            
            // Check if event is within our bounds
            let locationInWindow = event.locationInWindow
            let locationInSelf = self.convert(locationInWindow, from: nil)
            
            if self.bounds.contains(locationInSelf) {
                // Use hitTest to check if there's a higher-z view at the click point
                // This properly handles UI elements like outline, zoom controls, etc.
                if let window = self.window,
                   let contentView = window.contentView {
                    let locationInContent = contentView.convert(locationInWindow, from: nil)
                    if let hitView = contentView.hitTest(locationInContent) {
                        // Check if the hit view is this TapThroughView or a descendant/ancestor
                        let isHitViewRelatedToSelf = (hitView === self) || hitView.isDescendant(of: self) || self.isDescendant(of: hitView)
                        if !isHitViewRelatedToSelf {
                            // Another view is on top at this location - don't capture this click
                            self.pendingClickInSelf = false
                            return event
                        }
                    }
                }
                
                // Z-ORDER CHECK
                if let shouldProcess = self.shouldProcessTap {
                    if !shouldProcess(locationInWindow) {
                        self.pendingClickInSelf = false
                        return event
                    }
                }
                
                // Record the mouseDown location and modifiers - don't trigger tap yet
                // We'll check on mouseUp if it was a tap or drag
                self.pendingClickLocation = locationInWindow
                self.pendingClickInSelf = true
                self.pendingClickModifiers = event.modifierFlags
                
                #if DEBUG
                print("[TapThroughView] mouseDown captured, shift: \(event.modifierFlags.contains(.shift))")
                #endif
                
                // Activate scroll capturing immediately (this is fine on mouseDown)
                if self.shouldFocusOnTap {
                    if let prev = TapThroughView.activeInstance, prev !== self {
                        prev.isActive = false
                    }
                    TapThroughView.activeInstance = self
                    self.isActive = true
                    if self.scrollView == nil { self.scrollView = self.findScrollView() }
                }
            } else {
                self.pendingClickInSelf = false
            }
            
            return event
        }
        
        // Monitor for mouseUp - only trigger tap if mouse didn't move much (not a drag)
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self = self else { return event }
            
            // Only process if we had a pending click in our bounds
            guard self.pendingClickInSelf,
                  let startLocation = self.pendingClickLocation else {
                return event
            }
            
            // Clear the pending state
            self.pendingClickInSelf = false
            self.pendingClickLocation = nil
            
            // If a modal opened during the click, don't process
            if ModalCoordinator.shared.isModalPresented {
                return event
            }
            
            // Check if mouse moved significantly (drag vs tap)
            let locationInWindow = event.locationInWindow
            let dx = abs(locationInWindow.x - startLocation.x)
            let dy = abs(locationInWindow.y - startLocation.y)
            
            // If movement exceeds threshold, it was a drag - don't trigger tap
            if dx > self.dragThreshold || dy > self.dragThreshold {
                #if DEBUG
                print("[TapThroughView] Not triggering tap - was a drag (dx: \(dx), dy: \(dy))")
                #endif
                return event
            }
            
            // It was a tap (click and release without significant movement)
            let wasShiftHeld = self.pendingClickModifiers.contains(.shift)
            #if DEBUG
            print("[TapThroughView] Triggering tap callback, shift: \(wasShiftHeld)")
            #endif
            
            // Set static property so any tap handler can read the shift state
            TapThroughView.lastTapWasShiftClick = wasShiftHeld
            
            // Also call the optional callback
            self.onModifiersAtClick?(wasShiftHeld)
            
            self.onTap?()
            
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
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
        }
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
        if TapThroughView.activeInstance === self {
            TapThroughView.activeInstance = nil
        }
        pendingClickInSelf = false
        pendingClickLocation = nil
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Never intercept hit testing - stay transparent
        return nil
    }
}
