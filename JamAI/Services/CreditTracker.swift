//
//  CreditTracker.swift
//  JamAI
//
//  Tracks and deducts credits for AI usage
//

import Foundation
import FirebaseAuth

/// Credit tracker for AI operations
@MainActor
class CreditTracker {
    
    static let shared = CreditTracker()
    
    private init() {}
    
    /// Credits per 1000 tokens (approximate)
    private let creditsPerThousandTokens = 1
    
    /// Check if user has enough credits for AI generation
    func canGenerateResponse() -> Bool {
        guard let account = FirebaseDataService.shared.userAccount else {
            return false
        }
        
        // Check if account is active
        guard account.isActive else {
            return false
        }
        
        // Check trial expiration
        if account.isTrialExpired {
            return false
        }
        
        return account.hasCredits
    }
    
    /// Estimate tokens from text (rough approximation: 1 token ≈ 4 characters)
    private func estimateTokens(text: String) -> Int {
        return max(1, text.count / 4)
    }
    
    /// Calculate credits needed for prompt and response
    private func calculateCredits(promptText: String, responseText: String) -> Int {
        let promptTokens = estimateTokens(text: promptText)
        let responseTokens = estimateTokens(text: responseText)
        let totalTokens = promptTokens + responseTokens
        
        // Calculate credits (1 credit per 1000 tokens, minimum 1)
        return max(1, (totalTokens + 999) / 1000 * creditsPerThousandTokens)
    }
    
    /// Deduct credits after AI generation
    func trackGeneration(promptText: String, responseText: String, nodeId: UUID) async {
        guard let userId = FirebaseAuthService.shared.currentUser?.uid else {
            return
        }
        
        let credits = calculateCredits(promptText: promptText, responseText: responseText)
        
        let success = await FirebaseDataService.shared.deductCredits(
            userId: userId,
            amount: credits,
            description: "AI generation for node"
        )
        
        if !success {
            print("⚠️ Failed to deduct credits for generation")
        }
        
        // Update user metadata
        if var metadata = FirebaseDataService.shared.userAccount?.metadata {
            metadata.totalMessagesGenerated += 1
            await FirebaseDataService.shared.updateUserMetadata(userId: userId, metadata: metadata)
        }
    }
    
    /// Get remaining credits as a formatted string
    func getRemainingCreditsMessage() -> String? {
        guard let account = FirebaseDataService.shared.userAccount else {
            return nil
        }
        
        if account.credits == 0 {
            return "⚠️ Out of credits. Upgrade your plan to continue."
        } else if account.credits < 10 {
            return "⚠️ Running low on credits: \(account.credits) remaining"
        }
        
        return "\(account.credits) credits remaining"
    }
}
