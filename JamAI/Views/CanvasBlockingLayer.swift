//
//  CanvasBlockingLayer.swift
//  JamAI
//
//  Blocking layer that prevents scroll and interaction leakage to canvas when modals are open
//

import SwiftUI
import AppKit

/// NSView that intercepts and swallows ALL scroll wheel events
/// Used as a full-screen blocking layer when modals are open
private class ScrollBlockingView: NSView {
    override func scrollWheel(with event: NSEvent) {
        // Swallow all scroll events - don't pass to super or responder chain
        // This prevents scroll from reaching the canvas behind
    }
    
    override func mouseDown(with event: NSEvent) {
        // Swallow mouse events
    }
    
    override func rightMouseDown(with event: NSEvent) {
        // Swallow right-click events
    }
    
    override func otherMouseDown(with event: NSEvent) {
        // Swallow other mouse button events
    }
}

/// Full-screen blocking layer that prevents all canvas interactions when modals are open
/// This is the web equivalent of a blocking overlay div with no scroll
struct CanvasBlockingLayer: NSViewRepresentable {
    
    func makeNSView(context: Context) -> NSView {
        let view = ScrollBlockingView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // No updates needed
    }
}
