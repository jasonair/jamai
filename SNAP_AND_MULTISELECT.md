# Snap-to-Align and Multi-Select Features

This document describes the Figma/Illustrator-style snap-to-align and shift-click multi-select features implemented for JamAI.

## Snap-to-Align Feature

### Overview
When dragging nodes on the canvas, they automatically snap to align with nearby nodes. Pink/red dashed guide lines appear to show when alignment is detected.

### How It Works
- **Edge Alignment**: Nodes snap when their edges (left, right, top, bottom) align with other nodes' edges
- **Center Alignment**: Nodes also snap when their centers align with other nodes' centers
- **Threshold**: Default snap threshold is 10 canvas units (configurable in `Config.swift`)
- **Visual Feedback**: Dashed guide lines appear showing the alignment

### Disabling Snap Temporarily
- **Hold Control** while dragging to temporarily disable snapping and move freely
- Useful for fine positioning when you don't want snap behavior

### Configuration
In `Config.swift`:
```swift
static let snapEnabled: Bool = true  // Enable/disable snap globally
static let snapThreshold: CGFloat = 10.0  // Pixel distance to trigger snap
```

### Files
- `JamAI/Services/SnapGuideService.swift` - Core snap calculation logic
- `JamAI/Views/SnapGuideLayer.swift` - Visual guide line rendering

---

## Multi-Select Feature

### Overview
Hold **Shift** and click on multiple nodes to select them as a group. Once selected, drag any node in the group to move all of them together.

### How to Use
1. **Shift+Click** on nodes to add them to the selection
2. **Shift+Click** on an already-selected node to deselect it
3. **Drag** any multi-selected node to move all selected nodes together
4. **Click on empty canvas** to clear all selections
5. **Regular click** on a node (without Shift) clears multi-selection and selects just that node

### Visual Feedback
- Multi-selected nodes show a blue accent border around them
- The border appears slightly outside the node (4px padding)

### Behavior Notes
- Shift-clicking does NOT expand/open nodes - it only toggles selection
- Snap-to-align works with multi-select (primary dragged node is used for snap calculations)
- All selected nodes move by the same delta, maintaining relative positions

### Files
- `JamAI/Views/ModifierKeyTracker.swift` - Tracks Shift/Control key states
- `JamAI/Services/CanvasViewModel.swift` - Multi-select state and methods
- `JamAI/Views/CanvasView.swift` - Drag handling and tap handling
- `JamAI/Views/NodeItemWrapper.swift` - Multi-select visual indicator

---

## State Management

### CanvasViewModel Properties
```swift
// Multi-select state
@Published var selectedNodeIds: Set<UUID> = []  // Multiple selected nodes
@Published var isShiftPressed: Bool = false     // Shift key state

// Snap-to-align state
@Published var snapGuides: [SnapGuide] = []     // Active guide lines
@Published var isSnapEnabled: Bool = true       // Can be toggled
@Published var isControlPressed: Bool = false   // Control key state
```

### Key Methods
```swift
func toggleNodeInSelection(_ nodeId: UUID)
func clearMultiSelection()
func moveNodes(_ nodeIds: Set<UUID>, delta: CGSize)
func clearSnapGuides()
```

---

## Algorithm Details

### Snap Calculation
The `SnapGuideService` calculates potential snap positions by comparing:
1. Left, center, and right X coordinates
2. Top, center, and bottom Y coordinates

For each axis, it finds the closest alignment within the threshold and applies the snap. Guide lines are generated to visualize the alignment.

### Multi-Drag Implementation
When dragging with multiple nodes selected:
1. Store initial positions of all selected nodes at drag start
2. Calculate the delta from the primary node's movement
3. Apply the same delta to all selected nodes
4. If snapping is enabled, snap the primary node first, then apply the snapped delta to others

---

## Testing Checklist

### Snap-to-Align
- [ ] Drag a node near another - see snap guides appear
- [ ] Verify snap to left/right edges
- [ ] Verify snap to top/bottom edges  
- [ ] Verify snap to center alignment
- [ ] Hold Control while dragging - no snapping
- [ ] Release Control - snapping resumes

### Multi-Select
- [ ] Shift+Click to select multiple nodes
- [ ] Shift+Click selected node to deselect
- [ ] Drag multi-selected nodes together
- [ ] Click empty canvas to clear selection
- [ ] Regular click clears multi-selection
- [ ] Shift+Click doesn't expand/open nodes
- [ ] Multi-select visual indicator (blue border) shows correctly
