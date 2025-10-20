//
//  GeminiClient.swift
//  JamAI
//
//  Gemini 2.0 Flash API client with streaming support
//

import Foundation
import Combine

class GeminiClient: ObservableObject {
    private var apiKey: String?
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
        
        // Load API key from keychain
        self.apiKey = try? KeychainHelper.retrieve(forKey: Config.geminiAPIKeyIdentifier)
    }
    
    deinit {
        // Cancel all pending tasks and invalidate session
        cleanup()
    }
    
    /// Cleanup URLSession
    func cleanup() {
        session.invalidateAndCancel()
    }
    
    // MARK: - API Key Management
    
    func setAPIKey(_ key: String) throws {
        try KeychainHelper.save(key, forKey: Config.geminiAPIKeyIdentifier)
        self.apiKey = key
    }
    
    func hasAPIKey() -> Bool {
        return apiKey != nil && !apiKey!.isEmpty
    }
    
    // MARK: - Streaming Generation
    
    func generateStreaming(
        prompt: String,
        systemPrompt: String?,
        context: [Message] = [],
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        guard let apiKey = apiKey else {
            onComplete(.failure(GeminiError.noAPIKey))
            return
        }
        
        let urlString = "\(Config.geminiAPIBaseURL)/models/\(Config.geminiModel):streamGenerateContent?key=\(apiKey)&alt=sse"
        guard let url = URL(string: urlString) else {
            onComplete(.failure(GeminiError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = buildRequestBody(prompt: prompt, systemPrompt: systemPrompt, context: context)
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                onComplete(.failure(error))
                return
            }
            
            guard let data = data else {
                onComplete(.failure(GeminiError.noData))
                return
            }
            
            self.parseStreamingResponse(data: data, onChunk: onChunk, onComplete: onComplete)
        }
        
        task.resume()
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
        guard let apiKey = apiKey else {
            throw GeminiError.noAPIKey
        }
        
        let urlString = "\(Config.geminiAPIBaseURL)/models/\(Config.geminiModel):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = buildRequestBody(prompt: prompt, systemPrompt: systemPrompt, context: context)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
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
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GeminiError.invalidResponse
        }
        
        return text
    }
    
    // MARK: - Embeddings
    
    func generateEmbedding(text: String) async throws -> [Float] {
        guard let apiKey = apiKey else {
            throw GeminiError.noAPIKey
        }
        
        let urlString = "\(Config.geminiAPIBaseURL)/\(Config.geminiEmbeddingModel):embedContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": Config.geminiEmbeddingModel,
            "content": [
                "parts": [["text": text]]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GeminiError.invalidResponse
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embedding = json["embedding"] as? [String: Any],
              let values = embedding["values"] as? [Double] else {
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
            return "No API key configured. Please add your Gemini API key in settings."
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
