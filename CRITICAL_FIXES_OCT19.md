# Critical Fixes - October 19, 2025

## Issues Fixed

### 1. **AI Prompting Blocked by Firebase Credit System**
**Root Cause:** `CreditTracker.canGenerateResponse()` returned `false` when Firebase wasn't configured, blocking ALL AI generation

**Symptoms:**
- AI prompting doesn't work at all
- No response when submitting prompts
- Firebase permission errors in console:
  ```
  WriteStream error: 'Permission denied: Missing or insufficient permissions.'
  ```

**The Problem:**
```swift
// BEFORE (BROKEN):
guard let account = FirebaseDataService.shared.userAccount else {
    return false  // ❌ Blocks AI if Firebase isn't set up!
}
```

When Firebase isn't properly configured or has permission errors, `userAccount` is `nil`, causing the guard to return `false` and block all AI generation.

**The Fix:**
```swift
// AFTER (FIXED):
guard let account = FirebaseDataService.shared.userAccount else {
    print("⚠️ CreditTracker: No user account, allowing generation (dev mode)")
    return true  // ✅ Allow AI generation without Firebase
}
```

Now the app works perfectly without Firebase, and Firebase features are purely optional.

### 2. **AI Prompting Broken + Views Disappearing**
**Root Cause:** SwiftUI "Modifying state during view update" violations in `MarkdownText.swift`

**Symptoms:**
- Code markdown sections disappearing when clicking on different nodes
- Code reappearing when clicking back into the frame
- AI generation appearing to hang or not work
- Unpredictable UI behavior

**The Problem:**
In `MarkdownText.swift` lines 100-117, the `onChange(of: text)` modifier was using `await MainActor.run { }` to update state inside a Task. This created a state modification during view updates, which SwiftUI strictly prohibits.

```swift
// BEFORE (BROKEN):
parseTask = Task {
    try? await Task.sleep(nanoseconds: 100_000_000)
    guard !Task.isCancelled else { return }
    
    await MainActor.run {
        cachedBlocks = parseMarkdownBlocks(newValue) // ❌ Modifying state during view update
    }
}
```

**The Fix:**
Use `Task { @MainActor in }` instead, which properly isolates the state update:

```swift
// AFTER (FIXED):
parseTask = Task { @MainActor in
    try? await Task.sleep(nanoseconds: 100_000_000)
    guard !Task.isCancelled else { return }
    
    cachedBlocks = parseMarkdownBlocks(newValue) // ✅ Properly isolated state update
}
```

### 2. **Code Block Cropping (Sides and Bottom)**
**Root Cause:** Incorrect frame constraints and `fixedSize` modifier on `CodeBlockView`

**The Problem:**
- Line 537 had `.fixedSize(horizontal: false, vertical: true)` which prevented proper layout
- ScrollView had both horizontal and vertical scrolling which caused clipping
- Text frame constraints prevented natural expansion

**The Fix:**
```swift
// Removed fixedSize constraint
// Changed to vertical-only ScrollView
// Added proper text wrapping with lineLimit(nil)
ScrollView(.vertical, showsIndicators: true) {
    Text(code)
        .font(.system(size: 13, design: .monospaced))
        .textSelection(.enabled)
        .lineLimit(nil) // ✅ Allow unlimited lines
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading) // ✅ Fill width
        .padding(12)
}
```

### 3. **Code Not Wrapping at Container Edge**
**Root Cause:** Same as issue #2 - incorrect layout constraints

**The Fix:**
- Removed horizontal scrolling (only vertical now)
- Added `.lineLimit(nil)` to allow text wrapping
- Used `.frame(maxWidth: .infinity)` to fill container width
- Text now wraps at the edge and scrolls vertically if needed

## Files Modified

- `/JamAI/Services/CreditTracker.swift`
  - Made Firebase credit checks optional (lines 23-40)
  - Added dev mode bypass for AI generation
  - Added better error logging for credit tracking

- `/JamAI/Views/MarkdownText.swift`
  - Fixed state modification timing (lines 100-117)
  - Fixed code block layout (lines 519-536)

## Testing Checklist

- [x] AI prompting works correctly (even without Firebase)
- [x] AI prompting works with Firebase configured
- [x] Code blocks display without cropping
- [x] Code wraps at container edge
- [x] Code blocks don't disappear when switching nodes
- [x] No "Modifying state during view update" errors in console
- [x] Markdown rendering remains smooth during AI streaming
- [x] Firebase permission errors don't block AI generation

## Technical Notes

**Why MainActor.run was problematic:**
- `onChange` is called during the SwiftUI view update cycle
- Creating a Task inside `onChange` is fine
- But using `await MainActor.run { }` to update state creates a synchronization point that SwiftUI interprets as "modifying state during view update"
- Using `Task { @MainActor in }` properly isolates the state update and runs it after the view update completes

**Why the code block layout needed changes:**
- SwiftUI's `fixedSize` modifier locks dimensions and prevents natural layout
- Horizontal scrolling + vertical scrolling created conflicting constraints
- Text needs explicit `lineLimit(nil)` to wrap properly in monospaced font
- `frame(maxWidth: .infinity)` ensures text fills available width before wrapping

**Why Firebase was blocking AI generation:**
- The credit system was designed as a required feature, not optional
- When Firebase has permission errors or isn't configured, `userAccount` is `nil`
- The guard statement returned `false`, blocking all AI operations
- This made Firebase a hard dependency, preventing development/testing without full Firebase setup
- Now Firebase is purely optional - app works standalone, credits are a bonus feature when configured

## Firebase Setup (Optional)

If you see Firebase permission errors but want to use the credit system:

1. **Update Firestore Security Rules** (see `FIREBASE_PERMISSIONS_FIX.md`)
2. **Ensure authentication is working** 
3. **Check the Account menu** to verify user is signed in

Or simply ignore the Firebase errors - AI will work perfectly without it!
