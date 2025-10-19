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
    }
}

/// Custom NSScrollView that intercepts scroll wheel events and prevents propagation to parent views.
/// This ensures that scrolling within a node's content area doesn't cause the canvas to pan.
private class NonPropagatingNSScrollView: NSScrollView {
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
