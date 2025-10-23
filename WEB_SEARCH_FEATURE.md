# Web Search Feature

## Overview

The web search feature provides dual-provider web search integration (Serper.dev and Perplexity AI) with intelligent caching and credit metering. Users can toggle web search on/off via a globe icon in the chat input, and search results are automatically included in the AI's context.

## Architecture

### Provider Selection

- **Free/Starter Plans**: Serper.dev API (1 credit per search)
- **Pro/Teams/Enterprise Plans**: Option to use Perplexity API (5 credits per search) when enhanced search is enabled

### Caching Strategy

- All search results are cached in Firestore for **30 days**
- Cache key: SHA-256 hash of normalized query (lowercased, trimmed)
- Cache hits: **No credit deduction**
- Cache misses: Credit deduction based on provider used

### Credit Costs

| Provider | Credits | Plan Requirement |
|----------|---------|------------------|
| Serper | 1 | All plans |
| Perplexity | 5 | Pro+ plans with enhanced search |

## Components

### Models

**SearchResult.swift**
```swift
struct SearchResult: Codable, Equatable, Sendable {
    let title: String
    let snippet: String
    let url: String
    let source: String
}
```

**SearchProvider**
```swift
enum SearchProvider: String, Codable, Sendable {
    case serper = "serper"
    case perplexity = "perplexity"
}
```

**CachedSearch**
- Stored in Firestore collection: `cached_searches`
- Document ID: SHA-256 hash of query
- TTL: 30 days

### Services

**SearchManager.swift**
- Singleton service (`SearchManager.shared`)
- Main method: `search(query:userPlan:enhancedSearch:creditsRemaining:)`
- Handles provider selection, caching, and credit deduction
- Logs analytics to `users/{userId}/search_history`

### UI Components

**NodeView.swift**
- Globe icon toggle button (`webSearchEnabled` state)
- Positioned next to image upload button in chat input
- Visual feedback: highlighted when active
- Automatically resets after message submission

### Integration

**ConversationMessage**
- Extended with `webSearchEnabled: Bool`
- Extended with `searchResults: [SearchResult]?`

**CanvasViewModel**
- `generateResponse()` method updated with `webSearchEnabled` parameter
- New helper: `continueGenerationWithSearch()` handles AI generation with search context
- Search results formatted into enhanced prompt with citations

## Setup

### 1. Environment Variables

Add to your shell profile (`.zshrc`, `.bash_profile`, etc.):

```bash
export SERPER_API_KEY="your-serper-api-key"
export PERPLEXITY_API_KEY="your-perplexity-api-key"
```

Or create a `.env` file (not committed to git):

```bash
SERPER_API_KEY=your-serper-api-key
PERPLEXITY_API_KEY=your-perplexity-api-key
```

### 2. Get API Keys

**Serper.dev**
1. Sign up at https://serper.dev
2. Get API key from dashboard
3. Free tier: 2,500 searches/month

**Perplexity AI**
1. Sign up at https://www.perplexity.ai/settings/api
2. Get API key from settings
3. Pay-as-you-go pricing: ~$0.005 per search

### 3. Firestore Security Rules

Deploy the updated `firestore.rules`:

```bash
firebase deploy --only firestore:rules
```

Rules include:
- `cached_searches/{queryHash}` - Shared cache for all authenticated users
- `users/{userId}/search_history/{searchId}` - Per-user search analytics

## Usage

### For Users

1. Click the globe icon (🌐) in the chat input to enable web search
2. Type your question and send
3. The AI will search the web and provide answers with citations
4. Search results are cached for future use

### For Developers

```swift
// Search with automatic provider selection
let results = await SearchManager.shared.search(
    query: "latest Swift concurrency features",
    userPlan: .pro,
    enhancedSearch: true,
    creditsRemaining: 500
)

// Results are normalized SearchResult objects
if let results = results {
    for result in results {
        print("\(result.title) - \(result.source)")
        print(result.snippet)
    }
}
```

## Analytics

Search metadata logged to `users/{userId}/search_history`:

```swift
struct SearchMetadata {
    let provider: SearchProvider
    let query: String
    let cacheHit: Bool
    let responseTimeMs: Int
    let creditsUsed: Int
    let resultCount: Int
    let timestamp: Date
}
```

## Performance

- **Cache Hit**: ~50-100ms (Firestore read only)
- **Cache Miss (Serper)**: ~500-800ms
- **Cache Miss (Perplexity)**: ~1-2s

## Error Handling

- Missing API keys: Logs error, returns `nil`
- Insufficient credits: Returns `nil` before API call
- API failures: Returns `nil`, logs error
- Network timeouts: Returns `nil` after standard URLSession timeout

## Future Enhancements

1. **BYO API Keys**: Allow users to provide their own Perplexity key
2. **Search History UI**: Display search history in user settings
3. **Cache Management**: Allow users to clear their search cache
4. **Advanced Filters**: Date range, domain filtering, result count
5. **Redis Caching**: For faster cache hits in production

## Testing

### Manual Testing Checklist

- [ ] Globe icon appears in chat input
- [ ] Toggle changes icon highlight state
- [ ] Free plan uses Serper
- [ ] Pro plan with enhanced search uses Perplexity
- [ ] Cache hits don't deduct credits
- [ ] Cache misses deduct correct amount
- [ ] Search results appear in conversation
- [ ] AI responses include citations
- [ ] Analytics logged correctly
- [ ] Security rules enforce access control

### Test Queries

```
1. "What is Swift 6.0?"
2. "Latest AI trends 2024"
3. "How to implement async/await in Swift?"
```

## Troubleshooting

### "No search results"

- Check API keys are set correctly
- Verify network connectivity
- Check Firestore permissions

### "Insufficient credits"

- User needs to upgrade plan or wait for monthly reset
- Check credit balance in user settings

### "Search very slow"

- First search (cache miss) will be slower
- Subsequent identical searches use cache (fast)

## Files Modified

### New Files
- `JamAI/Models/SearchResult.swift`
- `JamAI/Services/SearchManager.swift`
- `WEB_SEARCH_FEATURE.md` (this file)

### Modified Files
- `JamAI/Models/ConversationMessage.swift` - Added search fields
- `JamAI/Models/Node.swift` - Updated `addMessage()` signature
- `JamAI/Views/NodeView.swift` - Added globe toggle, updated callback
- `JamAI/Views/NodeItemWrapper.swift` - Updated callback signature
- `JamAI/Views/CanvasView.swift` - Pass webSearchEnabled to ViewModel
- `JamAI/Services/CanvasViewModel.swift` - Integrated SearchManager
- `firestore.rules` - Added cache and search history rules

## Credits

This feature integrates:
- [Serper.dev](https://serper.dev) - Google Search API
- [Perplexity AI](https://www.perplexity.ai) - AI-powered search
- Firebase Firestore for caching and analytics
