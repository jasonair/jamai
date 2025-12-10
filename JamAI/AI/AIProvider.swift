import Foundation

enum AIProvider: String, Codable, CaseIterable {
    case local          // Local LLM (free, offline)
    case gemini         // Hosted Gemini (your API key, subscription users)
    case openai         // BYOK OpenAI
    case claude         // BYOK Anthropic Claude
    case geminiByok     // BYOK Gemini (user's own key)
    
    var displayName: String {
        switch self {
        case .local: return "Local (Free)"
        case .gemini: return "Gemini (Cloud)"
        case .openai: return "OpenAI"
        case .claude: return "Claude"
        case .geminiByok: return "Gemini (Your Key)"
        }
    }
    
    var description: String {
        switch self {
        case .local: return "Runs on your Mac, no internet required"
        case .gemini: return "Fast cloud AI, uses your subscription credits"
        case .openai: return "GPT-4o, uses your OpenAI API key"
        case .claude: return "Claude 3.5 Sonnet, uses your Anthropic API key"
        case .geminiByok: return "Gemini 2.0 Flash, uses your Google API key"
        }
    }
    
    /// Whether this provider requires a user-provided API key (BYOK)
    var isByok: Bool {
        switch self {
        case .openai, .claude, .geminiByok: return true
        case .local, .gemini: return false
        }
    }
    
    /// Whether this provider uses your hosted API (costs you money)
    var isHosted: Bool {
        return self == .gemini
    }
    
    /// Keychain identifier for storing the API key
    var keychainIdentifier: String? {
        switch self {
        case .openai: return "openai-api-key"
        case .claude: return "anthropic-api-key"
        case .geminiByok: return "gemini-byok-api-key"
        default: return nil
        }
    }
}

struct ProviderCapabilities: Equatable {
    let supportsVision: Bool
    let supportsAudio: Bool
    let supportsTools: Bool
    let maxOutputTokens: Int
}

struct AIChatMessage: Equatable {
    enum Role: String, Codable {
        case user
        case assistant
        case system
    }
    let role: Role
    let content: String
    let imageData: Data?
    let imageMimeType: String?
    
    init(role: Role, content: String, imageData: Data? = nil, imageMimeType: String? = nil) {
        self.role = role
        self.content = content
        self.imageData = imageData
        self.imageMimeType = imageMimeType
    }
}

struct AIRequest: Equatable {
    let prompt: String
    let systemPrompt: String?
    let context: [AIChatMessage]
}

enum AIHealthStatus: Equatable {
    case unknown
    case ready
    case installing
    case downloading(progress: Double) // 0.0 - 1.0
    case missingDependency
    case serverDown
    case error(String)
}

protocol AIClient: AnyObject {
    var capabilities: ProviderCapabilities { get }
    func healthCheck() async -> AIHealthStatus
    func generate(
        prompt: String,
        systemPrompt: String?,
        context: [AIChatMessage]
    ) async throws -> String
    func generateStreaming(
        prompt: String,
        systemPrompt: String?,
        context: [AIChatMessage],
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    )
    func cancelAll()
}
