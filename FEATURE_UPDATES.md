# Feature Updates

## Changes Implemented

### 1. Renamed "AI" to "Jam"
All AI response labels have been changed to "Jam" throughout the application:

**Files Modified:**
- `JamAI/Views/NodeView.swift` - Changed message label from "AI" to "Jam"
- `JamAI/Services/CanvasViewModel.swift` - Updated conversation formatting and title generation to use "Jam"

**Details:**
- User messages display as "You"
- AI/Assistant messages now display as "Jam"
- TLDR summaries now use "Jam" for assistant messages
- Auto-generated titles and descriptions now reference "Jam" instead of "AI"

---

### 2. Text Selection with Expand Functionality

Implemented interactive text selection with automatic branch creation for expanding on selected content.

**Files Modified:**
- `JamAI/Views/NodeView.swift` - Added contextMenu to MarkdownText with expand option
- `JamAI/Views/NodeItemWrapper.swift` - Added onExpandSelection parameter pass-through
- `JamAI/Views/CanvasView.swift` - Added handleExpandSelection handler
- `JamAI/Services/CanvasViewModel.swift` - Added expandSelectedText and generateExpandedResponse methods

**How It Works:**

1. **Text Selection**: Users select any text within message responses or prompts using native SwiftUI text selection (MarkdownText with `.textSelection(.enabled)`)
2. **Right-Click**: Right-click on the message to open SwiftUI's native context menu
3. **Expand Option**: Click "Expand on Selection" from the context menu
4. **Branch Creation**: 
   - Checks system pasteboard for selected text
   - Creates a new child node branching from the current node
   - Sends an internal prompt: "Expand on this: '[selected text]'. Provide a short, concise explanation with additional context."
   - **The prompt is NOT shown to the user** - only the Jam response appears
   - Auto-generates a title and description based on the selected text and response
   - Positions the new node to the right and slightly below the parent

**Technical Implementation:**
- Uses original `MarkdownText` component with native SwiftUI `.contextMenu` modifier
- Preserves all original UI behavior: scrolling, text selection, hovering
- Reads selected text from system pasteboard when context menu action is triggered
- Separate `generateExpandedResponse` method that doesn't add prompt to conversation
- Only the assistant response is added to the conversation history
- `autoGenerateTitleForExpansion` generates title/description immediately after response
- Async workflow to generate TLDR summary of parent node before expansion
- Context-aware prompt generation that includes parent conversation context
- Zero impact on layout, scrolling, or mouse interaction behavior

---

## Benefits

1. **Clearer Branding**: "Jam" is more aligned with the application name (JamAI)
2. **Enhanced Exploration**: Users can drill down into specific concepts by selecting text
3. **Natural Workflow**: Right-click context menu feels native to macOS
4. **Maintains Context**: New branches include summary context from parent conversation
5. **Clean UI**: Preserves original scrolling behavior without nested scroll views
6. **Focused Experience**: New nodes show only the response, not the internal expansion prompt
7. **Auto-titled**: New expansion nodes automatically get descriptive titles

---

## Testing Recommendations

1. Test text selection in both user and Jam messages
2. Verify context menu appears on right-click with selection
3. Confirm branch node creation and positioning
4. Check that only Jam response appears (no prompt shown)
5. Verify title and description are auto-generated
6. Test with multiple sequential expansions
7. Verify scrolling works properly in node conversation areas
8. Check that context from parent node is properly included in expansion
