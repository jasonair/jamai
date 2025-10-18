//
//  DiagonalResizeCursor.swift
//  JamAI
//
//  Custom diagonal resize cursor for macOS
//

import AppKit

struct DiagonalResizeCursor {
    private static var cursor: NSCursor = {
        // Create a custom diagonal resize cursor (NW-SE direction)
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        // Draw diagonal resize arrow (northwest to southeast)
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        
        // Set up drawing parameters
        let arrowColor = NSColor.black
        let strokeWidth: CGFloat = 2.0
        
        // Main diagonal line
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 6, y: 18))
        path.line(to: NSPoint(x: 18, y: 6))
        path.lineWidth = strokeWidth
        
        // Arrow head at top-right (southeast)
        path.move(to: NSPoint(x: 18, y: 6))
        path.line(to: NSPoint(x: 14, y: 6))
        path.move(to: NSPoint(x: 18, y: 6))
        path.line(to: NSPoint(x: 18, y: 10))
        
        // Arrow head at bottom-left (northwest)
        path.move(to: NSPoint(x: 6, y: 18))
        path.line(to: NSPoint(x: 10, y: 18))
        path.move(to: NSPoint(x: 6, y: 18))
        path.line(to: NSPoint(x: 6, y: 14))
        
        // Draw white outline for visibility
        NSColor.white.setStroke()
        path.lineWidth = strokeWidth + 1
        path.stroke()
        
        // Draw black arrow
        arrowColor.setStroke()
        path.lineWidth = strokeWidth
        path.stroke()
        
        context?.restoreGState()
        
        image.unlockFocus()
        
        // Hotspot at center
        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }()
    
    static func push() {
        cursor.push()
    }
}
