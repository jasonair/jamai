//
//  VoiceTranscriptionService.swift
//  JamAI
//
//  Voice transcription using Gemini 2.0 Flash (cheapest audio model)
//

import Foundation

class VoiceTranscriptionService {
    private let geminiClient = GeminiClient()
    
    // MARK: - Cleanup helpers
    
    /// Use Gemini text generation to remove disfluencies, fix grammar, and produce a clear concise version of user intent.
    private func cleanTranscriptWithLLM(_ text: String) async throws -> String {
        // Strong, constrained instruction to avoid hallucination
        let systemPrompt = """
        You are a transcription cleanup assistant.
        Clean the user's dictated text by:
        - Removing disfluencies (um, uh, ah, erm, hmm), stutters, and repeated filler phrases.
        - Fixing grammar, punctuation, and capitalization.
        - Keeping the original meaning and key entities (names, numbers, products).
        - Making the request concise and natural. If it is a question, phrase it as a single clear question.
        - Do not add or infer new facts. Do not change intent. Do not add prefaces or explanations.
        Output only the cleaned text, nothing else.
        """
        let prompt = "Text to clean:\n\n" + text
        let cleaned = try await geminiClient.generate(prompt: prompt, systemPrompt: systemPrompt, context: [])
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Local regex-based cleanup as a safety net and for extra polish
    private func localClean(_ text: String) -> String {
        var s = text
        
        // Remove common fillers (case-insensitive), including repeated sequences like "um, um"
        let fillerPattern = "(?i)(?:\\b(?:um|uh|ah|er|erm|hmm)\\b[,.!?]*)+"
        s = s.replacingOccurrences(of: fillerPattern, with: "", options: .regularExpression)
        
        // Collapse multiple spaces and stray commas
        s = s.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\u{00A0}", with: " ") // non-breaking space
        s = s.replacingOccurrences(of: "\\s+,", with: ",", options: .regularExpression)
        s = s.replacingOccurrences(of: ",\\s+,", with: ", ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Capitalize first letter if needed
        if let first = s.first, first.isLowercase {
            s.replaceSubrange(s.startIndex...s.startIndex, with: String(first).uppercased())
        }
        
        // Ensure terminal punctuation for sentences that look like a statement/question
        if !s.isEmpty, let last = s.last, !".?!".contains(last) {
            // Heuristic: add a question mark if it starts with a question word
            let lower = s.lowercased()
            let questionStarters = ["who", "what", "when", "where", "why", "how", "which", "can", "could", "would", "should", "is", "are", "do", "does", "did"]
            if questionStarters.contains(where: { lower.hasPrefix($0 + " ") }) {
                s.append("?")
            } else {
                s.append(".")
            }
        }
        
        return s
    }
    
    /// Transcribe audio file using Gemini 2.0 Flash
    /// Cost: $0.70 per 1M tokens (~$0.00105 per minute of audio)
    /// - Parameters:
    ///   - audioURL: local audio file URL
    ///   - clean: when true, post-processes transcript to remove disfluencies and fix grammar
    func transcribe(audioURL: URL, clean: Bool = true) async throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["GOOGLE_GEMINI_API_KEY"],
              !apiKey.isEmpty else {
            throw TranscriptionError.noAPIKey
        }
        
        // Read audio file
        let audioData = try Data(contentsOf: audioURL)
        
        // Convert to base64
        let base64Audio = audioData.base64EncodedString()
        
        // Determine MIME type based on file extension
        let mimeType: String
        if audioURL.pathExtension.lowercased() == "m4a" {
            mimeType = "audio/mp4"
        } else if audioURL.pathExtension.lowercased() == "mp3" {
            mimeType = "audio/mpeg"
        } else if audioURL.pathExtension.lowercased() == "wav" {
            mimeType = "audio/wav"
        } else {
            mimeType = "audio/mp4" // default
        }
        
        // Build API request
        // Using gemini-2.0-flash for cheapest audio transcription
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw TranscriptionError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build request body with audio inline data
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "text": "Transcribe this audio exactly as spoken. Only output the transcription text, nothing else."
                        ],
                        [
                            "inline_data": [
                                "mime_type": mimeType,
                                "data": base64Audio
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.1, // Low temperature for accurate transcription
                "topK": 1,
                "topP": 0.1
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw TranscriptionError.rateLimitExceeded
        }
        
        if httpResponse.statusCode >= 500 {
            throw TranscriptionError.serverError(httpResponse.statusCode)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw TranscriptionError.httpError(httpResponse.statusCode)
        }
        
        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw TranscriptionError.invalidResponse
        }
        var transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Optional cleanup: LLM rewrite first, then regex fallback polish
        if clean {
            if let llmCleaned = try? await cleanTranscriptWithLLM(transcript) {
                transcript = llmCleaned
            }
            transcript = localClean(transcript)
        }

        return transcript
    }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case rateLimitExceeded
    case serverError(Int)
    case httpError(Int)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Please set GOOGLE_GEMINI_API_KEY in your environment (for example in a .env file)."
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Failed to parse transcription response"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .serverError(let code):
            return "Server error: \(code)"
        case .httpError(let code):
            return "HTTP error: \(code)"
        }
    }
}
