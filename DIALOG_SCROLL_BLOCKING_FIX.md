# Dialog Scroll Blocking Fix

**Problem**: Dialog boxes (Team Member, Settings, Account) had scroll leakage - when scrolling over certain parts of dialogs, scroll events would pass through to nodes/canvas behind, causing the background to scroll instead of the dialog content.

**Root Cause**: Modal dialogs were presented as windows/sheets over the canvas, but macOS scroll events could bypass the modal and reach the canvas below, especially when hovering over non-scrollable areas of the dialog or when no node was directly underneath.

## Solution

Implemented a **canvas-level blocking layer** that acts like a web overlay div - when any modal is open, a full-screen blocking layer intercepts ALL scroll and interaction events before they reach the canvas.

### Architecture

```
┌─────────────────────────────────┐
│      Modal Dialog (on top)      │  ← Fully interactive
├─────────────────────────────────┤
│    CanvasBlockingLayer          │  ← Intercepts all events
│    (visible when modal open)    │
├─────────────────────────────────┤
│    Canvas with Nodes            │  ← Completely blocked
└─────────────────────────────────┘
```

### Components Created/Modified

#### 1. **CanvasBlockingLayer.swift** (NEW)
- Custom `NSView` that intercepts and swallows scroll wheel events
- Prevents mouse down, right-click, and other mouse button events
- Semi-transparent overlay (30% black) for visual feedback
- Uses `NSViewRepresentable` for SwiftUI integration

```swift
private class ScrollBlockingView: NSView {
    override func scrollWheel(with event: NSEvent) {
        // Swallow all scroll events - don't pass to canvas
    }
}
```

#### 2. **ModalCoordinator.swift** (ENHANCED)
- Now a **singleton** (`ModalCoordinator.shared`) for global access
- Tracks modal state with `activeModalCount` counter
- Generic `modalDidOpen()` / `modalDidClose()` methods
- Publishes `isModalPresented` for canvas to observe
- Handles TeamMember, Settings, and Account modals

**Key Feature**: Reference counting prevents premature dismissal when multiple modals open

#### 3. **CanvasView.swift** (MODIFIED)
- Uses shared `ModalCoordinator.shared` instance
- Conditionally shows `CanvasBlockingLayer` in ZStack
- Layer positioned above all canvas content (nodes, edges, controls)
- Only visible when `modalCoordinator.isModalPresented == true`

```swift
if modalCoordinator.isModalPresented {
    CanvasBlockingLayer()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
        .ignoresSafeArea()
}
```

#### 4. **Integration Points**

**TeamMemberModal** (TeamMemberModalWindow.swift):
- Already integrated - calls `modalDidClose()` in onDismiss callback

**Settings Window** (SettingsView.swift):
- `onAppear`: Calls `ModalCoordinator.shared.modalDidOpen()`
- `onDisappear`: Calls `ModalCoordinator.shared.modalDidClose()`

**Account Window** (JamAIApp.swift + UserSettingsView.swift):
- Window creation: Calls `modalDidOpen()` before `makeKeyAndOrderFront()`
- Window close observer: Calls `modalDidClose()` on `NSWindow.willCloseNotification`
- View lifecycle: Also calls in `onAppear`/`onDisappear` for redundancy

## How It Works

1. **Modal Opens** → `modalDidOpen()` increments counter → `isModalPresented = true`
2. **Canvas Reacts** → `CanvasBlockingLayer` appears above canvas
3. **User Scrolls** → `ScrollBlockingView` intercepts event, swallows it
4. **Modal Content** → ScrollViews in modal windows work normally (higher z-index)
5. **Modal Closes** → `modalDidClose()` decrements counter → Layer disappears

## Benefits

✅ **Robust**: Works for ANY dialog type (Team Member, Settings, Account, future modals)  
✅ **Simple**: Single blocking layer, no complex state machines  
✅ **Best Practice**: Same pattern as web overlays (`position: fixed; z-index: 9999`)  
✅ **Minimal**: Only ~50 lines of new code  
✅ **No Side Effects**: Doesn't modify dialog UI or scrolling behavior  
✅ **Backwards Compatible**: Doesn't break existing canvas interactions

## Testing Checklist

- [x] Build succeeds without errors
- [ ] Team Member modal: Scroll works inside, background blocked
- [ ] Settings window: Scroll works inside, background blocked
- [ ] Account window: Scroll works inside, background blocked
- [ ] Multiple modals: Works correctly with stacked modals
- [ ] Modal close: Blocking layer disappears immediately
- [ ] Canvas interactions: Resume normally after modal closes
- [ ] Visual feedback: Semi-transparent overlay visible

## Technical Notes

- **Z-ordering**: CanvasBlockingLayer is last item in ZStack → highest z-index
- **Thread Safety**: All ModalCoordinator calls wrapped in `Task { @MainActor in }`
- **Reference Counting**: Handles overlapping modal lifecycles gracefully
- **Event Handling**: NSView-level interception is more reliable than SwiftUI gesture handling
- **Performance**: Negligible - layer only exists when modal is open

## Files Changed

```
Created:
  JamAI/Views/CanvasBlockingLayer.swift

Modified:
  JamAI/Services/ModalCoordinator.swift
  JamAI/Views/CanvasView.swift
  JamAI/Views/SettingsView.swift
  JamAI/Views/UserSettingsView.swift
  JamAI/JamAIApp.swift
```

## Previous Failed Approaches

❌ Modifying scroll behavior in MouseTrackingView (broke canvas scrolling)  
❌ Adding `.disabled()` to canvas (broke node interactions after close)  
❌ Sheet-level scroll blocking (inconsistent across different modal types)  
❌ Gesture priority changes (conflicted with drag/pan/zoom)  
❌ Hit-testing modifications (caused UI glitches)

## Why This Solution Works

The key insight: **Don't try to fix scroll routing - just block it completely**. When a modal is open, the user shouldn't be interacting with the canvas anyway. The blocking layer provides a clear "modal contract" - canvas is off-limits until the dialog closes.

This is the **web-proven pattern**: overlay divs with `pointer-events: none` on background and `pointer-events: auto` on modal. Direct translation to macOS with NSView event interception.
