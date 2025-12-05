//
//  ThinkingGlowView.swift
//  JamAI
//
//  Pulsing glow effect for nodes during AI processing
//

import SwiftUI

/// A view that displays a soft, pulsing glow effect around a node
/// to indicate AI processing is in progress.
struct ThinkingGlowView: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let isActive: Bool
    let hasError: Bool
    
    // Animation state
    @State private var glowOpacity: Double = 0
    @State private var glowScale: CGFloat = 1.0
    @State private var animationId: UUID = UUID() // Used to cancel pending animations
    
    // Glow colors - subtle but noticeable
    private let thinkingColor = Color(red: 0.5, green: 0.75, blue: 1.0) // Soft blue
    private let errorColor = Color(red: 0.95, green: 0.3, blue: 0.3) // Soft red
    
    // Animation timing - 3 second breathing cycle
    private let breatheDuration: Double = 1.5 // Half cycle (fade in OR fade out)
    
    var body: some View {
        ZStack {
            // Outer glow layer - subtle halo
            RoundedRectangle(cornerRadius: cornerRadius + 8)
                .fill(glowColor.opacity(0.2 * glowOpacity))
                .frame(width: width + 20, height: height + 20)
                .blur(radius: 10)
                .scaleEffect(glowScale)
            
            // Middle glow layer
            RoundedRectangle(cornerRadius: cornerRadius + 4)
                .fill(glowColor.opacity(0.3 * glowOpacity))
                .frame(width: width + 12, height: height + 12)
                .blur(radius: 6)
                .scaleEffect(glowScale)
            
            // Inner glow layer - tighter edge glow
            RoundedRectangle(cornerRadius: cornerRadius + 2)
                .fill(glowColor.opacity(0.4 * glowOpacity))
                .frame(width: width + 6, height: height + 6)
                .blur(radius: 4)
                .scaleEffect(glowScale)
        }
        .allowsHitTesting(false) // Don't interfere with node interactions
        .onChange(of: isActive) { _, newValue in
            if newValue {
                startBreathingAnimation()
            } else {
                stopAnimation()
            }
        }
        .onChange(of: hasError) { _, newValue in
            if newValue {
                // Flash red briefly then fade out
                withAnimation(.easeOut(duration: 0.2)) {
                    glowOpacity = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        glowOpacity = 0
                    }
                }
            }
        }
        .onAppear {
            if isActive {
                startBreathingAnimation()
            }
        }
    }
    
    private var glowColor: Color {
        hasError ? errorColor : thinkingColor
    }
    
    private func startBreathingAnimation() {
        // Generate new animation ID to invalidate any pending callbacks
        let currentAnimationId = UUID()
        animationId = currentAnimationId
        
        // Reset state
        glowOpacity = 0
        glowScale = 1.0
        
        // Fade in smoothly
        withAnimation(.easeInOut(duration: breatheDuration)) {
            glowOpacity = 1.0
            glowScale = 1.03
        }
        
        // Start continuous breathing loop after initial fade-in
        DispatchQueue.main.asyncAfter(deadline: .now() + breatheDuration) { [self] in
            guard isActive && animationId == currentAnimationId else { return }
            breatheLoop(animationId: currentAnimationId)
        }
    }
    
    private func breatheLoop(animationId currentId: UUID) {
        // Check both isActive AND that this animation hasn't been cancelled
        guard isActive && animationId == currentId else { return }
        
        // Breathe out (fade down)
        withAnimation(.easeInOut(duration: breatheDuration)) {
            glowOpacity = 0.5
            glowScale = 1.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + breatheDuration) { [self] in
            guard isActive && animationId == currentId else { return }
            
            // Breathe in (fade up)
            withAnimation(.easeInOut(duration: breatheDuration)) {
                glowOpacity = 1.0
                glowScale = 1.03
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + breatheDuration) { [self] in
                guard isActive && animationId == currentId else { return }
                breatheLoop(animationId: currentId)
            }
        }
    }
    
    private func stopAnimation() {
        // Generate new animation ID to cancel any pending callbacks
        animationId = UUID()
        
        // Smooth fade out
        withAnimation(.easeOut(duration: 0.3)) {
            glowOpacity = 0
            glowScale = 1.0
        }
    }
}

// MARK: - Preview

#Preview("Thinking Glow - Active") {
    ZStack {
        Color.gray.opacity(0.2)
        
        ZStack {
            ThinkingGlowView(
                width: 400,
                height: 300,
                cornerRadius: 12,
                isActive: true,
                hasError: false
            )
            
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .frame(width: 400, height: 300)
                .shadow(radius: 4)
        }
    }
    .frame(width: 500, height: 400)
}

#Preview("Thinking Glow - Error") {
    ZStack {
        Color.gray.opacity(0.2)
        
        ZStack {
            ThinkingGlowView(
                width: 400,
                height: 300,
                cornerRadius: 12,
                isActive: false,
                hasError: true
            )
            
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .frame(width: 400, height: 300)
                .shadow(radius: 4)
        }
    }
    .frame(width: 500, height: 400)
}
