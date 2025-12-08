//
//  HapticFeedbackService.swift
//  JamAI
//
//  Provides haptic feedback for alignment snapping using macOS Force Touch trackpad.
//  Uses NSHapticFeedbackManager with .alignment pattern for Figma-style snap feedback.
//

import Foundation
import AppKit

/// Service for triggering haptic feedback on macOS Force Touch trackpads
@MainActor
final class HapticFeedbackService {
    static let shared = HapticFeedbackService()
    
    private init() {}
    
    /// Trigger alignment haptic feedback (for snap-to-guide)
    /// This produces a subtle "click" when objects align, similar to Figma/Illustrator
    func playAlignmentFeedback() {
        print("🔔 HapticFeedbackService: Playing alignment feedback")
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
    }
    
    /// Trigger generic haptic feedback
    func playGenericFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .default
        )
    }
    
    /// Trigger level change haptic feedback
    func playLevelChangeFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .default
        )
    }
}
