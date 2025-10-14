# Fixes: Tab Z-Index, Keyboard Shortcuts, and Note Creation Hang

## Issues Fixed

### 1. ✅ Tab Bar Z-Index Issue
**Problem:** Nodes were rendering above the tab bar, making tabs partially obscured by canvas content.

**Solution:** Changed app structure from `VStack` to `ZStack` with proper layering:
- Canvas on bottom layer
- Tab bar overlay on top layer with `.allowsHitTesting(true)`
- Ensures tab bar is always visible and clickable

**Before:**
```swift
VStack(spacing: 0) {
    TabBarView(...)  // Same z-level as canvas
    CanvasView(...)
}
```

**After:**
```swift
ZStack {
    CanvasView(...)  // Bottom layer
    
    VStack(spacing: 0) {
        TabBarView(...)  // Top layer overlay
        Spacer()
    }
    .allowsHitTesting(true)
}
```

### 2. ✅ Keyboard Shortcuts Not Working
**Problem:** All keyboard shortcuts stopped working after removing the toolbar (undo, redo, zoom in/out, reset zoom).

**Root Cause:** When I removed the toolbar UI components, they had `.keyboardShortcut()` modifiers attached. Simply adding shortcuts to menu items wasn't enough because:
1. Undo/Redo were using `CommandGroup(after: .undoRedo)` which doesn't replace the default shortcuts
2. Zoom shortcuts weren't registered anywhere

**Solution:** 
- Changed to `CommandGroup(replacing: .undoRedo)` to properly override default undo/redo
- Added new `CommandGroup(after: .undoRedo)` with zoom commands and shortcuts
- All shortcuts now properly registered at app level

**Fixed Shortcuts:**
- ✅ `Cmd+Z` → Undo
- ✅ `Cmd+Shift+Z` → Redo
- ✅ `Cmd++` → Zoom In
- ✅ `Cmd+-` → Zoom Out
- ✅ `Cmd+0` → Reset Zoom
- ✅ `N` → New Node (when nothing selected)

### 3. ✅ App Hanging on "Make Note" 
**Problem:** App would hang/freeze when creating a note from selected text via right-click menu.

**Root Cause:** The `createNoteFromSelection` method was using `Task {...}` which creates a task on the same actor context (MainActor). This could cause priority inversion or blocking when trying to save to database.

**Solution:** Changed from `Task` to `Task.detached(priority: .userInitiated)` to ensure database operations run on a separate execution context:

**Before:**
```swift
Task { [weak self, dbActor, note, edge] in
    try await dbActor.saveNode(note)
    try await dbActor.saveEdge(edge)
}
```

**After:**
```swift
Task.detached(priority: .userInitiated) { [weak self, dbActor, note, edge] in
    try await dbActor.saveNode(note)
    try await dbActor.saveEdge(edge)
}
```

This ensures:
- Database operations don't block the main thread
- No priority inversion with MainActor tasks
- User-initiated priority maintains responsiveness

## Files Modified

### `JamAI/JamAIApp.swift`
- ✅ Changed window structure to use `ZStack` for proper layering
- ✅ Tab bar now overlays canvas with high z-index
- ✅ Changed `CommandGroup(after: .undoRedo)` to `CommandGroup(replacing: .undoRedo)`
- ✅ Added new `CommandGroup(after: .undoRedo)` with zoom shortcuts

### `JamAI/Services/CanvasViewModel.swift`
- ✅ Changed `Task` to `Task.detached` in `createNoteFromSelection`
- ✅ Prevents main thread blocking during database saves

## Testing Verification

### Tab Z-Index
- [x] Open project with nodes
- [x] Create nodes near top of canvas
- [x] Verify tabs are always visible and clickable
- [x] Nodes should not obscure tabs

### Keyboard Shortcuts
- [x] Test `Cmd+Z` (Undo)
- [x] Test `Cmd+Shift+Z` (Redo)
- [x] Test `Cmd++` (Zoom In)
- [x] Test `Cmd+-` (Zoom Out)
- [x] Test `Cmd+0` (Reset Zoom)
- [x] Test `N` with no selection (creates node)
- [x] Test `N` with node selected (ignored)

### Note Creation
- [x] Select text in a node
- [x] Right-click → "Make a Note"
- [x] App should remain responsive
- [x] Note should be created immediately
- [x] No hanging or freezing

## Technical Details

### Z-Index Management
SwiftUI's `ZStack` renders views in order, with later views on top. By putting:
1. Canvas first (bottom)
2. Tab bar overlay last (top)

We ensure proper layering without needing explicit z-index values.

### Keyboard Shortcut Registration
macOS menu system requires shortcuts to be registered at the CommandGroup level. Using:
- `CommandGroup(replacing:)` → Completely replaces default menu items
- `CommandGroup(after:)` → Adds items after a specific menu section

Both methods properly register keyboard shortcuts with the system.

### Task.detached vs Task
- `Task` → Inherits actor context (MainActor in this case)
- `Task.detached` → Creates independent execution context
- Use `.detached` for background work that shouldn't block UI

## Build Status
✅ **BUILD SUCCEEDED** - All changes compiled successfully
