//
//  ClaudeClientAdapter.swift
//  JamAI
//
//  Anthropic Claude API client adapter for BYOK users
//

import Foundation

final class ClaudeClientAdapter: AIClient {
    private let session: URLSession
    private let baseURL = "https://api.anthropic.com/v1"
    private let model = "claude-sonnet-4-20250514" // Claude 4 Sonnet
    private let apiVersion = "2023-06-01"
    
    let capabilities: ProviderCapabilities = ProviderCapabilities(
        supportsVision: true,
        supportsAudio: false, // Claude doesn't support audio input
        supportsTools: true,
        maxOutputTokens: 8192
    )
    
    private var apiKey: String? {
        KeychainService.shared.getKey(for: .claude)
    }
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
    
    func healthCheck() async -> AIHealthStatus {
        guard let key = apiKey, !key.isEmpty else {
            return .error("No Anthropic API key configured")
        }
        return .ready
    }
    
    func generate(
        prompt: String,
        systemPrompt: String?,
        context: [AIChatMessage]
    ) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ClaudeError.noAPIKey
        }
        
        let url = URL(string: "\(baseURL)/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        
        let body = buildRequestBody(prompt: prompt, systemPrompt: systemPrompt, context: context)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw ClaudeError.invalidAPIKey
        }
        
        if httpResponse.statusCode == 429 {
            throw ClaudeError.rateLimitExceeded
        }
        
        if httpResponse.statusCode >= 500 {
            throw ClaudeError.serverError(httpResponse.statusCode)
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw ClaudeError.apiError(message)
            }
            throw ClaudeError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw ClaudeError.invalidResponse
        }
        
        return text
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
        
        // Context messages (Claude doesn't have a separate system role in messages)
        for msg in context {
            guard msg.role != .system else { continue } // System handled separately
            
            var content: Any = msg.content
            
            // Handle images
            if let imageData = msg.imageData, let mimeType = msg.imageMimeType {
                let base64 = imageData.base64EncodedString()
                content = [
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": mimeType,
                            "data": base64
                        ]
                    ],
                    [
                        "type": "text",
                        "text": msg.content
                    ]
                ]
            }
            
            let role = msg.role == .user ? "user" : "assistant"
            
            if let contentArray = content as? [[String: Any]] {
                messages.append(["role": role, "content": contentArray])
            } else {
                messages.append(["role": role, "content": content])
            }
        }
        
        // Current prompt
        messages.append([
            "role": "user",
            "content": prompt
        ])
        
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": capabilities.maxOutputTokens
        ]
        
        // System prompt is a top-level field for Claude
        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }
        
        return body
    }
}

// MARK: - Errors

enum ClaudeError: LocalizedError {
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
            return "No Anthropic API key configured. Add your key in Settings."
        case .invalidAPIKey:
            return "Invalid Anthropic API key. Please check your key in Settings."
        case .invalidResponse:
            return "Invalid response from Claude API"
        case .rateLimitExceeded:
            return "Claude rate limit exceeded. Please try again later."
        case .serverError(let code):
            return "Claude server error: \(code)"
        case .httpError(let code):
            return "Claude HTTP error: \(code)"
        case .apiError(let message):
            return "Claude error: \(message)"
        }
    }
}
