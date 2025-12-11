//
//  GeminiClient.swift
//  JamAI
//
//  Gemini 2.0 Flash API client with streaming support
//  Uses Cloud Functions to proxy requests with server-side API key
//

import Foundation
import Combine
import FirebaseAuth

class GeminiClient: ObservableObject {
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
    
    deinit {
        // Cancel all pending tasks and invalidate session
        cleanup()
    }
    
    /// Cleanup URLSession
    func cleanup() {
        session.invalidateAndCancel()
    }
    
    // MARK: - Availability / Auth
    
    /// In the SaaS model, cloud AI availability is tied to Firebase auth,
    /// not a local API key. We treat "has key" as "user is signed in".
    func hasAPIKey() -> Bool {
        return FirebaseAuthService.shared.currentUser != nil
    }
    
    // MARK: - Streaming Generation
    
    func generateStreaming(
        prompt: String,
        systemPrompt: String?,
        context: [Message] = [],
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        // For now we don't stream from the backend – just call generate()
        // and surface a single chunk to the UI (same pattern as LocalLlamaClient).
        Task {
            do {
                let text = try await self.generate(
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
        // Keep task alive until completion (no explicit store needed here).
    }
    
    private func parseStreamingResponse(
        data: Data,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        guard let dataString = String(data: data, encoding: .utf8) else {
            onComplete(.failure(GeminiError.invalidResponse))
            return
        }
        
        var fullResponse = ""
        let lines = dataString.components(separatedBy: "\n")
        
        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                guard let jsonData = jsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let firstCandidate = candidates.first,
                      let content = firstCandidate["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let firstPart = parts.first,
                      let text = firstPart["text"] as? String else {
                    continue
                }
                
                fullResponse += text
                onChunk(text)
            }
        }
        
        onComplete(.success(fullResponse))
    }
    
    // MARK: - Non-streaming Generation
    
    func generate(
        prompt: String,
        systemPrompt: String?,
        context: [Message] = []
    ) async throws -> String {
        guard let currentUser = FirebaseAuthService.shared.currentUser else {
            throw GeminiError.noAPIKey
        }

        let token = try await currentUser.getIDToken()
        guard let url = URL(string: Config.geminiBackendURL) else {
            throw GeminiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body = buildRequestBody(prompt: prompt, systemPrompt: systemPrompt, context: context)
        let payload: [String: Any] = [
            "body": body
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw GeminiError.rateLimitExceeded
        }

        if httpResponse.statusCode >= 500 {
            throw GeminiError.serverError(httpResponse.statusCode)
        }

        guard httpResponse.statusCode == 200 else {
            throw GeminiError.httpError(httpResponse.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = json["ok"] as? Bool, ok,
              let text = json["text"] as? String else {
            throw GeminiError.invalidResponse
        }

        return text
    }
    
    // MARK: - Embeddings
    
    func generateEmbedding(text: String) async throws -> [Float] {
        guard let currentUser = FirebaseAuthService.shared.currentUser else {
            throw GeminiError.noAPIKey
        }
        
        let token = try await currentUser.getIDToken()
        
        guard let url = URL(string: Config.geminiEmbeddingURL) else {
            throw GeminiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let payload: [String: Any] = ["text": text]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GeminiError.invalidResponse
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = json["ok"] as? Bool, ok,
              let values = json["embedding"] as? [Double] else {
            throw GeminiError.invalidResponse
        }
        
        return values.map { Float($0) }
    }
    
    // MARK: - Helper Methods
    
    private func buildRequestBody(prompt: String, systemPrompt: String?, context: [Message]) -> [String: Any] {
        var contents: [[String: Any]] = []
        
        // Add context messages
        for message in context {
            var parts: [[String: Any]] = [["text": message.content]]
            
            // Add image if present
            if let imageData = message.imageData, let mimeType = message.imageMimeType {
                let base64Image = imageData.base64EncodedString()
                parts.append([
                    "inline_data": [
                        "mime_type": mimeType,
                        "data": base64Image
                    ]
                ])
            }
            
            contents.append([
                "role": message.role,
                "parts": parts
            ])
        }
        
        // Add current prompt (text only, images come through context)
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
                "maxOutputTokens": 8192
            ]
        ]
        
        if let systemPrompt = systemPrompt {
            body["systemInstruction"] = [
                "parts": [["text": systemPrompt]]
            ]
        }
        
        return body
    }
}

// MARK: - Supporting Types

struct Message {
    let role: String  // "user" or "model"
    let content: String
    let imageData: Data?
    let imageMimeType: String?
    
    init(role: String, content: String, imageData: Data? = nil, imageMimeType: String? = nil) {
        self.role = role
        self.content = content
        self.imageData = imageData
        self.imageMimeType = imageMimeType
    }
}

enum GeminiError: LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case noData
    case rateLimitExceeded
    case serverError(Int)
    case httpError(Int)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Cloud AI is not available. Please sign in to JamAI and ensure your account has access."
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from API"
        case .noData:
            return "No data received from API"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .serverError(let code):
            return "Server error: \(code)"
        case .httpError(let code):
            return "HTTP error: \(code)"
        }
    }
}
