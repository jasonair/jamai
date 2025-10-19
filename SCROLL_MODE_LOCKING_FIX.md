# Scroll Mode Locking Fix - Final Solution

## Problems Fixed

### 1. Node Scroll Breaking Mid-Gesture
**Issue:** When scrolling inside a node's conversation, moving cursor over prompt sections or other UI elements would cause the canvas to start panning, interrupting the node scroll.

**User expectation:** Once engaged in scrolling a node, the scroll should stay locked to that node until the gesture ends (finger lifted), regardless of what's under the cursor.

### 2. Team Member Modal Scroll Interference
**Issue:** Opening the team member modal didn't fully deselect the node, causing scroll issues within the modal.

## Root Cause

The scroll detection logic was re-evaluating **every scroll event independently**:
- Start scrolling in node → Mode: node scroll ✓
- Continue scrolling, cursor moves over prompt field → Re-evaluate → Mode switches to canvas pan ✗

This violated the principle that **scroll gestures should be atomic** - once started, the mode should lock until the gesture completes.

## Solution

### Part 1: Scroll Mode Locking (`MouseTrackingView.swift`)

Changed from boolean to **enum-based state machine**:

```swift
private enum ScrollMode {
    case none       // No active scroll
    case canvasPan  // Canvas panning in progress
    case nodeScroll // Node scrolling in progress
}
```

**Flow:**

```
First scroll event
    ↓
Is mouse over focused scroll view?
    ↓ YES → Set mode = .nodeScroll
    ↓ NO  → Set mode = .canvasPan
    ↓
Subsequent scroll events (within 0.2s)
    ↓
Switch on current mode:
    case .nodeScroll → LOCKED: Pass to system (ignore cursor position)
    case .canvasPan  → LOCKED: Pan canvas (ignore nodes)
    case .none       → Re-evaluate
    ↓
After 0.5s of no scrolling
    ↓
Reset mode to .none
```

**Key change:**
```swift
// OLD: Re-evaluated every event
if shouldLetSystemHandleScroll(for: event) {
    return event // Could switch modes mid-gesture
}

// NEW: Lock to initial mode
if timeSinceLastScroll < 0.2 {
    switch scrollMode {
    case .nodeScroll:
        return event // Stay locked, ignore cursor position
    case .canvasPan:
        onScroll(...) // Stay locked, ignore nodes
    case .none:
        break // Re-evaluate
    }
}
```

### Part 2: Modal First Responder Cleanup (`NodeView.swift`)

Added explicit first responder resignation when opening team member modal:

**Two locations:**
1. **Team Member Tray settings button** (line 77-81)
2. **Header Add Team Member button** (line 443-446)

```swift
// Before showing modal
DispatchQueue.main.async {
    NSApp.keyWindow?.makeFirstResponder(nil)
}
```

This ensures the node is fully deselected before the modal opens, preventing scroll interference.

## Technical Details

### Scroll Mode State Machine

```
State: none
    ↓
[User starts scrolling]
    ↓
Check: Mouse over focused scroll view?
    ↓
YES → nodeScroll state
NO  → canvasPan state
    ↓
[User continues scrolling rapidly]
    ↓
timeSinceLastScroll < 0.2s?
    ↓ YES
    ↓
LOCKED: Use current state
(ignore cursor position, ignore new hit tests)
    ↓
[User stops scrolling > 0.5s]
    ↓
Timer fires → none state
```

### Why This Works

1. **Gesture atomicity** - Trackpad gestures are naturally continuous
2. **Intent preservation** - First event determines user intent
3. **No mode switching** - Prevents jarring UX changes mid-gesture
4. **Natural reset** - Pause long enough (0.5s) allows mode change

### Parameters

- **Lock duration:** 0.2s - Events within this window maintain mode
- **Reset delay:** 0.5s - Time after last scroll to clear mode
- **Mode determination:** First event in gesture sets the mode

## Testing

### Test Case 1: Node Scroll Continuity ⭐ **CRITICAL**
1. Click inside a node to select it
2. Start scrolling the conversation (two-finger scroll)
3. Continue scrolling, let cursor move over prompt field, buttons, etc.
4. **Expected:** Node conversation continues scrolling smoothly
5. **Previous bug:** Canvas would start panning when cursor hit certain elements

### Test Case 2: Canvas Pan Through Nodes
1. Start scrolling on empty canvas
2. Move cursor over a deselected node while continuing to scroll
3. **Expected:** Canvas continues panning
4. **Previous:** Worked after earlier fixes ✓

### Test Case 3: Team Member Modal
1. Select a node (something gets focus)
2. Click team member settings or Add button
3. Modal opens
4. Scroll inside the modal
5. **Expected:** Modal scrolls smoothly, no canvas movement
6. **Previous bug:** Node's lingering first responder interfered with modal scroll

### Test Case 4: Mode Reset
1. Scroll within a node
2. Stop completely (pause > 0.5s)
3. Click outside the node on empty canvas
4. Start scrolling on canvas
5. **Expected:** Canvas pans (mode properly reset and re-evaluated)

## Files Modified

1. **`JamAI/Views/MouseTrackingView.swift`**
   - Lines 42-50: Changed from boolean to enum state machine
   - Lines 79-122: Implemented scroll mode locking logic

2. **`JamAI/Views/NodeView.swift`**
   - Lines 77-81: Added first responder resignation for tray settings button
   - Lines 443-446: Added first responder resignation for Add team member button

## Impact

**Before:**
- Node scrolling was unreliable and "jumpy"
- Cursor position could change scroll target mid-gesture
- Modals had scroll conflicts

**After:**
- ✅ Smooth, locked node scrolling
- ✅ Clean canvas panning
- ✅ No modal interference
- ✅ Predictable, stable behavior

## Performance

**Minimal overhead:**
- Simple enum comparison per scroll event
- No additional hit testing during locked mode
- Single timer per scroll gesture

## Future Considerations

1. Make timing thresholds user-configurable
2. Add visual feedback for scroll mode (optional)
3. Consider different lock durations for different input devices
4. Add gesture momentum detection for smoother transitions

## Related Fixes

This completes the scroll system overhaul:
1. ✅ Infinite render loops fixed
2. ✅ Deselected node release fixed  
3. ✅ Gesture continuity fixed
4. ✅ **Scroll mode locking fixed** (this document)
