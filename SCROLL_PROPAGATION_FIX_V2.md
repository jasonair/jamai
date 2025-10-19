# Scroll Propagation Fix V2 - Gesture Continuity

## Problem

**Primary Issue:** When two-finger scrolling the canvas and the cursor passed over a node's conversation area, the scroll would "catch" or "stop" on that node instead of continuing to pan the canvas smoothly.

**Secondary Issue:** After deselecting a node by clicking outside, scrolling near that node's chat area would still prevent canvas panning.

This broke the expected UX where:
1. Canvas pan should continue smoothly even when cursor passes over nodes
2. Deselected nodes shouldn't interfere with canvas scrolling

## Root Cause

Two issues in `MouseTrackingView.swift`:

1. **No gesture continuity tracking** - Each scroll event was evaluated independently, allowing nodes to "hijack" ongoing canvas pan gestures

2. **Incorrect scroll detection** - Used first responder checking instead of hit-testing, which didn't properly handle deselected nodes

## Solution

### 1. Gesture Continuity Tracking

Added state tracking to maintain canvas pan mode once started:

```swift
private var isCanvasPanInProgress = false
private var lastScrollTime: TimeInterval = 0
private var scrollResetTimer: Timer?
```

**Logic:**
- When canvas panning starts (not over a scroll view), sets `isCanvasPanInProgress = true`
- If next scroll event occurs within 0.2s AND flag is true → continues canvas pan regardless of cursor position
- Timer resets the flag after 0.5s of no scrolling
- Prevents nodes from "catching" mid-gesture

### 2. First Responder + Focus-Based Detection

**Critical fix:** Only allow scroll views to intercept if they **contain the first responder**:

```swift
private func shouldLetSystemHandleScroll(for event: NSEvent) -> Bool {
    guard let firstResponder = window.firstResponder as? NSView else { return false }
    let responderScrollView = firstResponder.enclosingScrollView
    guard let activeScrollView = responderScrollView else { return false }
    
    // Check if mouse is over the ACTIVE scroll view
    let scrollViewRect = activeScrollView.convert(activeScrollView.bounds, to: nil)
    if !scrollViewRect.contains(location) { return false }
    
    // Check if it has scrollable content
    return hasVerticalScroll
}
```

**Benefits:**
- **Deselected nodes completely release control** - no first responder = no blocking
- Only the actively focused scroll view can intercept
- Mouse must be over that specific active scroll view
- Perfect for click-outside-to-deselect UX

### 3. Removed Overlay Approach

Initially tried adding `.blockScrollPropagation()` modifier to ScrollViews, but this:
- Always blocked scroll, even when deselected
- Broke natural AppKit responder chain
- Created more problems than it solved

**Reverted changes:**
- Removed `.blockScrollPropagation()` calls from NodeView.swift (lines 119, 157)
- Kept NonPropagatingScrollView.swift for potential future use

## Implementation Details

### Gesture Detection Flow

```
Scroll Event Received
    ↓
Sheet open? → Pass through to sheet
    ↓
Time since last scroll < 0.2s AND isCanvasPanInProgress?
    ↓ YES → Continue canvas pan (ignore nodes)
    ↓ NO
    ↓
Mouse over NSScrollView with scrollable content?
    ↓ YES → Pass to scroll view, set isCanvasPanInProgress = false
    ↓ NO → Canvas pan, set isCanvasPanInProgress = true
    ↓
Schedule 0.5s timer to reset isCanvasPanInProgress
```

### Key Parameters

- **Continuity threshold:** 0.2s - Scroll events within this window maintain mode
- **Reset delay:** 0.5s - How long after last scroll to clear canvas pan mode
- **Hit test:** Direct NSView.hitTest() at event location

## Testing

### Test Case 1: Canvas Pan Continuity
1. Start scrolling on empty canvas
2. Move cursor over a node while continuing to scroll
3. **Expected:** Canvas continues panning smoothly
4. **Previous bug:** Scroll would "catch" on the node

### Test Case 2: Deselected Node ⭐ **CRITICAL TEST**
1. Click a node to select it (something gets focus)
2. Click outside the node to deselect (first responder changes)
3. Scroll anywhere on canvas, even with cursor directly over the deselected node
4. **Expected:** Canvas pans freely, deselected node doesn't intercept
5. **Previous bug:** Deselected node's scroll area would still block canvas pan

### Test Case 3: Intentional Node Scrolling
1. Click inside a node's conversation
2. Start scrolling (cursor over node)
3. **Expected:** Node's conversation scrolls
4. Should work as before

### Test Case 4: Node to Canvas Transition
1. Scroll within a node
2. Stop scrolling (pause > 0.5s)
3. Start scrolling on canvas
4. **Expected:** Canvas pans (mode properly reset)

## Files Modified

- `JamAI/Views/MouseTrackingView.swift` (lines 42-45, 73-101, 123)
- `JamAI/Views/NodeView.swift` (removed blockScrollPropagation calls)

## Performance Impact

**Minimal overhead:**
- Simple timestamp comparison per scroll event
- Single timer per scroll gesture (auto-canceling)
- Hit test already part of normal event handling

## Future Improvements

Consider adding:
1. User preference for scroll behavior (sticky vs. pass-through)
2. Visual indicator when canvas pan mode is locked
3. Configurable timing thresholds

## Related

- MarkdownText.swift - Has NonPropagatingScrollView for individual text blocks
- CanvasView.swift - Pan gestures and zoom handling
- NodeView.swift - Conversation scroll areas
