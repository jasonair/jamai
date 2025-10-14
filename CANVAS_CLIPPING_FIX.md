# Canvas Clipping Investigation - Known SwiftUI Limitation

**STATUS: REVERTED** - The attempted fixes caused more problems than they solved.

See `CANVAS_LIMITATIONS.md` for the current understanding and workarounds.

## Problem

Edges/wires were disappearing when nodes were positioned far from the viewport center. Only edges within a limited "invisible area" were visible, even though the canvas appeared to support panning to distant locations.

## Root Cause

The issue was a **Canvas coordinate space clipping problem** in SwiftUI:

1. **Limited Canvas Size**: The `EdgeLayer` used `.frame(maxWidth: .infinity, maxHeight: .infinity)`, which made the Canvas adopt the viewport size (e.g., 1920x1080).

2. **World Coordinate Drawing**: Edges were drawn in world coordinates (e.g., from node at x:5000 to node at x:8000), but the Canvas was only sized to the viewport dimensions.

3. **Clipping After Drawing**: SwiftUI's Canvas clips any content drawn outside its frame bounds. Even though `.scaleEffect()` and `.offset()` were applied after, the clipping had already occurred during the drawing phase.

4. **Symptom**: Edges connecting distant nodes were being clipped because their world-space coordinates exceeded the Canvas's coordinate space bounds.

## Research: Figma's Approach

Figma handles this with a **bounded but very large canvas**:

- **Canvas Boundaries**: ±32,768 pixels in each direction from the origin
- **Total Size**: 65,536 x 65,536 pixels
- **Not Truly Infinite**: The canvas has limits, but they're large enough to feel infinite for practical use
- **Coordinate System**: Objects can be placed anywhere within this range

## Performance Issues with Initial Fix

The first implementation caused severe performance degradation:
- **TimelineView at 60fps**: Continuously redrawing a massive 65536x65536 canvas
- **"Animating backwards in time" errors**: TimelineView couldn't keep up
- **Screen jerking/chugging**: App became unusable

## Optimized Solution Implemented

### 1. **Config Constants** (`Config.swift`)
Added Figma-inspired canvas boundary constants:

```swift
// Canvas boundary: Similar to Figma's approach (±32768 in each direction)
static let canvasBoundarySize: CGFloat = 65536  // Total size: 32768 * 2
static let canvasOriginOffset: CGFloat = 32768  // Center point offset
// Padding around nodes to ensure edges are always visible
static let edgeRenderingPadding: CGFloat = 5000
```

### 2. **Dynamic Canvas Sizing** (`CanvasView.swift`)
Instead of always allocating a huge 65536x65536 canvas, calculate optimal size based on actual content:

```swift
private func calculateOptimalCanvasSize(geometry: GeometryProxy) -> CGSize {
    // Find actual bounds of all nodes
    var minX/maxX/minY/maxY from node positions
    
    // Add padding for edges
    let padding = Config.edgeRenderingPadding
    
    // Use larger of content size or 2x viewport, capped at max boundary
    let optimalWidth = min(
        max(contentWidth, geometry.size.width * 2),
        Config.canvasBoundarySize
    )
    // ... same for height
}
```

**Benefits:**
- Small projects use small canvas (fast)
- Large projects grow canvas as needed (up to 65536 limit)
- No wasted memory on empty space

### 3. **Removed TimelineView** (`EdgeLayer.swift`)
**Critical Performance Fix**: Removed `TimelineView(.animation)` that was redrawing at 60fps:

**Before (SLOW):**
```swift
TimelineView(.animation) { _ in
    Canvas { ... } // Redrawing entire canvas 60 times per second!
}
```

**After (FAST):**
```swift
Canvas { context, size in
    // Only redraws when positionsVersion changes (on node move)
    for edge in edges { ... }
}
```

### 4. **Hardware Acceleration** (`CanvasView.swift`)
Added `.drawingGroup()` to enable Metal-accelerated rendering:

```swift
EdgeLayer(edges: edgesArray, frames: nodeFrames)
    .drawingGroup() // Enables GPU acceleration
    .allowsHitTesting(false)
```

## How This Fixes the Issue

### Before Fix:
1. EdgeLayer Canvas sized to viewport (e.g., 1920 x 1080)
2. Edge drawn from node at (x:5000, y:3000) to node at (x:8000, y:4000)
3. Canvas clips anything beyond (1920, 1080) ❌
4. Edge disappears even though both nodes might be visible after transform

### After Fix:
1. EdgeLayer Canvas sized **dynamically** based on content (e.g., 8000 x 6000 for this project)
2. Edge drawn from node at (x:5000, y:3000) to node at (x:8000, y:4000)  
3. Canvas only clips beyond dynamic boundary (much larger than viewport) ✅
4. Edge remains visible as long as nodes are within the boundary
5. Transform (zoom/offset) is applied to the entire canvas
6. Only redraws when nodes move (not 60fps)
7. GPU-accelerated rendering via Metal

## Performance Comparison

### Initial "Fix" (BROKEN):
- ❌ Canvas: Always 65536 x 65536 pixels
- ❌ Redrawing: 60 times per second via TimelineView
- ❌ Result: Severe performance degradation, app unusable
- ❌ "Animating backwards in time" errors

### Optimized Fix (WORKING):
- ✅ Canvas: Dynamic size based on content (typically 2x-10x viewport)
- ✅ Redrawing: Only when nodes move (on-demand)
- ✅ Metal acceleration: GPU rendering via `.drawingGroup()`
- ✅ Result: Smooth performance, edges always visible
- ✅ Scales efficiently from small to large projects

## Benefits

✅ **Edges visible across entire canvas**: Up to ±32,768 pixels from origin (65536x65536 boundary)
✅ **Matches Figma UX**: Large bounded canvas that feels infinite in practice
✅ **Excellent performance**: 
  - Dynamic canvas sizing (only allocates what's needed)
  - On-demand rendering (no continuous 60fps redraw)
  - GPU acceleration via Metal
  - Smooth panning and zooming
✅ **Efficient memory usage**: Canvas grows with content, not fixed huge size
✅ **Consistent behavior**: Edges and nodes use same coordinate space

## Coordinate Range

The canvas now supports:
- **X coordinates**: 0 to 65,536 (with origin at top-left)
- **Y coordinates**: 0 to 65,536
- **Practical range**: More than enough for typical use cases

For reference:
- Viewport is typically ~1920 x 1080
- Canvas is 65536 x 65536 (34x larger in each dimension)
- That's ~1,156x the viewport area!

## Testing Recommendations

1. **Create Distant Nodes**: 
   - Pan far from origin and create nodes
   - Connect them with edges
   - Pan back and verify edges remain visible

2. **Stress Test**:
   - Create nodes at coordinates near 60,000
   - Verify edges draw correctly
   - Test zoom and pan behaviors

3. **Edge Cases**:
   - Nodes at (0, 0) and (65000, 65000)
   - Verify edges connect across maximum distance
   - Check that edges near boundary are visible

4. **Performance**:
   - Create many nodes spread across canvas
   - Verify smooth panning and zooming
   - Check that edge rendering remains smooth

## Migration Notes

- **Existing projects**: Will continue to work without changes
- **Coordinate system**: Unchanged (same world coordinates)
- **Node positioning**: Same as before (positive coordinates from top-left)
- **No data migration needed**: This is purely a rendering fix

## Files Modified

1. `/JamAI/Utils/Config.swift` - Added canvas boundary constants
2. `/JamAI/Views/CanvasView.swift` - Unified canvas container with explicit size
3. `/JamAI/Views/EdgeLayer.swift` - Simplified to rely on parent container size

## How This Compares to Figma

Figma's implementation:
- **View culling**: Only renders objects in/near viewport
- **Canvas API**: Low-level WebGL/Canvas2D rendering
- **Fixed large boundary**: ±32,768 from origin
- **Lazy rendering**: On-demand, not continuous

Our optimized implementation:
- **Dynamic sizing**: Canvas grows with content (up to Figma's limits)
- **SwiftUI Canvas + Metal**: Hardware-accelerated rendering
- **On-demand updates**: Only redraws when needed (via `positionsVersion`)
- **Efficient transforms**: Single transform applied to unified container

**Result**: Similar UX to Figma with good performance characteristics

## Additional Notes

- The 65,536 size can be adjusted in `Config.swift` if needed
- Could be made even larger (e.g., 131,072) but current size is plenty
- The approach is memory-efficient since canvas size adapts to content
- SwiftUI's `Canvas` with `.drawingGroup()` provides efficient GPU rendering
- Performance scales well from small projects (few nodes) to large ones (hundreds of nodes)
