//
//  SearchManager.swift
//  JamAI
//
//  Manages web search with dual providers (Serper/Perplexity) and caching
//

import Foundation
import CryptoKit
import FirebaseFirestore
import FirebaseAuth

/// Manages web search with provider selection, caching, and credit metering
@MainActor
class SearchManager {
    
    static let shared = SearchManager()
    
    private let db = Firestore.firestore()
    private let cacheCollection = "cached_searches"
    
    // API Keys from environment/config
    private var serperAPIKey: String? {
        ProcessInfo.processInfo.environment["SERPER_API_KEY"]
    }
    
    private var perplexityAPIKey: String? {
        ProcessInfo.processInfo.environment["PERPLEXITY_API_KEY"]
    }
    
    // Feature flag: Set to true to enable subscription-based provider selection (Perplexity for Pro+)
    // Set to false to always use Serper regardless of user plan
    private var enableSubscriptionBasedProviderSelection: Bool {
        // Check environment variable first, default to false (Serper-only)
        if let envValue = ProcessInfo.processInfo.environment["ENABLE_SUBSCRIPTION_BASED_SEARCH"], 
           envValue.lowercased() == "true" {
            return true
        }
        return false
    }
    
    private init() {}
    
    // MARK: - Public API
    
    /// Performs a web search with automatic provider selection based on user plan
    /// - Parameters:
    ///   - query: Search query
    ///   - userPlan: User's subscription plan
    ///   - enhancedSearch: Whether to use Perplexity (Pro+ only)
    ///   - creditsRemaining: User's remaining credits
    /// - Returns: Search results or nil if insufficient credits/error
    func search(
        query: String,
        userPlan: UserPlan,
        enhancedSearch: Bool = false,
        creditsRemaining: Int
    ) async -> [SearchResult]? {
        
        let startTime = Date()
        let queryHash = hashQuery(query)
        
        // 1. Check cache first
        if let cached = await checkCache(queryHash: queryHash) {
            print("🔍 SearchManager: Cache HIT for query '\(query)'")
            
            // Log analytics (no credit deduction)
            await logSearchMetadata(
                provider: cached.provider,
                query: query,
                cacheHit: true,
                responseTimeMs: Int(Date().timeIntervalSince(startTime) * 1000),
                creditsUsed: 0,
                resultCount: cached.results.count
            )
            
            return cached.results
        }
        
        print("🔍 SearchManager: Cache MISS for query '\(query)'")
        
        // 2. Determine provider based on plan
        let provider = selectProvider(userPlan: userPlan, enhancedSearch: enhancedSearch)
        let creditCost = provider.creditCost
        
        // 3. Check if user has enough credits
        guard creditsRemaining >= creditCost else {
            print("❌ SearchManager: Insufficient credits (need \(creditCost), have \(creditsRemaining))")
            return nil
        }
        
        // 4. Perform search
        guard let results = await performSearch(query: query, provider: provider) else {
            print("❌ SearchManager: Search failed for provider \(provider.displayName)")
            return nil
        }
        
        // 5. Cache results
        await cacheResults(queryHash: queryHash, query: query, results: results, provider: provider)
        
        // 6. Deduct credits
        if let userId = FirebaseAuthService.shared.currentUser?.uid {
            let success = await FirebaseDataService.shared.deductCredits(
                userId: userId,
                amount: creditCost,
                description: "Web Search (\(provider.displayName))"
            )
            
            if !success {
                print("⚠️ SearchManager: Credit deduction failed but search completed")
            }
        }
        
        // 7. Log analytics
        await logSearchMetadata(
            provider: provider,
            query: query,
            cacheHit: false,
            responseTimeMs: Int(Date().timeIntervalSince(startTime) * 1000),
            creditsUsed: creditCost,
            resultCount: results.count
        )
        
        print("✅ SearchManager: Search completed via \(provider.displayName), \(results.count) results, \(creditCost) credits")
        
        return results
    }
    
    // MARK: - Provider Selection
    
    private func selectProvider(userPlan: UserPlan, enhancedSearch: Bool) -> SearchProvider {
        // If subscription-based selection is disabled, always use Serper
        if !enableSubscriptionBasedProviderSelection {
            return .serper
        }
        
        // Pro+ with enhanced search enabled → Perplexity
        if (userPlan == .pro || userPlan == .teams || userPlan == .enterprise) && enhancedSearch {
            return .perplexity
        }
        
        // Everyone else → Serper
        return .serper
    }
    
    // MARK: - Cache Management
    
    private func hashQuery(_ query: String) -> String {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data(normalized.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func checkCache(queryHash: String) async -> CachedSearch? {
        do {
            let doc = try await db.collection(cacheCollection).document(queryHash).getDocument()
            
            if let cached = try? doc.data(as: CachedSearch.self) {
                if !cached.isExpired {
                    return cached
                } else {
                    // Clean up expired cache
                    try? await doc.reference.delete()
                    print("🗑️ SearchManager: Deleted expired cache entry")
                }
            }
        } catch {
            print("⚠️ SearchManager: Cache check failed - \(error.localizedDescription)")
        }
        
        return nil
    }
    
    private func cacheResults(
        queryHash: String,
        query: String,
        results: [SearchResult],
        provider: SearchProvider
    ) async {
        let cached = CachedSearch(
            queryHash: queryHash,
            query: query,
            results: results,
            provider: provider
        )
        
        do {
            try db.collection(cacheCollection).document(queryHash).setData(from: cached)
            print("💾 SearchManager: Cached results for query '\(query)'")
        } catch {
            print("⚠️ SearchManager: Failed to cache results - \(error.localizedDescription)")
        }
    }
    
    // MARK: - Search Providers
    
    private func performSearch(query: String, provider: SearchProvider) async -> [SearchResult]? {
        switch provider {
        case .serper:
            return await searchSerper(query: query)
        case .perplexity:
            return await searchPerplexity(query: query)
        }
    }
    
    private func searchSerper(query: String) async -> [SearchResult]? {
        guard let apiKey = serperAPIKey else {
            print("❌ SearchManager: SERPER_API_KEY not configured")
            return nil
        }
        
        guard let url = URL(string: "https://google.serper.dev/search") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        
        let body: [String: Any] = ["q": query]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            
            if httpResponse.statusCode != 200 {
                print("❌ Serper API error: Status \(httpResponse.statusCode)")
                if let responseText = String(data: data, encoding: .utf8) {
                    print("Response: \(responseText)")
                }
                return nil
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            guard let organic = json?["organic"] as? [[String: Any]] else {
                print("❌ Serper: No organic results found")
                return nil
            }
            
            // Parse results
            let results = organic.prefix(10).compactMap { item -> SearchResult? in
                guard let title = item["title"] as? String,
                      let snippet = item["snippet"] as? String,
                      let link = item["link"] as? String else {
                    return nil
                }
                
                let source = item["source"] as? String ?? extractDomain(from: link)
                
                return SearchResult(
                    title: title,
                    snippet: snippet,
                    url: link,
                    source: source
                )
            }
            
            return results
            
        } catch {
            print("❌ Serper search failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func searchPerplexity(query: String) async -> [SearchResult]? {
        guard let apiKey = perplexityAPIKey else {
            print("❌ SearchManager: PERPLEXITY_API_KEY not configured")
            return nil
        }
        
        guard let url = URL(string: "https://api.perplexity.ai/chat/completions") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "model": "sonar",
            "messages": [
                ["role": "system", "content": "Be precise and concise. Provide factual information with sources."],
                ["role": "user", "content": query]
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            
            if httpResponse.statusCode != 200 {
                print("❌ Perplexity API error: Status \(httpResponse.statusCode)")
                if let responseText = String(data: data, encoding: .utf8) {
                    print("Response: \(responseText)")
                }
                return nil
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            guard let choices = json?["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                print("❌ Perplexity: Invalid response format")
                return nil
            }
            
            // Parse search_results if available
            var results: [SearchResult] = []
            
            if let searchResults = json?["search_results"] as? [[String: Any]] {
                results = searchResults.compactMap { result in
                    guard let url = result["url"] as? String else { return nil }
                    let title = result["title"] as? String ?? "Search Result"
                    let domain = extractDomain(from: url)
                    return SearchResult(
                        title: title,
                        snippet: content,
                        url: url,
                        source: domain
                    )
                }
            }
            
            // If no search results, create single result with content
            if results.isEmpty {
                results.append(SearchResult(
                    title: "Perplexity Search Result",
                    snippet: content,
                    url: "https://www.perplexity.ai/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")",
                    source: "Perplexity AI"
                ))
            }
            
            return results
            
        } catch {
            print("❌ Perplexity search failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Utilities
    
    private func extractDomain(from urlString: String) -> String {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return "Unknown"
        }
        
        // Remove www. prefix
        return host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }
    
    // MARK: - Analytics
    
    private func logSearchMetadata(
        provider: SearchProvider,
        query: String,
        cacheHit: Bool,
        responseTimeMs: Int,
        creditsUsed: Int,
        resultCount: Int
    ) async {
        guard let userId = FirebaseAuthService.shared.currentUser?.uid else { return }
        
        let metadata = SearchMetadata(
            provider: provider,
            query: query,
            cacheHit: cacheHit,
            responseTimeMs: responseTimeMs,
            creditsUsed: creditsUsed,
            resultCount: resultCount,
            timestamp: Date()
        )
        
        do {
            try db.collection("users")
                .document(userId)
                .collection("search_history")
                .addDocument(from: metadata)
        } catch {
            print("⚠️ SearchManager: Failed to log metadata - \(error.localizedDescription)")
        }
    }
}
