//
//  SearchModalWindow.swift
//  JamAI
//
//  Native macOS modal window for conversation search
//

import SwiftUI
import AppKit

@MainActor
class SearchModalWindow: NSObject, NSWindowDelegate {
    private var window: NSPanel?
    private let viewModel: ConversationSearchViewModel
    private let onDismissCallback: (() -> Void)?
    
    init(
        viewModel: ConversationSearchViewModel,
        onDismiss: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onDismissCallback = onDismiss
        super.init()
    }
    
    func show() {
        // Create the SwiftUI content view
        let contentView = SearchModal(
            viewModel: viewModel,
            onDismiss: { [weak self] in
                self?.close()
            }
        )
        
        // Calculate panel size
        let panelWidth: CGFloat = 560
        let panelHeight: CGFloat = 520
        
        // Wrap in event-capturing container with explicit sizing
        let wrappedContent = ZStack(alignment: .topLeading) {
            // Full-size background that captures ALL events across entire panel
            Rectangle()
                .fill(Color(NSColor.windowBackgroundColor))
                .frame(width: panelWidth, height: panelHeight)
                .allowsHitTesting(true)
                .contentShape(Rectangle())
            
            // Make the SwiftUI modal fill the full panel height
            contentView
                .frame(width: panelWidth, height: panelHeight, alignment: .top)
        }
        .frame(width: panelWidth, height: panelHeight)
        .contentShape(Rectangle())
        .allowsHitTesting(true)
        
        // Wrap in NSHostingController
        let hostingController = NSHostingController(rootView: wrappedContent)
        
        // Embed hosting view inside a scroll-routing container
        let containerView = SearchScrollRoutingContentView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        containerView.wantsLayer = true
        hostingController.view.frame = containerView.bounds
        hostingController.view.autoresizingMask = [.width, .height]
        containerView.addSubview(hostingController.view)
        
        // Create NSPanel
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        panel.title = "Search Conversations"
        panel.contentView = containerView
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        
        // Configure as proper modal panel
        panel.level = .modalPanel
        panel.isFloatingPanel = false
        panel.worksWhenModal = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        
        // Ensure it captures all mouse events
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        
        // Ensure content view fills the panel
        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        }
        
        self.window = panel
        
        // Make the panel the key window BEFORE showing as sheet
        panel.makeKeyAndOrderFront(nil)
        
        // Show as modal (blocks parent window)
        if let parentWindow = NSApp.mainWindow {
            // Ensure parent becomes inactive
            parentWindow.makeFirstResponder(nil)
            
            parentWindow.beginSheet(panel) { [weak self] response in
                self?.window = nil
            }
            
            // Make absolutely sure the sheet is key
            DispatchQueue.main.async {
                panel.makeKey()
            }
        } else {
            // Fallback to modal dialog if no parent window
            NSApp.runModal(for: panel)
            panel.orderOut(nil)
            self.window = nil
        }
    }
    
    func close() {
        guard let window = window else { return }
        
        if let parentWindow = NSApp.mainWindow, parentWindow.sheets.contains(window) {
            parentWindow.endSheet(window)
        } else {
            NSApp.stopModal()
        }
        
        window.orderOut(nil)
        self.window = nil
        onDismissCallback?()
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        if let window = window {
            if let parentWindow = NSApp.mainWindow, parentWindow.sheets.contains(window) {
                // Already handled by sheet end
            } else {
                NSApp.stopModal()
            }
        }
        self.window = nil
        onDismissCallback?()
    }
}

// MARK: - Scroll Routing Content View

/// Routes scroll wheel events to the nearest scrollable NSScrollView
final class SearchScrollRoutingContentView: NSView {
    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let preferVertical = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)

        if let hitView = hitTest(point) {
            if let enclosing = hitView.enclosingScrollView {
                if (preferVertical && isVertScrollable(enclosing)) || (!preferVertical && isHorizScrollable(enclosing)) {
                    enclosing.scrollWheel(with: event)
                    return
                }
            }
            if let candidate = findBestScrollView(preferVertical: preferVertical, near: point) {
                candidate.scrollWheel(with: event)
                return
            }
        } else if let candidate = findBestScrollView(preferVertical: preferVertical, near: point) {
            candidate.scrollWheel(with: event)
            return
        }
        // No suitable scroll view found; swallow to avoid background scroll
    }

    private func findBestScrollView(preferVertical: Bool, near point: NSPoint) -> NSScrollView? {
        var all: [NSScrollView] = []
        collectScrollViews(in: self, into: &all)

        let filtered = all.filter { preferVertical ? isVertScrollable($0) : isHorizScrollable($0) }

        if let hit = filtered.first(where: { self.convert($0.frame, from: $0.superview).contains(point) }) {
            return hit
        }
        if let largest = filtered.max(by: { area(of: $0) < area(of: $1) }) {
            return largest
        }
        return all.max(by: { area(of: $0) < area(of: $1) })
    }

    private func area(of sv: NSScrollView) -> CGFloat {
        let f = convert(sv.frame, from: sv.superview)
        return f.width * f.height
    }

    private func collectScrollViews(in view: NSView, into out: inout [NSScrollView]) {
        for sub in view.subviews {
            if let sv = sub as? NSScrollView { out.append(sv) }
            collectScrollViews(in: sub, into: &out)
        }
    }

    private func isVertScrollable(_ sv: NSScrollView) -> Bool {
        guard let doc = sv.documentView else { return false }
        return doc.frame.height > sv.contentSize.height + 0.5
    }

    private func isHorizScrollable(_ sv: NSScrollView) -> Bool {
        guard let doc = sv.documentView else { return false }
        return doc.frame.width > sv.contentSize.width + 0.5
    }
}
