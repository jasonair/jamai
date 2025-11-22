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
    
    init(onTap: @escaping () -> Void, shouldFocusOnTap: Bool = true, isNodeSelected: Bool = true) {
        self.onTap = onTap
        self.shouldFocusOnTap = shouldFocusOnTap
        self.isNodeSelected = isNodeSelected
    }
    
    func makeNSView(context: Context) -> TapThroughView {
        let view = TapThroughView()
        view.onTap = onTap
        view.shouldFocusOnTap = shouldFocusOnTap
        view.isNodeSelected = isNodeSelected
        return view
    }
    
    func updateNSView(_ nsView: TapThroughView, context: Context) {
        nsView.onTap = onTap
        nsView.shouldFocusOnTap = shouldFocusOnTap
        nsView.isNodeSelected = isNodeSelected
    }
}

final class TapThroughView: NSView {
    var onTap: (() -> Void)?
    var shouldFocusOnTap: Bool = true
    var isNodeSelected: Bool = true
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
