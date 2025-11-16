//
//  Personality.swift
//  JamAI
//
//  Represents per-node thinking style for an attached expert
//

import Foundation

enum Personality: String, Codable, CaseIterable, Sendable {
    case generalist
    case analyst
    case strategist
    case creative
    case skeptic
    case clarifier
    
    var displayName: String {
        switch self {
        case .generalist: return "Generalist"
        case .analyst: return "Analyst"
        case .strategist: return "Strategist"
        case .creative: return "Creative"
        case .skeptic: return "Skeptic"
        case .clarifier: return "Clarifier"
        }
    }
    
    var shortDescription: String {
        switch self {
        case .generalist:
            return "Balanced, pragmatic, mixes explanation and recommendations."
        case .analyst:
            return "Evidence-based, explicit assumptions, structured comparisons."
        case .strategist:
            return "Considers options, trade-offs, and longer-term impact."
        case .creative:
            return "Imaginative, explores alternatives and connects perspectives."
        case .skeptic:
            return "Stress-tests assumptions, surfaces risks and failure modes."
        case .clarifier:
            return "Simplifies and structures information in clear language."
        }
    }
    
    var promptSnippet: String {
        switch self {
        case .generalist:
            return "Act as a balanced generalist. Combine clear explanation, sensible structure and practical recommendations. Use evidence and numbers when helpful, but don’t overcomplicate. When there are multiple reasonable options, briefly compare them and suggest a pragmatic next step."
        case .analyst:
            return "Be careful, evidence-based and explicit about assumptions and numbers. Compare options using concrete criteria, show calculations where relevant, and highlight uncertainties or missing data. Prefer structured reasoning over anecdotes."
        case .strategist:
            return "Think in terms of options, trade-offs and longer-term consequences. Lay out alternative approaches, compare their pros and cons, and explain how they affect risks, effort and outcomes over time. Help the user choose a path, not just make a single local decision."
        case .creative:
            return "Generate imaginative ideas and unexpected connections between concepts. Bring in analogies from other domains, explore alternative framings, and propose novel combinations or twists. It’s okay to be more playful and speculative, as long as you stay relevant to the user’s goal."
        case .skeptic:
            return "Stress-test the user’s ideas and your own suggestions. Look for hidden assumptions, edge cases, risks and failure modes. Politely challenge weak reasoning, point out where something could go wrong, and propose mitigations or safer alternatives."
        case .clarifier:
            return "Make things easy to understand. Rephrase complex ideas in plain language, organize information into clear sections or lists, and give small examples when helpful. Surface the key points first, then details. Check for ambiguity and resolve it."
        }
    }
}
