# Modal Scrolling and Dismiss Fix

## Issues Discovered

After implementing canvas interaction blocking, two critical issues emerged:

### Issue 1: ScrollViews Inside Modal Not Working ❌
**Symptom**: Category filters (horizontal scroll) and role list (vertical scroll) were not scrollable

**Root Cause**: 
The `ModalOverlay` background had aggressive gesture handlers:
```swift
.gesture(
    DragGesture(minimumDistance: 0)  // ⚠️ Captures ALL drags
        .onChanged { _ in ... }
)
```

This `DragGesture(minimumDistance: 0)` was capturing **every single drag event** in the entire overlay, including scroll gestures inside the modal's ScrollViews. Since it had `minimumDistance: 0`, even tiny movements (like the start of a scroll) were being captured and consumed.

### Issue 2: Closing Modal Hides Entire Window ❌
**Symptom**: When clicking Close (X), Cancel, or Save buttons, the entire application window would disappear

**Root Cause**:
The modal was using SwiftUI's `@Environment(\.dismiss)`:
```swift
@Environment(\.dismiss) var dismiss
```

This environment variable is designed for NavigationStack and `.sheet()` presentations. Since we're using a custom overlay system (not NavigationStack or .sheet), calling `dismiss()` was dismissing the wrong thing - likely the entire window or a parent view.

## Solutions

### Fix 1: Remove Blocking Gestures from ModalOverlay

**File**: `ModalOverlay.swift`

**Before**:
```swift
Color.black.opacity(0.3)
    .gesture(DragGesture(minimumDistance: 0)...)  // ❌ Blocks scrolling
    .highPriorityGesture(MagnificationGesture()...) // ❌ Blocks scrolling
```

**After**:
```swift
Color.black.opacity(0.3)
    .contentShape(Rectangle())
    .onTapGesture { ... }  // ✅ Only block taps
// No drag gestures - canvas blocking handled in CanvasView
```

**Why This Works**:
- The visual overlay still blocks clicks (via `onTapGesture`)
- Canvas interaction blocking is already handled comprehensively in `CanvasView` (scroll, drag, zoom, etc.)
- ScrollViews inside the modal can now process their own drag gestures normally
- No interference between overlay gestures and modal content gestures

### Fix 2: Replace @Environment(\.dismiss) with onDismiss Callback

**File**: `TeamMemberModal.swift`

**Before**:
```swift
struct TeamMemberModal: View {
    @Environment(\.dismiss) var dismiss  // ❌ Wrong dismissal mechanism
    
    let onSave: (TeamMember) -> Void
    let onRemove: (() -> Void)?
    
    // Later...
    Button(action: { dismiss() }) { ... }  // ❌ Dismisses wrong thing
}
```

**After**:
```swift
struct TeamMemberModal: View {
    let onSave: (TeamMember) -> Void
    let onRemove: (() -> Void)?
    let onDismiss: () -> Void  // ✅ Explicit callback
    
    // Later...
    Button(action: { onDismiss() }) { ... }  // ✅ Calls coordinator
}
```

**Changes Made**:
1. Removed `@Environment(\.dismiss) var dismiss`
2. Added `let onDismiss: () -> Void` parameter
3. Replaced all 4 `dismiss()` calls with `onDismiss()`:
   - Close (X) button
   - Cancel button
   - Remove button
   - Save button (in `saveTeamMember()`)

**File**: `CanvasView.swift`

Added `onDismiss` callback when creating modal:
```swift
TeamMemberModal(
    existingMember: config.existingMember,
    onSave: { ... },
    onRemove: { ... },
    onDismiss: {  // ✅ NEW
        print("[CanvasView] Modal dismissed via close/cancel button")
        modalCoordinator.dismissTeamMemberModal()
    }
)
```

## How It Works Now

### Modal Dismissal Flow
```
User clicks Close/Cancel/Save
    ↓
TeamMemberModal.onDismiss()
    ↓
CanvasView callback
    ↓
modalCoordinator.dismissTeamMemberModal()
    ↓
modalCoordinator.teamMemberModal = nil
    ↓
CanvasView body re-renders
    ↓
ModalOverlay conditional removes modal
```

### Interaction Layers
```
┌─────────────────────────────────────┐
│     Modal Content (Top)             │
│  ✅ ScrollViews work normally       │
│  ✅ Buttons work normally           │
│  ✅ All gestures processed here     │
├─────────────────────────────────────┤
│     ModalOverlay Background         │
│  ✅ Blocks clicks (onTapGesture)    │
│  ❌ NO drag gestures                │
├─────────────────────────────────────┤
│     Canvas (Bottom)                 │
│  ❌ All interactions blocked via    │
│     modalCoordinator checks         │
└─────────────────────────────────────┘
```

## Testing Results

### ✅ Modal ScrollViews (FIXED)
- Category filters scroll horizontally
- Role list scrolls vertically
- No interference from overlay gestures

### ✅ Modal Dismissal (FIXED)
- Close (X) button closes modal only
- Cancel button closes modal only
- Save button saves and closes modal only
- Window stays visible after dismissal

### ✅ Canvas Blocking (MAINTAINED)
- Canvas scroll still blocked when modal open
- Canvas drag still blocked when modal open
- Canvas zoom still blocked when modal open
- All blocking logs still appear

## Key Lessons

1. **Gesture Specificity Matters**: `DragGesture(minimumDistance: 0)` is extremely greedy and will capture everything
2. **Environment Variables Have Context**: `@Environment(\.dismiss)` only works in specific SwiftUI contexts (NavigationStack, .sheet, etc.)
3. **Explicit Callbacks > Magic**: Direct callbacks provide clearer control flow than environment-based dismissal
4. **Layered Blocking Strategy**: Visual overlay + interaction checks + explicit callbacks = comprehensive blocking
5. **Test Each Interaction**: Scrolling inside modal, dismissal, and canvas blocking are all separate concerns

## Files Modified

1. `ModalOverlay.swift` - Removed blocking drag gestures
2. `TeamMemberModal.swift` - Replaced @Environment(\.dismiss) with onDismiss callback
3. `CanvasView.swift` - Added onDismiss callback to modal instantiation

## Build Status

✅ Build succeeded with no errors or warnings
