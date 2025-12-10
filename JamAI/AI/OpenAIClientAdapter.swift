//
//  OpenAIClientAdapter.swift
//  JamAI
//
//  OpenAI API client adapter for BYOK users
//

import Foundation

final class OpenAIClientAdapter: AIClient {
    private let session: URLSession
    private let baseURL = "https://api.openai.com/v1"
    private let model = "gpt-4o" // Latest GPT-4o model
    
    let capabilities: ProviderCapabilities = ProviderCapabilities(
        supportsVision: true,
        supportsAudio: true,
        supportsTools: true,
        maxOutputTokens: 16384
    )
    
    private var apiKey: String? {
        KeychainService.shared.getKey(for: .openai)
    }
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
    
    func healthCheck() async -> AIHealthStatus {
        guard let key = apiKey, !key.isEmpty else {
            return .error("No OpenAI API key configured")
        }
        return .ready
    }
    
    func generate(
        prompt: String,
        systemPrompt: String?,
        context: [AIChatMessage]
    ) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw OpenAIError.noAPIKey
        }
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let body = buildRequestBody(prompt: prompt, systemPrompt: systemPrompt, context: context)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw OpenAIError.invalidAPIKey
        }
        
        if httpResponse.statusCode == 429 {
            throw OpenAIError.rateLimitExceeded
        }
        
        if httpResponse.statusCode >= 500 {
            throw OpenAIError.serverError(httpResponse.statusCode)
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw OpenAIError.apiError(message)
            }
            throw OpenAIError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.invalidResponse
        }
        
        return content
    }
    
    func generateStreaming(
        prompt: String,
        systemPrompt: String?,
        context: [AIChatMessage],
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        Task {
            do {
                let text = try await generate(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    context: context
                )
                onChunk(text)
                onComplete(.success(text))
            } catch {
                if !Task.isCancelled {
                    onComplete(.failure(error))
                }
            }
        }
    }
    
    func cancelAll() {
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
    }
    
    // MARK: - Helpers
    
    private func buildRequestBody(prompt: String, systemPrompt: String?, context: [AIChatMessage]) -> [String: Any] {
        var messages: [[String: Any]] = []
        
        // System prompt
        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            messages.append([
                "role": "system",
                "content": systemPrompt
            ])
        }
        
        // Context messages
        for msg in context {
            var messageContent: Any = msg.content
            
            // Handle images
            if let imageData = msg.imageData, let mimeType = msg.imageMimeType {
                let base64 = imageData.base64EncodedString()
                let mediaType = mimeType.contains("png") ? "png" : "jpeg"
                messageContent = [
                    [
                        "type": "text",
                        "text": msg.content
                    ],
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": "data:image/\(mediaType);base64,\(base64)"
                        ]
                    ]
                ]
            }
            
            let role: String
            switch msg.role {
            case .user: role = "user"
            case .assistant: role = "assistant"
            case .system: role = "system"
            }
            
            if let contentArray = messageContent as? [[String: Any]] {
                messages.append(["role": role, "content": contentArray])
            } else {
                messages.append(["role": role, "content": messageContent])
            }
        }
        
        // Current prompt
        messages.append([
            "role": "user",
            "content": prompt
        ])
        
        return [
            "model": model,
            "messages": messages,
            "max_tokens": capabilities.maxOutputTokens,
            "temperature": 1.0
        ]
    }
}

// MARK: - Errors

enum OpenAIError: LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case invalidResponse
    case rateLimitExceeded
    case serverError(Int)
    case httpError(Int)
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No OpenAI API key configured. Add your key in Settings."
        case .invalidAPIKey:
            return "Invalid OpenAI API key. Please check your key in Settings."
        case .invalidResponse:
            return "Invalid response from OpenAI API"
        case .rateLimitExceeded:
            return "OpenAI rate limit exceeded. Please try again later."
        case .serverError(let code):
            return "OpenAI server error: \(code)"
        case .httpError(let code):
            return "OpenAI HTTP error: \(code)"
        case .apiError(let message):
            return "OpenAI error: \(message)"
        }
    }
}
