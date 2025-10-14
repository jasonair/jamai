# Multi-Project Tabs Feature

## Overview

Added VS Code / Notion-style multi-project tabs to JamAI, allowing users to work with multiple projects simultaneously in a single window.

## Features

### ✅ Tab Bar
- Displays all open projects at the top of the window
- Shows project name with folder icon
- Active tab is highlighted with accent color
- Close button (×) appears on hover or for active tab
- Horizontal scrolling for many tabs

### ✅ Tab Management
- **Open in new tab**: All project opens create a new tab
- **Switch tabs**: Click any tab to switch to that project
- **Close tabs**: Click × button or use Cmd+W
- **Prevent duplicates**: Opening an already-open project switches to its tab
- **Auto-cleanup**: Saves project data when closing tabs

### ✅ Multiple Projects
- Work on multiple projects without switching windows
- Each tab maintains its own:
  - Canvas state
  - Undo/redo history
  - Project settings
  - Database connection

### ✅ Integration Points
- **Welcome Screen**: Opens projects in new tabs
- **File Menu**: "Open Recent" creates new tabs
- **Recent Projects List**: Click any item to open in new tab
- **New Project**: Creates and opens in new tab

## Architecture Changes

### New Files
- **`ProjectTab.swift`** - Model representing a project tab
- **`TabBarView.swift`** - UI component for tab bar

### Modified Files
- **`JamAIApp.swift`** - Refactored AppState for multi-tab support
- **`WelcomeView.swift`** - Updated to use new tab API

### AppState Refactoring

**Before (Single Project):**
```swift
@Published var viewModel: CanvasViewModel?
@Published var project: Project?
@Published var currentFileURL: URL?
```

**After (Multi-Project Tabs):**
```swift
@Published var tabs: [ProjectTab] = []
@Published var activeTabId: UUID?

// Computed properties for backward compatibility
var viewModel: CanvasViewModel? {
    activeTab?.viewModel
}
```

### Key Methods

```swift
// Tab management
func selectTab(_ id: UUID)
func closeTab(_ id: UUID)
func openProjectInNewTab(url: URL)

// Backward compatible
func openRecent(url: URL) // Opens in new tab
func createNewProject()   // Opens in new tab
func closeProject()       // Closes active tab
```

## User Experience

### Opening Projects
1. **From Welcome Screen**: Click "Open Project" → opens in first tab
2. **From Recent Projects**: Click any item → opens in new tab (or switches if already open)
3. **From File Menu**: File > Open Recent → opens in new tab
4. **Create New**: Creates and opens in new tab

### Working with Tabs
1. **Switch Projects**: Click any tab
2. **Close Tab**: Click × button
3. **Close via Menu**: Cmd+W closes active tab
4. **Last Tab**: Closing last tab returns to Welcome Screen

### Smart Behavior
- ✅ Opening an already-open project switches to its tab (doesn't duplicate)
- ✅ Each tab maintains independent state
- ✅ Security-scoped access managed per-tab
- ✅ Auto-save before closing tabs

## Industry Comparison

| Feature | VS Code | Notion | JamAI |
|---------|---------|--------|-------|
| Multiple projects in tabs | ✅ | ✅ | ✅ |
| Tab close button | ✅ | ✅ | ✅ |
| Prevent duplicates | ✅ | ✅ | ✅ |
| Independent state per tab | ✅ | ✅ | ✅ |
| Tab overflow scrolling | ✅ | ✅ | ✅ |

## Technical Details

### Security-Scoped Access
- Each tab's project file gets independent security-scoped access
- Access started when tab opens
- Access released when tab closes
- Tracked in `accessingResources` set

### Memory Management
- Projects remain in memory while tab is open
- Database connections maintained per-tab
- Clean shutdown on tab close with proper async/await

### Tab Identification
- Each tab has unique UUID
- URL used to prevent duplicates
- Active tab tracked via `activeTabId`

## Future Enhancements
- [ ] Drag-and-drop tab reordering
- [ ] Tab pinning
- [ ] Restore tabs on app relaunch
- [ ] Split view (side-by-side projects)
- [ ] Tab context menu (close others, close all, etc.)
- [ ] Cmd+1-9 to switch between first 9 tabs
