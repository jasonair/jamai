# Outline View Feature

## Overview
Added a left floating pane that displays a hierarchical outline of all canvas nodes in an indented bullet format. Users can click on any bullet to navigate to the corresponding node on the canvas.

## Implementation Details

### 1. New Files Created
- **`JamAI/Views/OutlineView.swift`**: Main outline view component with hierarchical node tree

### 2. Modified Files

#### `JamAI/Services/CanvasViewModel.swift`
- Added `navigateToNode(_:viewportSize:)` function that:
  - Selects the target node
  - Sets zoom to 100% (1.0)
  - Centers the node in the viewport
  - Updates positions version to trigger connector refresh

#### `JamAI/Views/CanvasView.swift`
- Added `@State var showOutline: Bool = true` to control outline visibility
- Integrated `OutlineView` as a left-side overlay with proper positioning
- Added outline toggle button in toolbar with sidebar icon
- Toggle uses smooth animation (0.25s easeInOut)

### 3. Features

#### Hierarchical Structure
- Displays nodes as indented bullets mirroring their parent-child relationships
- Root nodes (no parent) appear at level 0
- Each child level is indented by 16pt
- Chevron icons (▶/▼) for expanding/collapsing nodes with children

#### Visual Feedback
- Selected node is highlighted with accent color background
- Hovered items show a subtle gray background
- Node colors are displayed as colored bullet points (6pt circles)
- Text color changes to white when selected for better contrast

#### Navigation
- Click any node bullet to:
  - Select the node
  - Zoom canvas to 100%
  - Center the node in viewport
  - Highlight the node
- **Smooth animated transitions** (0.5s easeInOut) when navigating
- Proper viewport size calculation for accurate centering

#### UI/UX
- Fixed width: 280pt
- Dynamic max height: viewport height - 120pt
- Scrollable content when nodes exceed available space
- Toggle button in toolbar (left section, before undo/redo)
- Smooth slide-in/out animation when toggling
- **Semi-transparent background** (88% opacity) for subtle see-through effect
- Subtle border stroke (0.5pt) for visual definition
- Enhanced shadow for depth (12pt radius)
- Adapts to light/dark mode

### 4. Node Display
- Shows node title if available, otherwise "Untitled"
- 13pt font size for readability
- Single line with truncation for long titles
- Color-coded bullets matching node colors from palette

### 5. Technical Details
- Recursive view structure for nested nodes
- Binding to shared `hoveredNodeId` state for hover tracking
- Closure-based navigation callback
- Sorted by creation date for consistent ordering
- Handles orphaned nodes (parent doesn't exist) as root nodes
- **Edge synchronization**: Edges are hidden during navigation animation to prevent visual glitches
- Navigation state flag (`isNavigating`) controls edge visibility during transitions
- Edges fade back in smoothly after navigation completes (0.55s total)

## Usage
1. Click the sidebar icon in the top-left toolbar to toggle outline visibility
2. Browse the hierarchical list of nodes
3. Click any node to navigate to it on the canvas (auto-zooms to 100% and centers)
4. Expand/collapse nodes with children using the chevron button
5. Hover over items to see subtle highlighting

## Future Enhancements
- Keyboard shortcut for toggling outline (e.g., Cmd+\)
- Drag-and-drop nodes within outline to change hierarchy
- Search/filter nodes in outline
- Context menu for outline items (delete, duplicate, etc.)
- Sync scroll position to selected node
- Customizable outline width
