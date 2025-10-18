# Drag Drift Prevention - Technical Guide

## The Problem

When implementing drag interactions for resizing or moving elements in a canvas application, a common issue is **drag drift** - where the mouse cursor gradually separates from the element being dragged.

### Common Causes of Drift

1. **Relative Translation Accumulation**
   - Using `value.translation` which is relative to gesture start
   - Floating-point rounding errors accumulate over frames
   - View layout updates can introduce frame-to-frame inconsistencies

2. **Local Coordinate Spaces**
   - Coordinates relative to view that's moving/resizing
   - View transforms affect coordinate calculations
   - Zoom/pan can amplify errors

3. **Frame-by-Frame Updates**
   - Updating position/size triggers view re-layout
   - Re-layout can shift coordinate system slightly
   - Small errors compound over time

## The Solution: Absolute Coordinate Tracking

### Best Practice Pattern

```swift
@State private var dragStartLocation: CGPoint = .zero
@State private var elementStartSize: CGSize = .zero

DragGesture(minimumDistance: 0, coordinateSpace: .global)
    .onChanged { value in
        if !isDragging {
            // Store initial state ONCE
            dragStartLocation = value.location
            elementStartSize = currentSize
            isDragging = true
        }
        
        // Calculate delta from FIXED start point
        let deltaX = value.location.x - dragStartLocation.x
        let deltaY = value.location.y - dragStartLocation.y
        
        // Apply delta to initial size/position
        newSize.width = elementStartSize.width + deltaX
        newSize.height = elementStartSize.height + deltaY
    }
```

### Key Principles

1. **Use Global Coordinate Space**
   ```swift
   coordinateSpace: .global
   ```
   - Immune to view transforms
   - Consistent across entire screen
   - Not affected by zoom/pan

2. **Store Initial State Once**
   ```swift
   dragStartLocation = value.location  // Absolute position
   elementStartSize = currentSize       // Starting size
   ```
   - Capture at drag start only
   - Never update during drag
   - Provides fixed reference point

3. **Calculate Delta from Fixed Point**
   ```swift
   let delta = currentLocation - startLocation
   ```
   - Always relative to same start point
   - No accumulation errors
   - Mathematically precise

4. **Apply Delta to Initial State**
   ```swift
   newSize = startSize + delta
   ```
   - Each frame independently calculated
   - No frame-to-frame dependencies
   - Eliminates drift completely

## Implementation Comparison

### ❌ Drift-Prone Implementation
```swift
DragGesture(minimumDistance: 0)
    .onChanged { value in
        // Uses local coordinate space
        // Translation is relative and can accumulate errors
        height = startHeight + value.translation.height
        width = startWidth + value.translation.width
    }
```

**Problems**:
- Local coordinate space affected by view transforms
- Translation can have accumulated errors
- Each resize triggers layout which shifts coordinates

### ✅ Drift-Free Implementation
```swift
DragGesture(minimumDistance: 0, coordinateSpace: .global)
    .onChanged { value in
        if !isResizing {
            dragStartLocation = value.location  // Store once
            resizeStartHeight = node.height
            resizeStartWidth = node.width
        }
        
        // Calculate from fixed point
        let deltaY = value.location.y - dragStartLocation.y
        let deltaX = value.location.x - dragStartLocation.x
        
        // Apply to initial state
        newHeight = resizeStartHeight + deltaY
        newWidth = resizeStartWidth + deltaX
    }
```

**Benefits**:
- Global coordinates never affected by view changes
- Delta calculated fresh each frame from same start point
- No accumulation of errors
- Mouse stays perfectly aligned with element

## Canvas-Specific Considerations

### Zoom and Pan

When working with a zoomed/panned canvas:

```swift
// Convert screen delta to world delta
let worldDelta = CGSize(
    width: screenDelta.width / zoom,
    height: screenDelta.height / zoom
)

// Apply to world-space position
newPosition = startPosition + worldDelta
```

### Node Dragging on Canvas

JamAI's node dragging implementation (already drift-free):

```swift
private func handleNodeDrag(_ nodeId: UUID, value: DragGesture.Value) {
    if draggedNodeId == nil {
        // Store initial world position
        dragStartPosition = CGPoint(x: node.x, y: node.y)
    }
    
    // Calculate world-space delta
    let worldDelta = CGSize(
        width: value.translation.width / viewModel.zoom,
        height: value.translation.height / viewModel.zoom
    )
    
    // New position from fixed start + delta
    let newPosition = CGPoint(
        x: dragStartPosition.x + worldDelta.width,
        y: dragStartPosition.y + worldDelta.height
    )
    
    viewModel.moveNode(nodeId, to: newPosition)
}
```

## Testing for Drift

### Visual Test
1. Start dragging at a specific point
2. Move mouse in various directions
3. Return mouse to original point
4. Element should return to original size/position
5. Mouse should be aligned with grab point

### Stress Test
1. Rapid back-and-forth movements
2. Large zoom levels (200%+)
3. While canvas is panned far from origin
4. During smooth scrolling
5. With accessibility zoom enabled

## Performance Notes

Absolute coordinate tracking is actually **more performant** than relative:
- No accumulation calculations needed
- Each frame is independent (no state dependencies)
- Simpler arithmetic (subtraction only)
- No floating-point error correction needed

## Conclusion

**Always use absolute coordinate tracking for drag interactions:**
- ✅ Use `.coordinateSpace(.global)`
- ✅ Store initial position/size once at drag start
- ✅ Calculate delta from fixed start point each frame
- ✅ Apply delta to initial state (not previous frame)
- ❌ Never use relative coordinates that accumulate
- ❌ Never update reference point during drag

This pattern is proven in production canvas applications and eliminates drift completely.
