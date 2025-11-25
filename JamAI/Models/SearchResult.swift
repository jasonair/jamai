//
//  SearchResult.swift
//  JamAI
//
//  Web search result model for unified search provider responses
//

import Foundation

/// Normalized search result from any provider
struct SearchResult: Codable, Equatable, Sendable {
    let title: String
    let snippet: String
    let url: String
    let source: String
    
    init(title: String, snippet: String, url: String, source: String) {
        self.title = title
        self.snippet = snippet
        self.url = url
        self.source = source
    }
}

/// Search provider type
enum SearchProvider: String, Codable, Sendable {
    case serper = "serper"
    case perplexity = "perplexity"
    
    var displayName: String {
        switch self {
        case .serper: return "Serper"
        case .perplexity: return "Perplexity"
        }
    }
    
    /// Credit cost per search
    var creditCost: Int {
        switch self {
        case .serper: return 0
        case .perplexity: return 0
        }
    }
}

/// Cached search entry stored in Firestore
struct CachedSearch: Codable {
    let queryHash: String
    let query: String
    let results: [SearchResult]
    let provider: SearchProvider
    let timestamp: Date
    let expiresAt: Date
    
    init(queryHash: String, query: String, results: [SearchResult], provider: SearchProvider) {
        self.queryHash = queryHash
        self.query = query
        self.results = results
        self.provider = provider
        self.timestamp = Date()
        // 30 days TTL
        self.expiresAt = Date().addingTimeInterval(30 * 24 * 60 * 60)
    }
    
    var isExpired: Bool {
        return Date() > expiresAt
    }
}

/// Search metadata for analytics
struct SearchMetadata: Codable {
    let provider: SearchProvider
    let query: String
    let cacheHit: Bool
    let responseTimeMs: Int
    let creditsUsed: Int
    let resultCount: Int
    let timestamp: Date
}
