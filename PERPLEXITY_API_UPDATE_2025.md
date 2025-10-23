# Perplexity API Update - October 2025

## Issue
Web search with Perplexity was failing with error:
```
❌ Perplexity API error: Status 400
Response: {"error":{"message":"Invalid model 'llama-3.1-sonar-small-128k-online'. Permitted models can be found in the documentation at https://docs.perplexity.ai/getting-started/models.","type":"invalid_model","code":400}}
```

## Root Cause
Perplexity deprecated their old model naming scheme. The model `llama-3.1-sonar-small-128k-online` is no longer valid.

## API Changes (2025)

### Model Names
**Old (Deprecated as of August 2025)**:
- `llama-3.1-sonar-small-128k-online`
- `llama-3.1-sonar-large-128k-online`
- `llama-3.1-sonar-huge-128k-online`

**New (Current)**:
- `sonar` - Base model with web search (recommended for most use cases)
- `sonar-pro` - Pro model with enhanced search
- `sonar-reasoning` - Reasoning-focused model
- `sonar-reasoning-pro` - Pro reasoning model
- `sonar-deep-research` - Deep research model

### Response Format
**Deprecated** (May 2025):
- `citations` field - Array of URL strings

**Current**:
- `search_results` field - Array of objects with `title`, `url`, and `date`

**Old Request**:
```json
{
  "model": "llama-3.1-sonar-small-128k-online",
  "messages": [...],
  "return_citations": true,
  "return_related_questions": false
}
```

**New Request**:
```json
{
  "model": "sonar",
  "messages": [...]
}
```

**Old Response Parsing**:
```swift
if let citations = json?["citations"] as? [String] {
    // Process URL strings
}
```

**New Response Parsing**:
```swift
if let searchResults = json?["search_results"] as? [[String: Any]] {
    // Process objects with title, url, date
}
```

## Changes Made

### 1. SearchManager.swift (Perplexity API Update)

**Line 267**: Updated model name
```swift
// Before
"model": "llama-3.1-sonar-small-128k-online"

// After
"model": "sonar"
```

**Lines 266-272**: Removed deprecated parameters
```swift
// Before
"return_citations": true,
"return_related_questions": false

// After
// (Parameters removed - not needed)
```

**Lines 302-314**: Updated response parsing
```swift
// Before
if let citations = json?["citations"] as? [String] {
    results = citations.enumerated().compactMap { index, url in
        // Only had URL, generated title
    }
}

// After
if let searchResults = json?["search_results"] as? [[String: Any]] {
    results = searchResults.compactMap { result in
        let url = result["url"] as? String
        let title = result["title"] as? String ?? "Search Result"
        // Now have both title and URL from API
    }
}
```

### 2. CanvasView.swift (SwiftUI State Management Fix)

**Issue**: Warning "Publishing changes from within view updates is not allowed"

**Root Cause**: `generateResponse()` was being called synchronously from a view callback, which immediately modified `@Published` properties, causing state changes during view updates.

**Line 590-592**: Wrapped call in async Task
```swift
// Before
private func handlePromptSubmit(...) {
    viewModel.generateResponse(...)
}

// After
private func handlePromptSubmit(...) {
    Task { @MainActor in
        viewModel.generateResponse(...)
    }
}
```

This ensures state changes happen outside the view update cycle, eliminating the SwiftUI warning.

### 3. CanvasViewModel.swift (Citation Numbers Removal)

**Issue**: AI responses included inline citation numbers `[1][2][3]` throughout the text, cluttering the reading experience.

**Root Cause**: System prompt at line 1032 explicitly instructed AI to "Cite sources using [1], [2], etc."

**Line 1032**: Updated web search prompt instruction
```swift
// Before
"Please provide a comprehensive answer using the information from these sources. Cite sources using [1], [2], etc."

// After
"Please provide a comprehensive answer using the information from these sources. Do not include citation numbers or brackets in your response - the sources are shown separately to the user."
```

**Rationale**: Search result cards are already displayed separately in the UI below the response, making inline citations redundant and visually cluttered.

## Benefits

1. **Better titles**: Search results now include actual page titles instead of generic "Source 1", "Source 2"
2. **More metadata**: API now provides publication dates
3. **Simpler API**: Fewer parameters needed
4. **Future-proof**: Using current stable model names
5. **No SwiftUI warnings**: Proper async state management
6. **Cleaner reading experience**: No citation clutter `[1][2][3]` - sources shown separately

## Testing

After update, test with:
1. Enable web search (globe icon)
2. Try query: "List OpenAI's latest releases as of today 23 Oct 2025"
3. ✅ Should see proper search results with titles and URLs
4. ✅ Response text should be clean without `[1][2][3]` citation numbers
5. ✅ Search result cards displayed separately below the response
6. ✅ No SwiftUI warnings in console

## Model Selection Guidance

For JamAI's use case (quick factual searches):
- ✅ **sonar** - Fast, cost-effective, perfect for basic web search
- ⚠️ **sonar-pro** - More expensive, use for complex queries
- ❌ **sonar-deep-research** - Very expensive, overkill for real-time chat

Current implementation uses `sonar` which provides the best balance of speed, quality, and cost.

## Documentation

- Official docs: https://docs.perplexity.ai/
- Model cards: https://docs.perplexity.ai/docs/model-cards
- Changelog: https://docs.perplexity.ai/changelog

## Version Info

- **Updated**: October 23, 2025
- **API Version**: Current stable
- **Breaking Changes**: Yes (model names, response format)
- **Backward Compatibility**: No (must update to continue using)
