import Foundation

final class GeminiClientAdapter: AIClient {
    private let gemini: GeminiClient
    let capabilities: ProviderCapabilities = ProviderCapabilities(
        supportsVision: true,
        supportsAudio: true,
        supportsTools: false,
        maxOutputTokens: 8192
    )
    
    init(geminiClient: GeminiClient) {
        self.gemini = geminiClient
    }
    
    func healthCheck() async -> AIHealthStatus {
        if gemini.hasAPIKey() {
            return .ready
        } else {
            return .error("No API key configured")
        }
    }
    
    private func mapContext(_ context: [AIChatMessage]) -> [Message] {
        var messages: [Message] = []
        for m in context {
            switch m.role {
            case .user:
                messages.append(Message(role: "user", content: m.content, imageData: m.imageData, imageMimeType: m.imageMimeType))
            case .assistant:
                messages.append(Message(role: "model", content: m.content, imageData: m.imageData, imageMimeType: m.imageMimeType))
            case .system:
                continue
            }
        }
        return messages
    }
    
    func generate(
        prompt: String,
        systemPrompt: String?,
        context: [AIChatMessage]
    ) async throws -> String {
        try await gemini.generate(
            prompt: prompt,
            systemPrompt: systemPrompt,
            context: mapContext(context)
        )
    }
    
    func generateStreaming(
        prompt: String,
        systemPrompt: String?,
        context: [AIChatMessage],
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        gemini.generateStreaming(
            prompt: prompt,
            systemPrompt: systemPrompt,
            context: mapContext(context),
            onChunk: onChunk,
            onComplete: onComplete
        )
    }
    
    func cancelAll() {
    }
}
