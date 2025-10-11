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
    
    func makeNSView(context: Context) -> TapThroughView {
        let view = TapThroughView()
        view.onTap = onTap
        return view
    }
    
    func updateNSView(_ nsView: TapThroughView, context: Context) {
        nsView.onTap = onTap
    }
}

final class TapThroughView: NSView {
    var onTap: (() -> Void)?
    private var clickMonitor: Any?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupMonitor()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMonitor()
    }
    
    private func setupMonitor() {
        // Use local event monitor to catch mouse down events
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, let window = self.window else { return event }
            
            // Check if click is within our bounds
            let locationInWindow = event.locationInWindow
            let locationInSelf = self.convert(locationInWindow, from: nil)
            
            if self.bounds.contains(locationInSelf) {
                // Trigger the tap callback
                self.onTap?()
            }
            
            // Always return the event to allow text selection and other interactions
            return event
        }
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMonitor()
        } else if clickMonitor == nil {
            setupMonitor()
        }
    }
    
    deinit {
        removeMonitor()
    }
    
    private func removeMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Never intercept hit testing - allow underlying views to handle events
        return nil
    }
}
