//
//  OutOfCreditsMessageView.swift
//  JamAI
//
//  Inline message shown in node when user runs out of credits
//

import SwiftUI

/// Inline message view shown in the node chat when user runs out of credits
struct OutOfCreditsMessageView: View {
    let creditCheckResult: CreditCheckResult
    let onUpgradePlan: () -> Void
    let onUseLocalModel: () -> Void
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with warning icon
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.orange)
                
                Text("Out of Credits")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Dismiss button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Dismiss")
            }
            
            // Message
            Text(creditCheckResult.userMessage)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Action buttons
            HStack(spacing: 12) {
                // Use Local Model button
                Button(action: onUseLocalModel) {
                    HStack(spacing: 6) {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 12))
                        Text("Use Local Model")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Switch to local model (free, no credits needed)")
                
                // Upgrade Plan button
                Button(action: onUpgradePlan) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 12))
                        Text("Upgrade Plan")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .help("View plans and upgrade")
                
                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark 
                    ? Color(white: 0.15) 
                    : Color(white: 0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    VStack {
        OutOfCreditsMessageView(
            creditCheckResult: CreditCheckResult(
                allowed: false,
                reason: .outOfCredits,
                remainingCredits: 0
            ),
            onUpgradePlan: {},
            onUseLocalModel: {},
            onDismiss: {}
        )
        .frame(maxWidth: 500)
        .padding()
    }
}
