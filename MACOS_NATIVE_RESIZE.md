# macOS-Native Resize Design

## Visual Design

### Resize Grip
The resize grip uses the classic macOS pattern seen in TextEdit, Finder, and other native apps:
- **Three diagonal lines** (↗) in the bottom-right corner
- Adapts to **light and dark mode** appearance
- Semi-transparent for subtlety (40% white in dark mode, 30% black in light mode)

### Cursor
The diagonal resize cursor follows macOS conventions:
- **Northwest-to-southeast double-headed arrow** (↖↘)
- Black stroke with white outline for visibility
- Appears on hover over the resize grip
- Stays active during the entire drag operation
- 24x24pt size with center hotspot

## Implementation

### ResizeGripView
```swift
// Draws three parallel diagonal lines
// Automatically adapts to appearance mode
// 16x16pt canvas, 12pt line length
// 3.5pt spacing between lines
```

### DiagonalResizeCursor
```swift
// Custom NSCursor with diagonal arrow
// White outline + black foreground
// Pushed on hover, popped on mouse exit
// Follows cursor stack conventions
```

## User Experience Flow

1. **Idle State**: Resize grip visible in corner with subtle opacity
2. **Hover**: Cursor changes to diagonal resize arrow
3. **Drag Start**: Cursor locked to diagonal resize, smooth resizing begins
4. **During Drag**: Local state updates (no binding mutations) = 60fps smooth
5. **Drag End**: Cursor pops back, final size persisted to database

## Design Philosophy

Follows Apple's Human Interface Guidelines:
- **Familiar**: Uses same patterns as TextEdit, Finder, Preview
- **Discoverable**: Visual grip indicates functionality
- **Responsive**: Immediate cursor feedback
- **Smooth**: No jank or stuttering during interaction
- **Native**: Feels like a first-party macOS app

## Comparison with Other Apps

### TextEdit
✅ Three diagonal lines in corner  
✅ Diagonal resize cursor  
✅ Smooth resizing

### Figma (Web)
❌ Different resize handle design  
❌ Web-based cursor limitations

### JamAI (Now)
✅ Matches TextEdit/native macOS design  
✅ Custom cursor for optimal UX  
✅ Smooth 60fps performance
