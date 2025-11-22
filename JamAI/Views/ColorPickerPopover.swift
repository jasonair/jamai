//
//  ColorPickerPopover.swift
//  JamAI
//
//  FigJam-style color picker popover for node organization
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ColorPickerPopover: View {
    let selectedColorId: String
    let onColorSelected: (String) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(NodeColor.palette.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 8) {
                    ForEach(row) { nodeColor in
                        ColorButton(
                            nodeColor: nodeColor,
                            isSelected: nodeColor.id == selectedColorId,
                            onSelect: {
                                if nodeColor.id == "rainbow" {
                                    openSystemColorPicker()
                                } else {
                                    onColorSelected(nodeColor.id)
                                    dismiss()
                                }
                            }
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 2)
    }

    private func openSystemColorPicker() {
        #if os(macOS)
        MacColorPicker.shared.present { hex in
            onColorSelected(hex)
        }
        dismiss()
        #endif
    }
}

struct ColorButton: View {
    let nodeColor: NodeColor
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            ZStack {
                // Color circle
                if nodeColor.id == "rainbow" {
                    // Rainbow gradient
                    Circle()
                        .fill(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red
                                ]),
                                center: .center
                            )
                        )
                        .frame(width: 32, height: 32)
                } else {
                    Circle()
                        .fill(nodeColor.color)
                        .frame(width: 32, height: 32)
                }
                
                // Selection ring
                if isSelected {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 3)
                        .frame(width: 36, height: 36)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .help(nodeColor.name)
    }
}

// Preview
#Preview {
    ColorPickerPopover(selectedColorId: "blue") { _ in }
        .frame(width: 400, height: 200)
}

#if os(macOS)
final class MacColorPicker {
    static let shared = MacColorPicker()

    private var colorChangeObserver: Any?
    private var windowCloseObserver: Any?
    private var onColorPicked: ((String) -> Void)?
    private var lastCommittedColor: String?

    func present(onPicked: @escaping (String) -> Void) {
        // Clean up existing observers
        cleanup()
        
        onColorPicked = onPicked
        lastCommittedColor = nil

        let panel = NSColorPanel.shared
        panel.showsAlpha = false

        // Observe color changes for live updates
        colorChangeObserver = NotificationCenter.default.addObserver(
            forName: NSColorPanel.colorDidChangeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let color = panel.color
            if let hex = color.hexString {
                self.lastCommittedColor = hex
                self.onColorPicked?(hex)
            }
        }
        
        // Observe window close to ensure final color is committed
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // Commit the last color one final time when panel closes
            if let finalColor = self.lastCommittedColor {
                self.onColorPicked?(finalColor)
            }
            self.cleanup()
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    
    private func cleanup() {
        if let observer = colorChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            colorChangeObserver = nil
        }
        if let observer = windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            windowCloseObserver = nil
        }
        onColorPicked = nil
        lastCommittedColor = nil
    }
    
    deinit {
        cleanup()
    }
}

private extension NSColor {
    var hexString: String? {
        guard let rgbColor = usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(rgbColor.redComponent * 255))
        let g = Int(round(rgbColor.greenComponent * 255))
        let b = Int(round(rgbColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
#endif
