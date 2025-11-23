//
//  BackgroundToggleView.swift
//  JamAI
//
//  Background toggle control for switching between grid and dots
//

import SwiftUI

struct BackgroundToggleView: View {
    @Binding var backgroundStyle: CanvasBackgroundStyle
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 8) {
            // Blank button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    backgroundStyle = .blank
                }
            }) {
                Image(systemName: "square")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
                    .background(backgroundStyle == .blank ? Color.accentColor.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Blank Background")
            
            // Dots button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    backgroundStyle = .dots
                }
            }) {
                Image(systemName: "circle.grid.2x2")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
                    .background(backgroundStyle == .dots ? Color.accentColor.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Dots Background")
            
            // Grid button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    backgroundStyle = .grid
                }
            }) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
                    .background(backgroundStyle == .grid ? Color.accentColor.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Grid Background")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
    }
}
