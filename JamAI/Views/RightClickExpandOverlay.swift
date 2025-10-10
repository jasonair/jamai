//
//  RightClickExpandOverlay.swift
//  JamAI
//
//  Non-blocking overlay that shows an "Expand on Selection" menu on right-click
//  Uses local event monitor and never intercepts normal mouse/scroll events.
//

import SwiftUI
import AppKit

struct RightClickExpandOverlay: NSViewRepresentable {
    let onExpand: (String) -> Void
    
    func makeNSView(context: Context) -> RightClickMonitorView {
        let view = RightClickMonitorView()
        view.onExpand = onExpand
        view.wantsLayer = false
        return view
    }
    
    func updateNSView(_ nsView: RightClickMonitorView, context: Context) {
        nsView.onExpand = onExpand
    }
}

final class RightClickMonitorView: NSView {
    var onExpand: ((String) -> Void)?
    private var eventMonitor: Any?
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Never intercept events; allow underlying SwiftUI content to handle everything
        return nil
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        // Local monitor receives events before the target; we don't consume them unless we show our menu
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseUp]) { [weak self] event in
            guard let self = self, let window = self.window else { return event }
            // Only act when the click occurs within our bounds
            let locationInWindow = event.locationInWindow
            let locationInSelf = self.convert(locationInWindow, from: nil)
            guard self.bounds.contains(locationInSelf) else { return event }
            
            // Try to extract currently selected text from first responder
            var selectedText: String? = nil
            if let tv = window.firstResponder as? NSTextView {
                let range = tv.selectedRange()
                if range.length > 0 {
                    let ns = tv.string as NSString
                    selectedText = ns.substring(with: range)
                }
            }
            
            // Show our menu only if there is a non-empty selection
            if let text = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                if event.type == .rightMouseDown {
                    let menu = NSMenu()
                    let item = NSMenuItem(title: "Expand on Selection", action: #selector(self.handleExpand(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = text
                    menu.addItem(item)
                    NSMenu.popUpContextMenu(menu, with: event, for: self)
                    // Swallow to avoid duplicate default menu popping
                    return nil
                }
            }
            return event
        }
    }
    
    deinit {
        removeMonitor()
    }
    
    @objc private func handleExpand(_ sender: NSMenuItem) {
        if let text = sender.representedObject as? String {
            onExpand?(text)
        }
    }
    
    private func removeMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
