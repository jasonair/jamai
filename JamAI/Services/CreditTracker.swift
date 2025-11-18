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
        // If no user account is loaded, allow generation (development mode / Firebase not configured)
        guard let account = FirebaseDataService.shared.userAccount else {
            print("⚠️ CreditTracker: No user account, allowing generation (dev mode)")
            return true
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
    
    /// Calculates credits needed for a given prompt, response, and additional
    /// context texts (conversation history, summaries, RAG/search context).
    func calculateCredits(
        promptText: String,
        responseText: String,
        contextTexts: [String] = []
    ) -> Int {
        let promptTokens = estimateTokens(text: promptText)
        let responseTokens = estimateTokens(text: responseText)
        let contextTokens = contextTexts.reduce(0) { partial, text in
            partial + estimateTokens(text: text)
        }
        let totalTokens = promptTokens + responseTokens + contextTokens
        
        // Calculate credits (1 credit per 1000 tokens, minimum 1)
        return max(1, (totalTokens + 999) / 1000 * creditsPerThousandTokens)
    }

    /// Tracks the detailed token usage for an AI generation event, including
    /// context tokens from conversation history, summaries, and RAG/search.
    /// This function is now responsible for logging analytics ONLY.
    /// Credit deduction should be handled by the caller.
    func trackGeneration(
        promptText: String,
        responseText: String,
        contextTexts: [String] = [],
        nodeId: UUID,
        projectId: UUID,
        teamMemberRoleId: String? = nil,
        teamMemberExperienceLevel: String? = nil,
        generationType: String = "chat"
    ) async {
        guard let userId = FirebaseAuthService.shared.currentUser?.uid else {
            print("⚠️ CreditTracker: No authenticated user, skipping credit tracking")
            return
        }
        
        let promptTokens = estimateTokens(text: promptText)
        let contextTokens = contextTexts.reduce(0) { partial, text in
            partial + estimateTokens(text: text)
        }
        let inputTokens = promptTokens + contextTokens
        let outputTokens = estimateTokens(text: responseText)
        
        // Determine the generation type for analytics
        let genType: TokenUsageEvent.GenerationType
        switch generationType {
        case "expand":
            genType = .expand
        case "auto_title":
            genType = .autoTitle
        case "auto_description":
            genType = .autoDescription
        case "voice_input":
            genType = .voiceInput
        default:
            genType = .chat
        }
        
        // Log the detailed event. The AnalyticsService will handle both the detailed
        // log and the user-facing metadata increment.
        await AnalyticsService.shared.trackTokenUsage(
            userId: userId,
            projectId: projectId,
            nodeId: nodeId,
            teamMemberRoleId: teamMemberRoleId,
            teamMemberExperienceLevel: teamMemberExperienceLevel,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            modelUsed: Config.geminiModel,
            generationType: genType
        )
    }
    
    /// Track token usage for voice transcription only (no credit deduction).
    /// Treats the transcribed text as model output tokens so we can estimate
    /// audio transcription cost separately from chat.
    func trackTranscriptionUsage(
        transcriptText: String,
        nodeId: UUID,
        projectId: UUID
    ) async {
        guard let userId = FirebaseAuthService.shared.currentUser?.uid else {
            print("⚠️ CreditTracker: No authenticated user, skipping transcription tracking")
            return
        }
        let outputTokens = estimateTokens(text: transcriptText)
        await AnalyticsService.shared.trackTokenUsage(
            userId: userId,
            projectId: projectId,
            nodeId: nodeId,
            teamMemberRoleId: nil,
            teamMemberExperienceLevel: nil,
            inputTokens: 0,
            outputTokens: outputTokens,
            modelUsed: "gemini-2.0-flash-audio",
            generationType: .voiceInput
        )
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
