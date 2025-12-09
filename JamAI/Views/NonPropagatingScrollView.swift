//
//  NonPropagatingScrollView.swift
//  JamAI
//
//  Custom scroll view that blocks scroll event propagation to parent views
//

import SwiftUI
import AppKit

// MARK: - View Modifier Approach

extension View {
    /// Blocks scroll wheel event propagation to prevent the canvas from panning
    /// when scrolling inside a node's content area
    func blockScrollPropagation() -> some View {
        self.overlay(ScrollEventBlocker())
    }
    
    /// Blocks horizontal scrolling completely by finding and modifying the underlying NSScrollView.
    /// Uses VerticalOnlyClipView to constrain bounds to x=0, preventing any horizontal movement.
    func lockHorizontalScroll() -> some View {
        self.background(HorizontalScrollLocker())
    }
}

/// Background view that finds the parent NSScrollView and installs a VerticalOnlyClipView
/// to completely block horizontal scrolling at the source level.
private struct HorizontalScrollLocker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = HorizontalScrollLockingView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-apply lock on updates in case scroll view was recreated
        if let lockingView = nsView as? HorizontalScrollLockingView {
            lockingView.applyHorizontalLock()
        }
    }
}

/// Helper view that finds and modifies the parent NSScrollView
private class HorizontalScrollLockingView: NSView {
    private weak var lockedScrollView: NSScrollView?
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Apply lock immediately and with delays to catch late-created scroll views
        applyHorizontalLock()
        DispatchQueue.main.async { [weak self] in
            self?.applyHorizontalLock()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.applyHorizontalLock()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.applyHorizontalLock()
        }
    }
    
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        applyHorizontalLock()
    }
    
    func applyHorizontalLock() {
        // Find the parent NSScrollView
        var currentView: NSView? = self.superview
        while currentView != nil {
            if let scrollView = currentView as? NSScrollView {
                // Check if we already have a VerticalOnlyClipView installed
                if !(scrollView.contentView is VerticalOnlyClipViewPublic) {
                    // Install our custom clip view
                    let currentBounds = scrollView.contentView.bounds
                    let verticalClipView = VerticalOnlyClipViewPublic()
                    verticalClipView.drawsBackground = false
                    
                    // Preserve the document view
                    let documentView = scrollView.documentView
                    scrollView.contentView = verticalClipView
                    scrollView.documentView = documentView
                    
                    // Restore bounds
                    verticalClipView.setBoundsOrigin(NSPoint(x: 0, y: currentBounds.origin.y))
                    
                    // Disable horizontal scroller and elasticity
                    scrollView.hasHorizontalScroller = false
                    scrollView.horizontalScrollElasticity = .none
                    
                    lockedScrollView = scrollView
                }
                break
            }
            currentView = currentView?.superview
        }
    }
}

/// Public version of VerticalOnlyClipView that can be used by the modifier.
/// Prevents any horizontal scrolling by constraining bounds to x=0.
class VerticalOnlyClipViewPublic: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrainedBounds = super.constrainBoundsRect(proposedBounds)
        // Lock horizontal position to 0 - prevents any horizontal scrolling
        constrainedBounds.origin.x = 0
        return constrainedBounds
    }
    
    override func scroll(to newOrigin: NSPoint) {
        // Only allow vertical scrolling by forcing x to 0
        var constrainedOrigin = newOrigin
        constrainedOrigin.x = 0
        super.scroll(to: constrainedOrigin)
    }
}

/// Invisible overlay that captures and blocks scroll events while allowing other interactions
private struct ScrollEventBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollBlockingView {
        return ScrollBlockingView()
    }
    
    func updateNSView(_ nsView: ScrollBlockingView, context: Context) {
        // Nothing to update
    }
}

/// Custom NSView that intercepts scroll wheel events and stops propagation
/// while allowing all other events to pass through
private class ScrollBlockingView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Make completely transparent and non-interactive except for scrolling
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func scrollWheel(with event: NSEvent) {
        // Intercept scroll and pass to first scroll view in hierarchy
        // Find the nearest NSScrollView in the view hierarchy
        var currentView: NSView? = self.superview
        while currentView != nil {
            if let scrollView = currentView as? NSScrollView {
                scrollView.scrollWheel(with: event)
                // Don't propagate further - this stops canvas pan
                return
            }
            currentView = currentView?.superview
        }
        // If no scroll view found, just block (don't propagate)
    }
    
    override var acceptsFirstResponder: Bool {
        return false // Don't steal focus
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // For scroll events to reach us, we need to be in the view hierarchy
        // But we want clicks to pass through to views below
        // Return self only if there's a scroll view below us that can handle it
        var currentView: NSView? = self.superview
        while currentView != nil {
            if currentView is NSScrollView {
                // There's a scroll view in our hierarchy, intercept scroll events
                return self
            }
            currentView = currentView?.superview
        }
        // No scroll view found, pass through
        return nil
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return false
    }
    
    // Pass all non-scroll mouse events to the next responder
    override func mouseDown(with event: NSEvent) {
        // Don't handle, let it pass through the responder chain
        super.mouseDown(with: event)
    }
    
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
    }
    
    override func rightMouseDown(with event: NSEvent) {
        super.rightMouseDown(with: event)
    }
}

/// A SwiftUI wrapper around NSScrollView that prevents scroll events from propagating to parent views.
/// When the scroll view has reached the end of its content in a direction, it still blocks the scroll
/// event instead of passing it to the parent (preventing canvas pan).
struct NonPropagatingScrollViewWrapper<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        ScrollViewWithBlockedPropagation {
            content
        }
    }
}

/// Internal representable wrapper
private struct ScrollViewWithBlockedPropagation<Content: View>: NSViewRepresentable {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NonPropagatingNSScrollView()
        let hostingView = NSHostingView(rootView: content)
        
        scrollView.documentView = hostingView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        
        // Disable horizontal elastic bounce to prevent content shifting left/right during trackpad scroll
        scrollView.horizontalScrollElasticity = .none
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let hostingView = scrollView.documentView as? NSHostingView<Content> {
            hostingView.rootView = content
            hostingView.invalidateIntrinsicContentSize()
            
            // Ensure width matches scroll view
            let width = scrollView.contentSize.width
            if hostingView.frame.width != width {
                hostingView.frame.size.width = width
            }
        }
        
        // Ensure horizontal elasticity stays disabled
        scrollView.horizontalScrollElasticity = .none
        
        // Reset horizontal offset if it drifted from trackpad gestures
        let clipView = scrollView.contentView
        if clipView.bounds.origin.x != 0 {
            clipView.scroll(to: NSPoint(x: 0, y: clipView.bounds.origin.y))
            scrollView.reflectScrolledClipView(clipView)
        }
    }
}

/// Custom NSClipView that prevents any horizontal scrolling.
/// By constraining bounds to always have x=0, we completely block horizontal movement.
private class VerticalOnlyClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrainedBounds = super.constrainBoundsRect(proposedBounds)
        // Lock horizontal position to 0 - prevents any horizontal scrolling
        constrainedBounds.origin.x = 0
        return constrainedBounds
    }
    
    override func scroll(to newOrigin: NSPoint) {
        // Only allow vertical scrolling by forcing x to 0
        var constrainedOrigin = newOrigin
        constrainedOrigin.x = 0
        super.scroll(to: constrainedOrigin)
    }
}

/// Custom NSScrollView that intercepts scroll wheel events and prevents propagation to parent views.
/// This ensures that scrolling within a node's content area doesn't cause the canvas to pan.
private class NonPropagatingNSScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupVerticalOnlyClipView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupVerticalOnlyClipView()
    }
    
    private func setupVerticalOnlyClipView() {
        // Replace the default clip view with our vertical-only version
        let verticalClipView = VerticalOnlyClipView()
        verticalClipView.drawsBackground = false
        self.contentView = verticalClipView
    }
    
    override func scrollWheel(with event: NSEvent) {
        // Always handle scroll ourselves and never propagate to parent
        // This prevents the canvas from moving when scrolling within node content
        
        guard let documentView = documentView else {
            // No document view, don't propagate
            return
        }
        
        // Calculate if we have scrollable content
        let contentView = self.contentView
        let bounds = contentView.bounds
        let documentFrame = documentView.frame
        
        let scrollDeltaY = event.scrollingDeltaY
        let canScrollUp = bounds.origin.y > 0
        let canScrollDown = bounds.maxY < documentFrame.maxY
        
        // Only handle scroll if we can scroll in that direction
        if scrollDeltaY < 0 {
            // Scrolling down
            if canScrollDown {
                super.scrollWheel(with: event)
            }
            // Don't propagate even if we can't scroll
        } else if scrollDeltaY > 0 {
            // Scrolling up
            if canScrollUp {
                super.scrollWheel(with: event)
            }
            // Don't propagate even if we can't scroll
        } else if event.scrollingDeltaX != 0 {
            // Horizontal scroll - don't handle or propagate
            return
        }
        
        // Explicitly block propagation by not calling nextResponder?.scrollWheel
        // This is the key difference from the MarkdownText version
    }
}
