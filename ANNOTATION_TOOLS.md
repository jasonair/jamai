# Annotation Tools - FigJam-Style Implementation

## Overview
Added FigJam and Apple Freeform-inspired annotation tools to enhance canvas organization and visual communication.

## Features Implemented

### 1. Bottom Tool Dock
**Location**: Bottom-center of canvas
**Tools Available**:
- Select (V) - Default selection tool
- Text (T) - Add text labels
- Rectangle (R) - Add rectangular shapes
- Ellipse (O) - Add circular shapes

### 2. Text Labels
**Behavior**:
- Click canvas with Text tool to place
- Auto-enters edit mode on creation
- Dynamic width based on content (100px - 600px)
- No background color (transparent)
- Double-click to edit existing text
- Click outside to exit edit mode
- Fully draggable when not editing

**Formatting Options**:
- Font size (8-96pt)
- Bold toggle
- Font family (Default, Serif, Mono)
- Color picker

### 3. Shape Annotations
**Types**:
- Rectangle with rounded corners
- Ellipse

**Behavior**:
- Click canvas with shape tool to place
- Fixed size (160x120 default)
- Color-coded fills from node palette
- Fully draggable
- Selection outline on select

### 4. Contextual Formatting Bar
**Appearance**: Shows when text or shape is selected
**Location**: Bottom-center, above tool dock
**Controls**:
- Text: Bold, size adjustment, font family, color
- Shape: Fill color

### 5. Keyboard Shortcuts (FigJam-Style)
```
V         - Select tool
T         - Text label tool
R         - Rectangle tool
O         - Ellipse tool
ESC       - Cancel tool / Deselect all
Shift+Click - Keep tool active (place multiple)
```

### 6. Power User Features
**Shift-Click Behavior**:
- Normally: Tool auto-switches to Select after placement
- With Shift: Tool stays active for multiple placements

**Escape Key**:
- Cancels active tool
- Deselects all items
- Returns to Select mode

## UX Patterns (Based on FigJam/Freeform Research)

### Tool Selection Flow
1. Press keyboard shortcut or click dock button
2. Tool becomes active (visual highlight)
3. Click canvas to place item
4. Tool auto-switches to Select (beginner-friendly)
5. OR: Hold Shift while placing to keep tool active (power users)

### Text Editing Flow
1. Place text → Auto-enters edit mode with cursor
2. Type text → Updates in real-time
3. Press Enter or click away → Exits edit mode
4. Text becomes draggable
5. Double-click to edit again
6. Select to show formatting bar

### Annotation Dragging
- Text in display mode: Draggable
- Text in edit mode: Not draggable (TextField captures input)
- Shapes: Always draggable
- Nodes: Always draggable (unchanged)

### UI Interaction Hierarchy
**Blocks canvas tap**:
- Top toolbar
- Bottom tool dock
- Formatting bar
- Grid toggle button

**Allows canvas tap**:
- Empty canvas space
- Background layer

## Files Changed

### New Files
- `JamAI/Models/Tool.swift` - CanvasTool enum
- `JamAI/Views/ToolDockView.swift` - Bottom dock UI
- `JamAI/Views/TextLabelView.swift` - Text annotation view
- `JamAI/Views/ShapeItemView.swift` - Shape annotation view
- `JamAI/Views/FormattingBarView.swift` - Contextual formatting
- `ANNOTATION_TOOLS.md` - This document

### Modified Files
- `JamAI/Models/Node.swift` - Added text/shape types, formatting fields
- `JamAI/Storage/Database.swift` - Schema migrations for new fields
- `JamAI/Services/CanvasViewModel.swift` - Tool state, creation methods
- `JamAI/Views/CanvasView.swift` - Tool integration, keyboard shortcuts
- `JamAI/Views/NodeItemWrapper.swift` - Render text/shape, dynamic sizing
- `QUICKSTART.md` - Documentation updates

## Database Schema Updates

### New Columns in `nodes` Table
```sql
font_size REAL DEFAULT 16
is_bold BOOLEAN DEFAULT 0
font_family TEXT
shape_kind TEXT
```

### New NodeType Values
- `.text` - Text labels
- `.shape` - Geometric shapes

### New Enum: ShapeKind
- `.rectangle`
- `.ellipse`

## Known Behaviors

### Auto-Switch to Select
By default, after placing an annotation, the tool switches back to Select mode. This prevents accidentally creating multiple items while trying to interact with the formatting bar.

### Shift Override
Power users can hold Shift while clicking to keep the tool active for placing multiple items quickly.

### Text Width
Text labels dynamically size based on content length and font size:
- Minimum: 100px
- Maximum: 600px
- Formula: `max(100, min(600, textLength * fontSize * 0.6 + 40))`

### No Text Background
Text labels have no background fill (transparent) to feel lightweight and overlay nodes naturally.

### Selection States
- Text selected + not editing → Shows formatting bar + trash button
- Text selected + editing → No formatting bar, no trash (editing mode)
- Shape selected → Shows formatting bar + trash button
- Nothing selected → No formatting bar

## Future Enhancements (Not Implemented)

### Potential Additions
- Stroke width/color for shapes
- Text alignment (left/center/right)
- Click-drag to draw custom-sized shapes
- Arrow/line tool for connectors
- Sticky note tool
- More shape types (triangle, star, etc.)
- Multi-select for bulk operations
- Copy/paste annotations
- Layer ordering (bring to front/send to back)
- Opacity controls
- Shadow effects

### Performance Optimizations
- Virtualized rendering for 100+ annotations
- Shape instancing
- Text caching

## Testing Checklist

- [x] Place text label
- [x] Edit text inline
- [x] Drag text label
- [x] Format text (size, bold, font, color)
- [x] Place rectangle
- [x] Place ellipse
- [x] Drag shapes
- [x] Format shapes (color)
- [x] Keyboard shortcuts work
- [x] Shift+click keeps tool active
- [x] ESC cancels tool
- [x] Formatting bar doesn't create items
- [x] Click outside text deselects
- [x] Double-click text enters edit mode
- [x] Text auto-focuses on creation
- [x] No background color on text
- [x] Text width adjusts to content
- [x] Persistence (save/load)
- [x] Undo/redo support

## Design Rationale

### Why Auto-Switch to Select?
FigJam offers both modes (persistent and auto-switch). We chose auto-switch as the default because:
1. Prevents accidental multi-creation
2. More intuitive for beginners
3. Power users can use Shift override
4. Reduces clicks needed to interact with formatting

### Why No Text Background?
1. Cleaner visual appearance
2. Works better overlaid on nodes
3. FigJam sticky notes have backgrounds, but quick text labels don't
4. Freeform uses transparent text for annotations
5. Reduces visual clutter on busy canvases

### Why Dynamic Text Width?
1. Prevents excessive white space
2. Natural reading experience
3. Adapts to different font sizes
4. Min/max bounds prevent extreme sizes
5. Similar to FigJam's text auto-sizing

### Why Bottom Dock?
1. Doesn't interfere with top toolbar
2. Thumb-friendly on trackpads
3. Centered position is equidistant from all canvas areas
4. Mirrors FigJam's tool placement
5. Formatting bar can appear above it naturally

---

**Implementation Complete**: All core annotation features working and documented.
