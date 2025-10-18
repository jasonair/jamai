//
//  ModalOverlay.swift
//  JamAI
//
//  Custom modal overlay that blocks all background interaction
//

import SwiftUI

struct ModalOverlay<Content: View>: View {
    let isPresented: Binding<Bool>
    let content: Content
    
    init(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.isPresented = isPresented
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            if isPresented.wrappedValue {
                // Blocking background overlay - absorbs all events
                // NOTE: Don't add drag gestures here as they block scrolling inside modal
                // Canvas interaction blocking is handled in CanvasView
                Color.black.opacity(0.3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .allowsHitTesting(true) // Block all events on background
                    .onTapGesture {
                        print("[ModalOverlay] Background tapped - blocking interaction")
                        // Don't dismiss on background tap, just absorb the event
                    }
                    .ignoresSafeArea()
                    .zIndex(0) // Background layer
                
                // Modal content - allows normal interaction inside
                content
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(12)
                    .shadow(radius: 20)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(true) // Ensure modal content captures all events
                    .zIndex(1) // Modal content on top
                    .onAppear {
                        print("[ModalOverlay] Modal content appeared")
                    }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPresented.wrappedValue)
    }
}
