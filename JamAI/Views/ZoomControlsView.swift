//
//  ZoomControlsView.swift
//  JamAI
//
//  Floating zoom controls for canvas zoom operations
//

import SwiftUI

struct ZoomControlsView: View {
    let currentZoom: CGFloat
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onZoomTo: (CGFloat) -> Void
    let onZoomFit: () -> Void
    let onSearch: () -> Void
    let onCreateChat: () -> Void
    let onCreateNote: () -> Void
    let onCreateTitle: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    /// Standard zoom levels used in design apps
    private static let zoomLevels: [CGFloat] = [0.1, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5]
    
    /// Format zoom as percentage string
    private var zoomPercentage: String {
        let percent = Int(round(currentZoom * 100))
        return "\(percent)%"
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Zoom Out
            ZoomTextButton(text: "−", action: onZoomOut, tooltip: "Zoom Out (⌘-)")
            
            // Zoom Level Dropdown
            ZoomLevelMenu(
                currentZoom: currentZoom,
                zoomLevels: Self.zoomLevels,
                zoomPercentage: zoomPercentage,
                onZoomTo: onZoomTo,
                onZoomFit: onZoomFit
            )
            
            // Zoom In
            ZoomTextButton(text: "+", action: onZoomIn, tooltip: "Zoom In (⌘+)")
            
            Divider()
                .frame(width: 1, height: 20)
            
            // Search
            ZoomButton(icon: "magnifyingglass", action: onSearch, tooltip: "Search Conversations (⌘F)")
            
            Divider()
                .frame(width: 1, height: 20)
            
            // Creation tools
            ZoomButton(icon: "plus.circle", action: onCreateChat, tooltip: "New Chat")
            ZoomButton(icon: "doc.text", action: onCreateNote, tooltip: "New Note")
            ZoomButton(icon: "textformat.size", action: onCreateTitle, tooltip: "New Title")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
    }
}

// MARK: - Zoom Level Menu

struct ZoomLevelMenu: View {
    let currentZoom: CGFloat
    let zoomLevels: [CGFloat]
    let zoomPercentage: String
    let onZoomTo: (CGFloat) -> Void
    let onZoomFit: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Menu {
            ForEach(zoomLevels, id: \.self) { level in
                Button(action: { onZoomTo(level) }) {
                    HStack {
                        Text("\(Int(level * 100))%")
                        Spacer()
                        if isCurrentLevel(level) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            
            Divider()
            
            Button(action: onZoomFit) {
                HStack {
                    Text("Zoom to Fit")
                    Spacer()
                    Text("⌘0")
                        .foregroundColor(.secondary)
                }
            }
        } label: {
            Text(zoomPercentage)
                .font(.system(size: 12, weight: isHovering ? .semibold : .medium))
                .monospacedDigit()
                .frame(minWidth: 48)
                .frame(height: 28)
                .background(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
                .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering in
            isHovering = hovering
        }
        .help("Zoom Level")
    }
    
    private func isCurrentLevel(_ level: CGFloat) -> Bool {
        abs(currentZoom - level) < 0.01
    }
}

struct ZoomButton: View {
    let icon: String
    let action: () -> Void
    let tooltip: String
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: isHovering ? .medium : .regular))
                .frame(width: 32, height: 28)
                .background(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovering = hovering
        }
        .help(tooltip)
    }
}

struct ZoomTextButton: View {
    let text: String
    let action: () -> Void
    let tooltip: String
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12, weight: isHovering ? .semibold : .medium))
                .frame(minWidth: text == "100%" ? 40 : 28)
                .frame(height: 28)
                .background(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovering = hovering
        }
        .help(tooltip)
    }
}
