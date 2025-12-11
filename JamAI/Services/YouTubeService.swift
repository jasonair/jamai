//
//  YouTubeService.swift
//  JamAI
//
//  Service for YouTube URL validation, metadata extraction, and Gemini video context
//

import Foundation

/// Metadata extracted from a YouTube video
struct YouTubeMetadata {
    let videoId: String
    let title: String
    let thumbnailUrl: String
    let authorName: String?
    let duration: String? // Not available from oEmbed, but kept for future use
}

/// Error types for YouTube operations
enum YouTubeError: LocalizedError {
    case invalidURL
    case videoNotFound
    case metadataFetchFailed(String)
    case networkError(String)
    case noAPIKey
    case geminiError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid YouTube URL. Please paste a valid YouTube video link."
        case .videoNotFound:
            return "Video not found or is private/unavailable."
        case .metadataFetchFailed(let message):
            return "Failed to fetch video info: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .noAPIKey:
            return "API key not configured"
        case .geminiError(let message):
            return "Gemini API error: \(message)"
        }
    }
}

/// Service for YouTube video operations
@MainActor
class YouTubeService {
    static let shared = YouTubeService()
    
    private let metadataSession: URLSession
    private let videoSession: URLSession // Longer timeout for video processing
    
    private var apiKey: String? {
        ProcessInfo.processInfo.environment["GOOGLE_GEMINI_API_KEY"]
    }
    
    private init() {
        // Short timeout for metadata fetching
        let metadataConfig = URLSessionConfiguration.default
        metadataConfig.timeoutIntervalForRequest = 30
        metadataConfig.timeoutIntervalForResource = 60
        self.metadataSession = URLSession(configuration: metadataConfig)
        
        // Long timeout for video processing (videos can take 2-3 minutes)
        let videoConfig = URLSessionConfiguration.default
        videoConfig.timeoutIntervalForRequest = 180 // 3 minutes
        videoConfig.timeoutIntervalForResource = 300 // 5 minutes
        self.videoSession = URLSession(configuration: videoConfig)
    }
    
    // MARK: - URL Validation & Video ID Extraction
    
    /// Extract video ID from various YouTube URL formats
    /// Supports:
    /// - https://www.youtube.com/watch?v=VIDEO_ID
    /// - https://youtu.be/VIDEO_ID
    /// - https://www.youtube.com/embed/VIDEO_ID
    /// - https://www.youtube.com/v/VIDEO_ID
    /// - https://www.youtube.com/shorts/VIDEO_ID
    func extractVideoId(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to parse as URL
        guard let url = URL(string: trimmed) else {
            // Maybe it's just a video ID?
            if trimmed.count == 11 && trimmed.range(of: "^[a-zA-Z0-9_-]{11}$", options: .regularExpression) != nil {
                return trimmed
            }
            return nil
        }
        
        let host = url.host?.lowercased() ?? ""
        
        // youtu.be short links
        if host == "youtu.be" {
            let videoId = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return videoId.isEmpty ? nil : videoId
        }
        
        // youtube.com variants
        if host.contains("youtube.com") {
            // /watch?v=VIDEO_ID
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let videoId = components.queryItems?.first(where: { $0.name == "v" })?.value {
                return videoId
            }
            
            // /embed/VIDEO_ID, /v/VIDEO_ID, /shorts/VIDEO_ID
            let pathComponents = url.pathComponents
            if pathComponents.count >= 2 {
                let prefix = pathComponents[1].lowercased()
                if ["embed", "v", "shorts"].contains(prefix) && pathComponents.count >= 3 {
                    return pathComponents[2]
                }
            }
        }
        
        return nil
    }
    
    /// Validate if a string is a valid YouTube URL
    func isValidYouTubeURL(_ urlString: String) -> Bool {
        return extractVideoId(from: urlString) != nil
    }
    
    // MARK: - Metadata Fetching
    
    /// Fetch video metadata using YouTube oEmbed API (no API key required)
    func fetchMetadata(for urlString: String) async throws -> YouTubeMetadata {
        guard let videoId = extractVideoId(from: urlString) else {
            throw YouTubeError.invalidURL
        }
        
        // Use oEmbed API - free, no API key needed
        let oEmbedUrl = "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoId)&format=json"
        
        guard let url = URL(string: oEmbedUrl) else {
            throw YouTubeError.invalidURL
        }
        
        do {
            let (data, response) = try await metadataSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw YouTubeError.networkError("Invalid response")
            }
            
            if httpResponse.statusCode == 404 {
                throw YouTubeError.videoNotFound
            }
            
            guard httpResponse.statusCode == 200 else {
                throw YouTubeError.metadataFetchFailed("HTTP \(httpResponse.statusCode)")
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw YouTubeError.metadataFetchFailed("Invalid JSON response")
            }
            
            let title = json["title"] as? String ?? "Untitled Video"
            let authorName = json["author_name"] as? String
            
            // Construct high-quality thumbnail URL
            // YouTube provides: default (120x90), mqdefault (320x180), hqdefault (480x360), maxresdefault (1280x720)
            let thumbnailUrl = "https://img.youtube.com/vi/\(videoId)/mqdefault.jpg"
            
            return YouTubeMetadata(
                videoId: videoId,
                title: title,
                thumbnailUrl: thumbnailUrl,
                authorName: authorName,
                duration: nil
            )
        } catch let error as YouTubeError {
            throw error
        } catch {
            throw YouTubeError.networkError(error.localizedDescription)
        }
    }
    
    // MARK: - Transcript Fetching
    
    /// Fetch YouTube video transcript/captions
    /// Uses youtube-transcript-api format via a public endpoint
    func fetchTranscript(videoId: String) async throws -> String {
        // Try to get captions via YouTube's timedtext API
        // This fetches auto-generated or manual captions
        let captionUrl = "https://www.youtube.com/watch?v=\(videoId)"
        
        guard let url = URL(string: captionUrl) else {
            throw YouTubeError.invalidURL
        }
        
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            
            let (data, _) = try await metadataSession.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else {
                return ""
            }
            
            // Extract captions URL from the page
            // Look for "captionTracks" in the YouTube page data
            if let captionsData = extractCaptionsData(from: html, videoId: videoId) {
                return captionsData
            }
            
            return ""
        } catch {
            print("⚠️ [YouTube] Failed to fetch transcript: \(error.localizedDescription)")
            return ""
        }
    }
    
    /// Extract captions data from YouTube page HTML
    private func extractCaptionsData(from html: String, videoId: String) -> String? {
        // Look for timedtext URL in the page
        guard let range = html.range(of: "\"captions\":", options: .caseInsensitive),
              let endRange = html.range(of: "\"videoDetails\"", options: .caseInsensitive, range: range.upperBound..<html.endIndex) else {
            return nil
        }
        
        let captionsSection = String(html[range.lowerBound..<endRange.lowerBound])
        
        // Extract the baseUrl for captions
        guard let baseUrlRange = captionsSection.range(of: "\"baseUrl\":\""),
              let endUrlRange = captionsSection.range(of: "\"", options: [], range: baseUrlRange.upperBound..<captionsSection.endIndex) else {
            return nil
        }
        
        var captionUrl = String(captionsSection[baseUrlRange.upperBound..<endUrlRange.lowerBound])
        captionUrl = captionUrl.replacingOccurrences(of: "\\u0026", with: "&")
        
        // Fetch the actual captions
        return fetchCaptionsFromUrl(captionUrl)
    }
    
    /// Fetch and parse captions from YouTube's timedtext URL
    private func fetchCaptionsFromUrl(_ urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        
        // Synchronous fetch for simplicity (called from async context)
        let semaphore = DispatchSemaphore(value: 0)
        var result: String?
        
        let task = metadataSession.dataTask(with: url) { data, _, error in
            defer { semaphore.signal() }
            guard let data = data, error == nil,
                  let xml = String(data: data, encoding: .utf8) else {
                return
            }
            
            // Parse the XML captions - extract text from <text> tags
            // Use nonisolated helper to avoid main actor isolation issue
            result = Self.parseCaptionsXML(xml)
        }
        task.resume()
        semaphore.wait()
        
        return result
    }
    
    /// Parse captions XML to extract plain text (nonisolated for use in closures)
    private nonisolated static func parseCaptionsXML(_ xml: String) -> String {
        var texts: [String] = []
        var searchRange = xml.startIndex..<xml.endIndex
        
        while let startRange = xml.range(of: "<text", options: [], range: searchRange),
              let contentStart = xml.range(of: ">", options: [], range: startRange.upperBound..<xml.endIndex),
              let endRange = xml.range(of: "</text>", options: [], range: contentStart.upperBound..<xml.endIndex) {
            
            let content = String(xml[contentStart.upperBound..<endRange.lowerBound])
            // Decode HTML entities
            let decoded = content
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "\n", with: " ")
            
            if !decoded.trimmingCharacters(in: .whitespaces).isEmpty {
                texts.append(decoded)
            }
            
            searchRange = endRange.upperBound..<xml.endIndex
        }
        
        return texts.joined(separator: " ")
    }
}
