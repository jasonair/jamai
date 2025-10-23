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

### 4. NodeView.swift (Search Results UI & Web Search Indicators)

**New Features Added**:

1. **Search Result Cards** (Lines 793-856)
   - **Vertical stack** of source cards (no horizontal scrolling to avoid conflicts)
   - Shows up to 5 sources with numbered badges (1-5)
   - Clickable cards that open URLs in browser
   - Each card displays: number badge, title (2 lines max), domain, external link icon
   - Clean design with subtle borders and hover effects
   - Safe implementation - no nested scrollviews that could interfere with canvas
   
2. **Web Search Footer** (Lines 774-784)
   - Small text "Generated using web search" below AI responses that used search
   - Only appears for messages with `webSearchEnabled: true`
   - Centered and styled in secondary color for subtle indication

3. **Web Search Progress Indicator** (Lines 1137-1152)
   - Animated spinning globe icon during web search
   - "Searching the web..." text with pulsing animation
   - Appears below main processing message ("Jamming...", "Cooking up something good...")
   - Only shows when last user message had web search enabled

4. **PRO SEARCH Button** (Lines 933-962)
   - Shows "PRO SEARCH" text for Pro/Teams/Enterprise users
   - Pill-shaped outline button with no background (default state)
   - Globe icon + text for premium users, just globe for Free users
   - **Active state**: Blue background with white text when enabled
   - **Stays blue during generation** - remains active while AI is responding
   - Only resets when generation completes
   - Disabled during generation to prevent toggle

**Implementation Details**:
```swift
// Search results displayed in vertical stack (safe, no nested scrolling)
private func searchResultsView(results: [SearchResult]) -> some View {
    VStack(spacing: 8) {
        ForEach(Array(results.prefix(5).enumerated()), id: \.offset) { index, result in
            Button { openURL(result.url) } {
                HStack {
                    Text("\(index + 1)")  // Numbered badge
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .frame(width: 20, height: 20)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading) {
                        Text(result.title).lineLimit(2)
                        Text(result.source)
                    }
                    
                    Image(systemName: "arrow.up.right")
                }
            }
        }
    }
}

// PRO SEARCH button with pill outline style
let isSearchActive = webSearchEnabled || (isGenerating && lastUserMsg.webSearchEnabled)

Button(action: { webSearchEnabled.toggle() }) {
    HStack(spacing: 4) {
        Image(systemName: "globe")
        if isPremiumUser {
            Text("PRO SEARCH")
                .font(.system(size: 11, weight: .semibold))
        }
    }
    .foregroundColor(isSearchActive ? .white : .secondary)
    .background(isSearchActive ? Color.accentColor : Color.clear)
    .cornerRadius(12)
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .stroke(isSearchActive ? Color.accentColor : Color.secondary.opacity(0.3))
    )
}
.disabled(isGenerating)  // Stays active during generation
```

## Benefits

1. **Better titles**: Search results now include actual page titles instead of generic "Source 1", "Source 2"
2. **More metadata**: API now provides publication dates
3. **Simpler API**: Fewer parameters needed
4. **Future-proof**: Using current stable model names
5. **No SwiftUI warnings**: Proper async state management
6. **Cleaner reading experience**: No citation clutter `[1][2][3]` - sources shown separately
7. **Interactive source cards**: Numbered cards with titles, domains, and click-to-open functionality
8. **Safe implementation**: Vertical stack avoids nested scrollview conflicts with canvas
9. **Visual feedback**: Spinning globe animation shows when web search is active
10. **Clear attribution**: "Generated using web search" footer on search-powered responses
11. **Premium branding**: "PRO SEARCH" button for Pro/Teams/Enterprise users
12. **Persistent state**: Button stays active during generation to show search is in use

## Testing

After update, test with:
1. Enable web search (globe icon 🌐)
2. Try query: "List OpenAI's latest releases as of today 23 Oct 2025"

**Expected Results**:
- ✅ **PRO SEARCH button**: 
  - Shows "PRO SEARCH" text if user is Pro/Teams/Enterprise
  - Pill-shaped with outline (no background when inactive)
  - Turns blue with white text when clicked
  - **Stays blue during generation** and only resets when complete
  - Button is disabled (can't toggle) while generating
- ✅ **During generation**: 
  - See spinning globe 🌐 with "Searching the web..." text below "Jamming..." message
  - PRO SEARCH button remains blue/active
- ✅ **Response text**: Clean content without `[1][2][3]` citation numbers
- ✅ **Source cards**: 
  - Vertical stack of numbered cards (1, 2, 3, 4, 5)
  - Each shows: circle badge, title (2 lines), domain, external link arrow
  - Up to 5 sources displayed
  - No horizontal scrolling - safe for canvas interactions
- ✅ **Interactive**: Click any card to open URL in browser, hover to see full URL tooltip
- ✅ **Footer**: Small "Generated using web search" text at bottom of response
- ✅ **Console**: No SwiftUI warnings about publishing changes

**Visual Verification**:
- PRO SEARCH button should have pill shape (rounded corners) with outline border
- Globe icon should spin continuously during search
- Source cards should show actual page titles (e.g., "Project Sharing in ChatGPT") with numbered badges
- Cards should be stacked vertically, full-width, with subtle borders
- No scrolling conflicts with canvas panning or node scrolling

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
