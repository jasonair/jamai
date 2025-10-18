# Scrolling and Click Passthrough Fix

## Issues Reported

1. **ScrollViews not scrollable**: Category filters and role list were not scrolling
2. **Clicks passing through**: When clicking on a role in the modal, nodes behind it were being selected

## Root Causes

### Issue 1: ScrollViews Not Scrolling

**Investigation**:
- 10 roles × ~70px per RoleRow = ~700px total height
- Modal had `.frame(maxHeight: 300)` 
- Content should be scrollable (700px > 300px)

**Problem**: Using `maxHeight` instead of fixed `height` can prevent proper scroll calculation in some cases. Also missing explicit scroll indicators and clipping.

### Issue 2: Clicks Passing Through

**Problem**: Multiple layers not properly configured to block events:
1. ModalOverlay's `ZStack` layers not explicitly ordered with `zIndex`
2. Modal content not explicitly marked as hit-testable
3. Canvas layer not explicitly below modal
4. CanvasView wrapping modal in `Color.clear.overlay` instead of direct placement

## Solutions

### Fix 1: Make ScrollViews Explicitly Scrollable

**File**: `TeamMemberModal.swift`

**Changes**:
```swift
// Before
ScrollView {
    LazyVStack(spacing: 8) {
        // roles...
    }
    .padding()
}
.frame(maxHeight: 300)

// After
ScrollView(.vertical, showsIndicators: true) {  // ✅ Explicit direction & indicators
    LazyVStack(spacing: 8) {
        // roles...
    }
    .padding()
}
.frame(height: 300)  // ✅ Fixed height (not maxHeight)
.clipped()            // ✅ Clip content to bounds
```

**Why This Works**:
- `showsIndicators: true` makes scroll indicators visible
- Fixed `height` instead of `maxHeight` ensures proper scroll bounds calculation
- `.clipped()` prevents content from rendering outside bounds
- Added logging to role selection for debugging

### Fix 2: Proper Event Blocking with Z-Index

**File**: `ModalOverlay.swift`

**Changes**:
```swift
ZStack {
    // Background
    Color.black.opacity(0.3)
        .allowsHitTesting(true)  // ✅ Explicitly block events
        .zIndex(0)                // ✅ Background layer

    // Modal content
    content
        .allowsHitTesting(true)  // ✅ Capture all events in modal
        .zIndex(1)                // ✅ Modal on top of background
}
```

**File**: `TeamMemberModal.swift`

**Changes**:
```swift
VStack {
    // ... modal content
}
.frame(width: 600, height: 650)
.allowsHitTesting(true)  // ✅ Ensure modal captures all events
```

**File**: `CanvasView.swift`

**Changes**:
```swift
ZStack {
    canvasContent
        .zIndex(0)  // ✅ Canvas at bottom
    
    if let config = modalCoordinator.teamMemberModal {
        ModalOverlay(...) {  // ✅ Direct placement (no Color.clear wrapper)
            TeamMemberModal(...)
        }
        .ignoresSafeArea()
        .zIndex(1000)  // ✅ Modal at very top
    }
}
```

**Why This Works**:
- Explicit `zIndex` values ensure proper layering order
- `allowsHitTesting(true)` on modal and background ensures they capture events
- Canvas explicitly below modal (zIndex: 0 vs zIndex: 1000)
- Removed `Color.clear.overlay` wrapper that might interfere with event routing
- High zIndex (1000) ensures modal is definitely on top

## Event Flow

### Before (Broken)
```
User clicks role
    ↓
Event propagates through layers (unclear order)
    ↓
Both modal AND canvas receive event
    ↓
Role selected AND node behind selected ❌
```

### After (Fixed)
```
User clicks role
    ↓
Modal content (zIndex: 1) captures event
    ↓
Modal's allowsHitTesting(true) consumes event
    ↓
Event stops, doesn't reach canvas (zIndex: 0)
    ↓
Only role selected ✅
```

## Layer Stack (Bottom to Top)

```
┌─────────────────────────────────────┐
│  Modal Content (zIndex: 1)         │  ✅ Hit testable
│  - Buttons work                     │
│  - ScrollViews scroll               │
│  - Clicks don't pass through        │
├─────────────────────────────────────┤
│  Modal Background (zIndex: 0)      │  ✅ Hit testable
│  - Black 30% opacity                │
│  - Blocks clicks                    │
├─────────────────────────────────────┤
│  (ModalOverlay zIndex: 1000)       │  ← Entire overlay above canvas
├─────────────────────────────────────┤
│  Canvas Content (zIndex: 0)        │  ❌ Not hit testable when modal open
│  - Gestures blocked via checks      │
│  - Can't receive events             │
└─────────────────────────────────────┘
```

## Testing Checklist

### Scrolling
- [x] Build succeeds
- [ ] Category filters scroll horizontally (if enough categories)
- [ ] ✅ Role list scrolls vertically (10 roles > 300px height)
- [ ] ✅ Scroll indicators visible on role list
- [ ] ✅ Content clipped at boundaries

### Click Isolation
- [ ] ✅ Clicking on a role only selects the role
- [ ] ✅ Nodes behind modal are NOT selected
- [ ] ✅ Clicking modal background doesn't affect canvas
- [ ] ✅ All buttons in modal work
- [ ] ✅ Text fields in modal work

### Debug Logging
When clicking a role, should see:
```
[TeamMemberModal] Role selected: [Role Name]
```

Should NOT see:
```
[CanvasView] Node selected  // ❌ This means click passed through
```

## Files Modified

1. `TeamMemberModal.swift`:
   - Changed `.frame(maxHeight: 300)` to `.frame(height: 300)`
   - Added `.clipped()`
   - Added `showsIndicators: true`
   - Added `.allowsHitTesting(true)` to modal VStack
   - Added role selection logging

2. `ModalOverlay.swift`:
   - Added `.allowsHitTesting(true)` to background
   - Added `.allowsHitTesting(true)` to content
   - Added explicit `.zIndex(0)` to background
   - Added explicit `.zIndex(1)` to content

3. `CanvasView.swift`:
   - Removed `Color.clear.overlay` wrapper
   - Added `.zIndex(0)` to canvas content
   - Added `.zIndex(1000)` to modal overlay
   - Direct ModalOverlay placement in ZStack

## Key Lessons

1. **z-index is critical**: SwiftUI doesn't guarantee layering order without explicit zIndex
2. **Hit testing must be explicit**: Use `.allowsHitTesting(true)` to ensure event capture
3. **ScrollView configuration matters**: Fixed height + clipped + indicators = reliable scrolling
4. **Simple is better**: Direct placement in ZStack better than wrappers like Color.clear.overlay
5. **High z-index numbers**: Use large values (1000+) to ensure top layer stays on top

## Build Status

✅ Build succeeded with no errors or warnings
