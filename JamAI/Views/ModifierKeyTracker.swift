//
//  ModifierKeyTracker.swift
//  JamAI
//
//  Tracks modifier key states (Shift, Control, Option, Command) for the canvas.
//  Used to enable features like:
//  - Shift+Click for multi-select
//  - Control to temporarily disable snap-to-align
//

import SwiftUI
import AppKit

/// A view that monitors modifier key states and updates bindings
struct ModifierKeyTracker: NSViewRepresentable {
    @Binding var isShiftPressed: Bool
    @Binding var isControlPressed: Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = ModifierKeyTrackingView()
        view.onModifierChange = { flags in
            // Update synchronously - async caused timing issues with tap handling
            isShiftPressed = flags.contains(.shift)
            isControlPressed = flags.contains(.control)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // No update needed
    }
}

/// NSView subclass that monitors modifier key changes
private class ModifierKeyTrackingView: NSView {
    var onModifierChange: ((NSEvent.ModifierFlags) -> Void)?
    private var flagsMonitor: Any?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupMonitor()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMonitor()
    }
    
    private func setupMonitor() {
        // Monitor flag changes (modifier keys)
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.onModifierChange?(event.modifierFlags)
            return event
        }
        
        // Also check current state on setup
        if let currentFlags = NSApp.currentEvent?.modifierFlags {
            onModifierChange?(currentFlags)
        }
    }
    
    deinit {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var shift = false
        @State private var control = false
        
        var body: some View {
            VStack {
                Text("Shift: \(shift ? "Pressed" : "Released")")
                Text("Control: \(control ? "Pressed" : "Released")")
                ModifierKeyTracker(isShiftPressed: $shift, isControlPressed: $control)
                    .frame(width: 0, height: 0)
            }
            .frame(width: 200, height: 100)
        }
    }
    return PreviewWrapper()
}
