# Dialog Scroll Blocking Fix V2 - Window-Level Tracking

## Problem Discovery

After initial implementation, Team Member modal worked perfectly but Settings and Account windows caused nodes to stop scrolling after opening them a few times.

**Root Cause**: Settings and Account were using **view lifecycle tracking** (`onAppear`/`onDisappear`), which:
- Fires multiple times during window lifetime
- Can get stuck if view updates while window is open
- Increments `activeModalCount` without corresponding decrements
- Results in `isModalPresented` stuck at `true` → blocking layer never disappears

## Solution

Match the **Team Member modal pattern** which tracks at the **window level**, not view lifecycle level.

### Key Components

#### 1. ModalTrackingView (NEW)
```swift
private class WindowTrackingView: NSView {
    var onWindowAppear: (() -> Void)?
    var onWindowDisappear: (() -> Void)?
    private var hasTrackedAppear = false
    
    override func viewDidMoveToWindow() {
        // Called ONCE when view added to window hierarchy
        // Called ONCE when view removed from window hierarchy
    }
}
```

**Why this works**:
- `viewDidMoveToWindow()` fires exactly ONCE when window opens
- Fires exactly ONCE when window closes
- Not affected by view updates or SwiftUI re-renders
- Perfect 1:1 pairing of modalDidOpen/modalDidClose calls

#### 2. Integration Pattern

**Settings Window**:
```swift
var body: some View {
    ZStack {
        // Hidden tracking view (0x0 size, opacity 0)
        ModalTrackingView()
            .frame(width: 0, height: 0)
            .opacity(0)
        
        ScrollView {
            // Settings content...
        }
    }
}
```

**Account Window**:
- Same pattern applied
- Removed manual tracking from `showUserSettings()` function
- Now purely window-level tracking via ModalTrackingView

### How It Works

```
Window Opens
   ↓
ModalTrackingView added to window hierarchy
   ↓
viewDidMoveToWindow() called (window != nil)
   ↓
modalDidOpen() → activeModalCount++
   ↓
isModalPresented = true → CanvasBlockingLayer appears
   ↓
[User interacts with window - multiple view updates, no duplicate calls]
   ↓
Window Closes
   ↓
ModalTrackingView removed from window hierarchy
   ↓
viewDidMoveToWindow() called (window == nil)
   ↓
modalDidClose() → activeModalCount--
   ↓
isModalPresented = false → CanvasBlockingLayer disappears
```

## Comparison: Before vs After

### Before (BROKEN)
```swift
.onAppear {
    ModalCoordinator.shared.modalDidOpen()  // May fire multiple times
}
.onDisappear {
    ModalCoordinator.shared.modalDidClose() // May not fire or fire late
}
```

Problems:
- ❌ onAppear fires when view refreshes
- ❌ onDisappear doesn't fire if view is still mounted
- ❌ Counter gets out of sync
- ❌ Nodes stop scrolling permanently

### After (WORKING)
```swift
// Hidden in ZStack
ModalTrackingView()
    .frame(width: 0, height: 0)
    .opacity(0)
```

Benefits:
- ✅ Fires exactly once per window open/close
- ✅ Immune to SwiftUI re-renders
- ✅ Perfect counter synchronization
- ✅ Nodes resume scrolling after close

## Testing Results

| Modal Type      | Before | After  |
|----------------|--------|--------|
| Team Member    | ✅ Works | ✅ Works |
| Settings       | ❌ Breaks | ✅ Works |
| Account        | ❌ Breaks | ✅ Works |

**Test Procedure**:
1. Open and close each modal 5-10 times
2. Verify canvas blocking appears/disappears correctly
3. Verify nodes scroll normally after each close
4. Test rapid open/close sequences
5. Test with multiple modals open simultaneously

## Files Modified

```
Created:
  JamAI/Views/ModalTrackingView.swift

Modified:
  JamAI/Views/SettingsView.swift (added ModalTrackingView, removed onAppear/onDisappear tracking)
  JamAI/Views/UserSettingsView.swift (added ModalTrackingView, removed onAppear/onDisappear tracking)
  JamAI/JamAIApp.swift (removed manual tracking from showUserSettings)
```

## Technical Notes

**Why not use SwiftUI's task/onAppear?**
- These are tied to view lifecycle, not window lifecycle
- SwiftUI can recreate views without changing window state
- Window is the true modal boundary, not the view

**Why invisible 0x0 view?**
- Must be in view hierarchy to receive `viewDidMoveToWindow()` callback
- Size/opacity don't matter - only hierarchy position matters
- Zero performance cost

**Why NSView instead of NSWindow delegate?**
- Settings window uses system-provided window (not our NSPanel)
- Can't access window delegate without breaking macOS APIs
- NSView approach works universally for all window types

## Lessons Learned

1. **View lifecycle ≠ Window lifecycle** in SwiftUI/AppKit hybrid apps
2. **NSView.viewDidMoveToWindow()** is the reliable window tracking API
3. **Counter-based reference tracking** requires perfect increment/decrement pairing
4. **Always test modal open/close multiple times** to catch lifecycle bugs

## Prevention

When adding new modals in the future:
1. ✅ Use `ModalTrackingView()` hidden in ZStack
2. ❌ Don't use `onAppear`/`onDisappear` for modal tracking
3. ✅ Test open/close 10+ times to verify counter stays balanced
4. ✅ Check that nodes scroll after every modal close
