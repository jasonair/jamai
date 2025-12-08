# Clickable Links with External Link Confirmation

## Overview

URLs in node content (both user prompts and AI responses) are now clickable. When clicked, a confirmation dialog appears warning users they're about to leave Jam AI, giving them options to:
- **Open in Browser** - Opens the URL in the default browser
- **Copy Link** - Copies the URL to clipboard
- **Cancel** - Dismisses the dialog

## UX Research & Best Practices

This follows standard macOS patterns used by apps like:
- **Slack** - Shows confirmation before opening external links
- **Discord** - Warns about leaving the application
- **Mail.app** - Allows copying or opening links

Key UX considerations:
- Show the full URL so users know exactly where they're going
- Provide copy option for users who want to inspect URLs first
- Use native macOS alert styling for familiarity
- Don't block internal links (mailto:, tel:, etc.)

## Implementation

### Files Created

**`JamAI/Services/ExternalLinkService.swift`**
- `ExternalLinkService` singleton for URL handling
- `detectLinks(in:)` - Uses `NSDataDetector` to find URLs in text
- `addLinkAttributes(to:isDarkMode:)` - Adds clickable link styling to NSAttributedString
- `openWithConfirmation(url:)` - Shows macOS native confirmation dialog
- `isExternalURL(_:)` - Determines if URL should show confirmation
- `LinkClickDelegate` - NSTextViewDelegate that intercepts link clicks
- `String.withDetectedLinks()` - Extension to convert strings to AttributedString with links

### Files Modified

**`JamAI/Views/MarkdownText.swift`**
1. In `convertToNSAttributedString()`:
   - Added check for `run.link` to preserve markdown links `[text](url)`
   - Styled links with `NSColor.linkColor` and underline
   - Added `ExternalLinkService.shared.addLinkAttributes()` call to detect raw URLs

2. In `NSTextViewWrapper.makeNSView()`:
   - Set `textView.delegate = LinkClickDelegate.shared` to intercept clicks
   - Disabled automatic link detection (we do it ourselves)

**`JamAI/Views/NodeView.swift`**
- User messages now use `Text(displayText.withDetectedLinks())`
- Added `.environment(\.openURL, ...)` to intercept clicks and show confirmation

## How It Works

### AI Responses (MarkdownText)
1. Text is parsed as markdown via `AttributedString`
2. Markdown links `[text](url)` get `.link` attribute automatically
3. `convertToNSAttributedString()` preserves these links
4. `ExternalLinkService.addLinkAttributes()` detects raw URLs (`https://...`)
5. `NSTextViewWrapper` renders with `LinkClickDelegate` intercepting clicks
6. Clicks trigger `ExternalLinkService.openWithConfirmation()`

### User Messages (NodeView)
1. `String.withDetectedLinks()` detects URLs via `NSDataDetector`
2. Returns `AttributedString` with `.link` attributes
3. SwiftUI `Text` renders links as clickable
4. `.environment(\.openURL, ...)` intercepts clicks
5. External URLs show confirmation dialog

## Supported Link Types

| Link Type | Example | Behavior |
|-----------|---------|----------|
| Raw URLs | `https://example.com` | ✅ Clickable with confirmation |
| Markdown links | `[click here](https://example.com)` | ✅ Clickable with confirmation |
| Email | `mailto:user@example.com` | ✅ Opens directly (no confirmation) |
| Phone | `tel:+1234567890` | ✅ Opens directly (no confirmation) |

## Notes on Notes

Note descriptions use `TextEditor` for always-editable FigJam/Miro-style editing. Making links clickable in an editable text field would require complex handling (e.g., Command+Click). This is intentionally not implemented to maintain simple, predictable editing behavior.

## Testing Checklist

- [ ] Paste URL in chat prompt, submit, verify clickable in conversation
- [ ] Have AI generate response with URLs, verify clickable
- [ ] Have AI generate markdown links `[text](url)`, verify clickable
- [ ] Click external link, verify confirmation dialog appears
- [ ] Click "Open in Browser", verify URL opens
- [ ] Click "Copy Link", verify URL copied to clipboard
- [ ] Click "Cancel", verify nothing happens
- [ ] Email links (`mailto:`) should open directly without confirmation
- [ ] Phone links (`tel:`) should open directly without confirmation
