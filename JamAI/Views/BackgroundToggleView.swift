//
//  BackgroundToggleView.swift
//  JamAI
//
//  Background toggle control for switching between grid and dots
//

import SwiftUI

struct BackgroundToggleView: View {
    @Binding var showDots: Bool
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 8) {
            // Grid button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDots = false
                }
            }) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
                    .background(showDots ? Color.clear : Color.accentColor.opacity(0.1))
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Grid Background")
            
            // Dots button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDots = true
                }
            }) {
                Image(systemName: "circle.grid.2x2")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
                    .background(showDots ? Color.accentColor.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Dots Background")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
    }
}
