# Undo/Redo System Investigation & Fix

## Current Implementation

### Architecture
The app uses a **custom undo/redo system** (`CanvasUndoManager`) instead of macOS's built-in `NSUndoManager`. This is properly implemented with:

1. **Action Recording**: All canvas operations record undo actions
2. **Undo Stack**: Maintains history of actions  
3. **Redo Stack**: Cleared when new action recorded
4. **Coalescing**: Combines multiple move operations

### What's Being Recorded
✅ Create Node  
✅ Delete Node  
✅ Update Node (including text edits)  
✅ Move Node  
✅ Create Edge  
✅ Delete Edge  

## Debug Logging Added

### To help diagnose the issue, I added logging:

**When action is recorded:**
```
📝 Recording action: <action>
📊 Undo stack size: X, canUndo: true/false
```

**When undo is called:**
```
🔄 Undo called - canUndo: true/false
✅ Undoing action: <action>
OR
⚠️ No action to undo
```

**When redo is called:**
```
🔄 Redo called - canRedo: true/false
✅ Redoing action: <action>
OR
⚠️ No action to redo
```

## Testing Instructions

### 1. Test Action Recording
**Run the app and watch the console:**

- Create a node → Should see: `📝 Recording action: createNode(...)`
- Delete a node → Should see: `📝 Recording action: deleteNode(...)`
- Edit text → Should see: `📝 Recording action: updateNode(...)`

**Expected:** Every action logs to console with stack size

### 2. Test Undo via Menu
- Do an action (create node)
- Click Edit > Undo (or press Cmd+Z)
- Check console for: `🔄 Undo called`

**Expected:** Should see undo called and action undone

### 3. Test Undo via Keyboard
- Do an action (create node)
- Press **Cmd+Z**
- Check console

**Two possible outcomes:**
1. ✅ Sees `🔄 Undo called` → Shortcut works!
2. ❌ No console output → Shortcut not reaching the handler

## Potential Issues & Solutions

### Issue 1: Shortcuts Not Reaching Handler
**Symptom:** Menu item works but Cmd+Z doesn't  
**Cause:** SwiftUI view consuming keyboard events  
**Solution:** Implemented `focusedValue` to connect menu commands to canvas

### Issue 2: canUndo is false
**Symptom:** Undo menu disabled  
**Cause:** Actions not being recorded  
**Solution:** Check that `undoManager.record()` is called (debug log shows this)

### Issue 3: Menu Item Disabled
**Symptom:** Edit > Undo is grayed out  
**Cause:** `appState.viewModel` might be nil or `canUndo` is false  
**Solution:** Verify viewModel exists and stack has actions

## Code Changes Made

### 1. JamAIApp.swift
```swift
CommandGroup(replacing: .undoRedo) {
    Button("Undo") {
        appState.viewModel?.undo()
    }
    .keyboardShortcut("z", modifiers: .command)
    .disabled(appState.viewModel == nil || !(appState.viewModel?.undoManager.canUndo ?? false))
    
    Button("Redo") {
        appState.viewModel?.redo()
    }
    .keyboardShortcut("z", modifiers: [.command, .shift])
    .disabled(appState.viewModel == nil || !(appState.viewModel?.undoManager.canRedo ?? false))
}
```

### 2. CanvasView.swift
- Added `FocusedValueKey` for canvas view model
- Applied `.focusedValue(\.canvasViewModel, viewModel)` to canvas
- This connects menu commands to the active canvas

### 3. CanvasViewModel.swift & UndoManager.swift
- Added comprehensive debug logging
- Tracks every action recorded, undo called, redo called

## Next Steps for User

### Run the app and test:

1. **Open project**
2. **Create a node** → Check console for recording
3. **Press Cmd+Z** → Check console for undo call
4. **Report results:**
   - Did you see `📝 Recording action` messages?
   - Did you see `🔄 Undo called` when pressing Cmd+Z?
   - Did the undo actually work?

### Expected Console Output for Full Test:

```
📝 Recording action: createNode(...)
📊 Undo stack size: 1, canUndo: true
🔄 Undo called - canUndo: true
✅ Undoing action: createNode(...)
```

## macOS Undo/Redo Best Practices

### Standard Approaches:

1. **NSUndoManager** (Apple's standard)
   - Built into AppKit/UIKit
   - Automatic integration with menus
   - Responder chain-based

2. **Custom System** (What this app uses)
   - More control over what's undoable
   - Can implement complex coalescing
   - Must manually wire shortcuts

### Why Custom System Here:
- Complex canvas operations
- Need fine-grained control
- Want to coalesce move operations
- Custom action types

### The Challenge:
SwiftUI's menu keyboard shortcuts sometimes don't propagate properly to complex views. The `focusedValue` approach is the modern SwiftUI solution.

## If Shortcuts Still Don't Work

### Alternative Approach - NSResponder Chain

If the current approach fails, we can:

1. Use native `NSUndoManager`
2. Bridge our custom actions to it
3. Get automatic shortcut handling

This would require refactoring but guarantees macOS-standard behavior.

## Build Status
✅ **BUILD SUCCEEDED** with debug logging
