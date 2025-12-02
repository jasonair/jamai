//
//  ZoomControlsView.swift
//  JamAI
//
//  Floating zoom controls for canvas zoom operations
//

import SwiftUI

struct ZoomControlsView: View {
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onZoomReset: () -> Void
    let onZoomFit: () -> Void
    let onSearch: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 6) {
            // Zoom Out
            ZoomTextButton(text: "−", action: onZoomOut, tooltip: "Zoom Out (⌘-)")
            
            // Reset Zoom
            ZoomTextButton(text: "100%", action: onZoomReset, tooltip: "Reset Zoom (⌘0)")
            
            // Zoom In
            ZoomTextButton(text: "+", action: onZoomIn, tooltip: "Zoom In (⌘+)")
            
            Divider()
                .frame(width: 1, height: 20)
            
            // Zoom to Fit
            ZoomButton(icon: "arrow.up.left.and.arrow.down.right", action: onZoomFit, tooltip: "Zoom to Fit All")
            
            Divider()
                .frame(width: 1, height: 20)
            
            // Search
            ZoomButton(icon: "magnifyingglass", action: onSearch, tooltip: "Search Conversations (⌘F)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
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
