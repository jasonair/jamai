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
    let onMakeNote: (String) -> Void
    let onJamWithThis: (String) -> Void
    
    func makeNSView(context: Context) -> RightClickMonitorView {
        let view = RightClickMonitorView()
        view.onExpand = onExpand
        view.onMakeNote = onMakeNote
        view.onJamWithThis = onJamWithThis
        view.wantsLayer = false
        return view
    }
    
    func updateNSView(_ nsView: RightClickMonitorView, context: Context) {
        nsView.onExpand = onExpand
        nsView.onMakeNote = onMakeNote
        nsView.onJamWithThis = onJamWithThis
    }
}

final class RightClickMonitorView: NSView {
    var onExpand: ((String) -> Void)?
    var onMakeNote: ((String) -> Void)?
    var onJamWithThis: ((String) -> Void)?
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
                    // Dispatch menu presentation asynchronously to avoid priority inversion
                    // The event monitor runs at User-interactive QoS, but menu operations may use lower QoS
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        let menu = NSMenu()
                        let expandItem = NSMenuItem(title: "Expand on Selection", action: #selector(self.handleExpand(_:)), keyEquivalent: "")
                        expandItem.target = self
                        expandItem.representedObject = text
                        menu.addItem(expandItem)
                        let jamItem = NSMenuItem(title: "Jam with this", action: #selector(self.handleJamWithThis(_:)), keyEquivalent: "")
                        jamItem.target = self
                        jamItem.representedObject = text
                        menu.addItem(jamItem)
                        let noteItem = NSMenuItem(title: "Make a Note", action: #selector(self.handleMakeNote(_:)), keyEquivalent: "")
                        noteItem.target = self
                        noteItem.representedObject = text
                        menu.addItem(noteItem)
                        // Pop up menu at the current mouse location
                        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
                    }
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
            // Dispatch to main queue with user-initiated QoS to avoid priority inversion
            DispatchQueue.main.async(qos: .userInitiated) { [weak self] in
                self?.onExpand?(text)
            }
        }
    }
    
    @objc private func handleMakeNote(_ sender: NSMenuItem) {
        if let text = sender.representedObject as? String {
            // Dispatch to main queue with user-initiated QoS to avoid priority inversion
            DispatchQueue.main.async(qos: .userInitiated) { [weak self] in
                self?.onMakeNote?(text)
            }
        }
    }
    
    @objc private func handleJamWithThis(_ sender: NSMenuItem) {
        if let text = sender.representedObject as? String {
            // Dispatch to main queue with user-initiated QoS to avoid priority inversion
            DispatchQueue.main.async(qos: .userInitiated) { [weak self] in
                self?.onJamWithThis?(text)
            }
        }
    }
    
    private func removeMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
