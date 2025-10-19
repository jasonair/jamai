# Scroll Propagation Fix

## Problem

When scrolling within a node's conversation content and reaching the end of the scrollable area, scroll events would propagate to the parent canvas, causing the entire canvas to pan. This was particularly problematic when:

1. User is scrolling through conversation history
2. Reaches the end of content (top or bottom)
3. Continues scrolling gesture
4. Canvas unexpectedly moves instead of staying still

This broke the expected behavior where scrolling within a node should be isolated from canvas panning.

## Root Cause

SwiftUI's `ScrollView` component doesn't provide a way to block scroll event propagation. When a ScrollView reaches its scroll limits, scroll wheel events bubble up through the responder chain to parent views, eventually reaching the canvas pan gesture handlers.

The existing `NonPropagatingScrollView` class in `MarkdownText.swift` only handled scroll blocking for individual markdown text blocks, not for the entire conversation ScrollView.

## Solution

Created a reusable view modifier `.blockScrollPropagation()` that:

1. Adds an invisible overlay to the ScrollView
2. Intercepts scroll wheel events before they propagate
3. Forwards events to the nearest NSScrollView in the hierarchy
4. Stops propagation after handling, preventing canvas pan

### Implementation Details

**File:** `JamAI/Views/NonPropagatingScrollView.swift`

```swift
extension View {
    func blockScrollPropagation() -> some View {
        self.overlay(ScrollEventBlocker())
    }
}
```

**Key Features:**

1. **Transparent overlay** - Doesn't interfere with visual layout
2. **Event pass-through** - Allows clicks, drags, and other interactions
3. **Scroll interception** - Only captures scroll wheel events
4. **Smart forwarding** - Finds nearest NSScrollView and handles scroll there
5. **Propagation blocking** - Stops events from reaching canvas

### Applied To

The modifier is applied to both ScrollViews in `NodeView.swift`:

1. **Line 119** - Note chat section ScrollView
2. **Line 157** - Standard node conversation ScrollView

## Benefits

✅ **Isolated scrolling** - Node content scrolls independently of canvas  
✅ **No canvas jumping** - Canvas stays put while scrolling node content  
✅ **Preserved functionality** - All other interactions (click, drag, select) work normally  
✅ **ScrollViewReader compatibility** - Auto-scroll to new messages still works  
✅ **No performance impact** - Minimal overhead, events handled efficiently  

## Testing

1. Open a node with conversation history
2. Scroll through the content
3. Continue scrolling at the top/bottom boundaries
4. **Expected:** Node scrolls, canvas stays still
5. **Previous bug:** Canvas would pan when hitting scroll boundaries

## Technical Notes

### Why Not Replace ScrollView?

Initially considered replacing SwiftUI's `ScrollView` with a custom NSScrollView wrapper, but:
- Would lose `ScrollViewReader` functionality for auto-scrolling
- More invasive change with higher risk
- Modifier approach is cleaner and more maintainable

### Responder Chain

The solution works by inserting a view into the responder chain that:
1. Captures scroll events via `scrollWheel(with:)`
2. Walks up the view hierarchy to find NSScrollView
3. Forwards event directly to that scroll view
4. Returns without calling `super` or `nextResponder`, breaking the chain

### Alternative Approaches Considered

1. **Custom NSScrollView wrapper** - Too invasive, loses SwiftUI features
2. **Background blocker** - Doesn't work, needs to be in responder chain
3. **Event monitoring** - Global approach, too broad
4. **Gesture masking** - Doesn't work for scroll wheel events

## Files Modified

- `JamAI/Views/NonPropagatingScrollView.swift` (created)
- `JamAI/Views/NodeView.swift` (modified lines 119, 157)

## Related

- Previous scroll handling in `MarkdownText.swift` for text blocks
- Canvas pan gestures in `CanvasView.swift`
- Mouse tracking in `MouseTrackingView.swift`
