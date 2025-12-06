//
//  CreditTracker.swift
//  JamAI
//
//  Tracks and deducts credits for AI usage
//

import Foundation
import Combine
import FirebaseAuth

/// Reason why credit check failed or succeeded
enum CreditCheckReason: Equatable {
    case allowed
    case outOfCredits
    case accountInactive
    case trialExpired
    case devMode  // No account loaded, allowing generation
}

/// Result of a credit check with structured information
struct CreditCheckResult {
    let allowed: Bool
    let reason: CreditCheckReason
    let remainingCredits: Int
    
    /// User-facing message for the credit status
    var userMessage: String {
        switch reason {
        case .allowed:
            return "\(remainingCredits) credits remaining"
        case .outOfCredits:
            return "You've run out of cloud prompt credits for this month. Switch to the local model for free, or upgrade your plan to get more credits."
        case .accountInactive:
            return "Your account is inactive. Please contact support."
        case .trialExpired:
            return "Your trial has expired. Upgrade your plan to continue using cloud models."
        case .devMode:
            return "Development mode - credits not tracked"
        }
    }
    
    /// Whether the user should be prompted to upgrade
    var shouldPromptUpgrade: Bool {
        switch reason {
        case .outOfCredits, .trialExpired:
            return true
        default:
            return false
        }
    }
}

/// Credit tracker for AI operations
@MainActor
class CreditTracker: ObservableObject {
    
    static let shared = CreditTracker()
    
    /// Published property to notify views when credits run out
    @Published var lastCreditCheckResult: CreditCheckResult?
    
    private init() {}
    
    /// Check if user has enough credits for AI generation (structured result)
    func checkCredits() -> CreditCheckResult {
        // If no user account is loaded, allow generation (development mode / Firebase not configured)
        guard let account = FirebaseDataService.shared.userAccount else {
            print("⚠️ CreditTracker: No user account, allowing generation (dev mode)")
            return CreditCheckResult(allowed: true, reason: .devMode, remainingCredits: 0)
        }
        
        // Check if account is active
        guard account.isActive else {
            return CreditCheckResult(allowed: false, reason: .accountInactive, remainingCredits: account.credits)
        }
        
        // Check trial expiration
        if account.isTrialExpired {
            return CreditCheckResult(allowed: false, reason: .trialExpired, remainingCredits: account.credits)
        }
        
        // Check credits
        if !account.hasCredits {
            return CreditCheckResult(allowed: false, reason: .outOfCredits, remainingCredits: 0)
        }
        
        return CreditCheckResult(allowed: true, reason: .allowed, remainingCredits: account.credits)
    }
    
    /// Check if user has enough credits for AI generation (legacy bool version)
    func canGenerateResponse() -> Bool {
        return checkCredits().allowed
    }
    
    /// Estimate tokens from text (rough approximation: 1 token ≈ 4 characters)
    private func estimateTokens(text: String) -> Int {
        return max(1, text.count / 4)
    }
    
    /// Calculates credits needed for a given prompt.
    ///
    /// We now charge a **flat 1 credit per AI generation** so usage is
    /// predictable for users, independent of token counts. Token-level
    /// analytics are still tracked separately in `trackGeneration`.
    func calculateCredits(
        promptText: String,
        responseText: String,
        contextTexts: [String] = []
    ) -> Int {
        _ = promptText
        _ = responseText
        _ = contextTexts
        return 1
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
