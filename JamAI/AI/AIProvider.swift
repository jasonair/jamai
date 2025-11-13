import Foundation

enum AIProvider: String, Codable, CaseIterable {
    case local
    case gemini
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
