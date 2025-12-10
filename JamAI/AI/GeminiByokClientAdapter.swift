//
//  GeminiByokClientAdapter.swift
//  JamAI
//
//  Gemini API client adapter for BYOK users using their own Google API key
//

import Foundation

final class GeminiByokClientAdapter: AIClient {
    private let session: URLSession
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"
    private let model = "gemini-2.0-flash"
    
    let capabilities: ProviderCapabilities = ProviderCapabilities(
        supportsVision: true,
        supportsAudio: true,
        supportsTools: false,
        maxOutputTokens: 8192
    )
    
    private var apiKey: String? {
        KeychainService.shared.getKey(for: .geminiByok)
    }
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
    
    func healthCheck() async -> AIHealthStatus {
        guard let key = apiKey, !key.isEmpty else {
            return .error("No Gemini API key configured")
        }
        return .ready
    }
    
    func generate(
        prompt: String,
        systemPrompt: String?,
        context: [AIChatMessage]
    ) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw GeminiByokError.noAPIKey
        }
        
        let urlString = "\(baseURL)/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiByokError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = buildRequestBody(prompt: prompt, systemPrompt: systemPrompt, context: context)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiByokError.invalidResponse
        }
        
        if httpResponse.statusCode == 400 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                if message.contains("API key") {
                    throw GeminiByokError.invalidAPIKey
                }
                throw GeminiByokError.apiError(message)
            }
            throw GeminiByokError.invalidAPIKey
        }
        
        if httpResponse.statusCode == 429 {
            throw GeminiByokError.rateLimitExceeded
        }
        
        if httpResponse.statusCode >= 500 {
            throw GeminiByokError.serverError(httpResponse.statusCode)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw GeminiByokError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GeminiByokError.invalidResponse
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
        var contents: [[String: Any]] = []
        
        // Context messages
        for msg in context {
            guard msg.role != .system else { continue }
            
            var parts: [[String: Any]] = [["text": msg.content]]
            
            // Handle images
            if let imageData = msg.imageData, let mimeType = msg.imageMimeType {
                let base64 = imageData.base64EncodedString()
                parts.append([
                    "inline_data": [
                        "mime_type": mimeType,
                        "data": base64
                    ]
                ])
            }
            
            let role = msg.role == .user ? "user" : "model"
            contents.append([
                "role": role,
                "parts": parts
            ])
        }
        
        // Current prompt
        contents.append([
            "role": "user",
            "parts": [["text": prompt]]
        ])
        
        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": 1.0,
                "topK": 40,
                "topP": 0.95,
                "maxOutputTokens": capabilities.maxOutputTokens
            ]
        ]
        
        // System instruction
        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            body["systemInstruction"] = [
                "parts": [["text": systemPrompt]]
            ]
        }
        
        return body
    }
}

// MARK: - Errors

enum GeminiByokError: LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case invalidURL
    case invalidResponse
    case rateLimitExceeded
    case serverError(Int)
    case httpError(Int)
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Gemini API key configured. Add your key in Settings."
        case .invalidAPIKey:
            return "Invalid Gemini API key. Please check your key in Settings."
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from Gemini API"
        case .rateLimitExceeded:
            return "Gemini rate limit exceeded. Please try again later."
        case .serverError(let code):
            return "Gemini server error: \(code)"
        case .httpError(let code):
            return "Gemini HTTP error: \(code)"
        case .apiError(let message):
            return "Gemini error: \(message)"
        }
    }
}
