//
//  ConnectionPointView.swift
//  JamAI
//
//  Hoverable connection point that appears on node edges for manual wiring
//

import SwiftUI

struct ConnectionPointView: View {
    let nodeId: UUID
    let side: ConnectionSide
    let isWiring: Bool
    let isValidDropTarget: Bool
    let hasConnection: Bool  // Whether this point has an existing connection
    let onClickToStartWiring: (UUID, ConnectionSide) -> Void  // Click to start wiring
    let onClickToConnect: (UUID, ConnectionSide) -> Void      // Click to complete connection
    let onDeleteConnection: ((UUID, ConnectionSide) -> Void)?  // Click to delete existing connection
    
    @State private var isHovered: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var isOptionKeyPressed: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    private let pointSize: CGFloat = 16
    private let hitAreaSize: CGFloat = 32
    
    var body: some View {
        ZStack {
            // Hit area (invisible, larger for easier interaction)
            Circle()
                .fill(Color.clear)
                .frame(width: hitAreaSize, height: hitAreaSize)
                .contentShape(Circle())
            
            // Visual connection point
            if hasConnection && isHovered && isOptionKeyPressed && !isWiring {
                // Show minus icon when Option+hovering over connected point (delete mode)
                Circle()
                    .fill(Color.red.opacity(0.9))
                    .frame(width: pointSize, height: pointSize)
                    .overlay(
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 8, height: 2)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.red, lineWidth: 1.5)
                    )
            } else if hasConnection {
                // Filled circle when connected
                Circle()
                    .fill(fillColor)
                    .frame(width: pointSize, height: pointSize)
                    .overlay(
                        Circle()
                            .stroke(strokeColor, lineWidth: 1.5)
                    )
            } else if isValidDropTarget {
                // Green filled circle for valid drop target
                Circle()
                    .fill(Color.green.opacity(0.8))
                    .frame(width: pointSize, height: pointSize)
                    .overlay(
                        Circle()
                            .stroke(Color.green, lineWidth: 1.5)
                    )
            } else {
                // Outline circle by default (no fill, just stroke)
                Circle()
                    .stroke(strokeColor, lineWidth: isHovered ? 2 : 1.5)
                    .frame(width: pointSize, height: pointSize)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.black.opacity(0.6) : Color.white.opacity(0.9))
                    )
            }
        }
        .shadow(color: shadowColor, radius: isHovered ? 3 : 1, x: 0, y: 1)
        .scaleEffect(isHovered || isValidDropTarget ? 1.2 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isValidDropTarget)
        .onHover { hovering in
            isHovered = hovering
        }
        // Track Option key for delete mode
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                isOptionKeyPressed = event.modifierFlags.contains(.option)
                return event
            }
        }
        // Click gesture - Option+click to delete, regular click to wire
        .onTapGesture {
            if isWiring && isValidDropTarget {
                // Complete the connection
                onClickToConnect(nodeId, side)
            } else if hasConnection && isOptionKeyPressed && !isWiring {
                // Option+click on connected point: show delete confirmation
                showDeleteConfirmation = true
            } else if !isWiring {
                // Regular click: start wiring from this point (even if already connected)
                onClickToStartWiring(nodeId, side)
            }
        }
        .cursor(deleteMode ? .pointingHand : (isHovered ? .crosshair : .arrow))
        .popover(isPresented: $showDeleteConfirmation, arrowEdge: .top) {
            VStack(spacing: 12) {
                Text("Delete this connection?")
                    .font(.system(size: 13, weight: .medium))
                
                HStack(spacing: 12) {
                    Button("Cancel") {
                        showDeleteConfirmation = false
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Delete") {
                        showDeleteConfirmation = false
                        onDeleteConnection?(nodeId, side)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(12)
        }
    }
    
    private var deleteMode: Bool {
        hasConnection && isHovered && isOptionKeyPressed && !isWiring
    }
    
    private var fillColor: Color {
        if isValidDropTarget {
            return Color.green.opacity(0.8)
        } else if hasConnection {
            return colorScheme == .dark 
                ? Color.white.opacity(0.9) 
                : Color.white
        } else {
            return Color.clear
        }
    }
    
    private var strokeColor: Color {
        if isValidDropTarget {
            return Color.green
        } else if isHovered {
            return colorScheme == .dark 
                ? Color.white.opacity(0.9) 
                : Color.black.opacity(0.6)
        } else {
            return colorScheme == .dark 
                ? Color.white.opacity(0.5) 
                : Color.black.opacity(0.3)
        }
    }
    
    private var shadowColor: Color {
        colorScheme == .dark 
            ? Color.black.opacity(0.2) 
            : Color.black.opacity(0.1)
    }
}

// MARK: - Cursor Extension

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Connection Points Overlay (Inline version for NodeView)

/// Overlay that adds connection points to all four sides of a node
/// This version uses .position() which works correctly inside NodeView's overlay
struct ConnectionPointsOverlayInline: View {
    let nodeId: UUID
    let nodeWidth: CGFloat
    let nodeHeight: CGFloat
    let isNodeHovered: Bool
    let isNodeSelected: Bool
    let isWiring: Bool
    let wireSourceNodeId: UUID?
    let hasTopConnection: Bool
    let hasRightConnection: Bool
    let hasBottomConnection: Bool
    let hasLeftConnection: Bool
    let onClickToStartWiring: (UUID, ConnectionSide) -> Void
    let onClickToConnect: (UUID, ConnectionSide) -> Void
    let onDeleteConnection: ((UUID, ConnectionSide) -> Void)?
    
    // Gap between node edge and the nearest edge of the connection circle
    // Circle center is positioned at (gap + radius) from node edge
    // With pointSize=16 (radius=8) and gap=3, center is at 11px from node edge
    private let edgeGap: CGFloat = 11  // 3px gap + 8px radius
    
    init(
        nodeId: UUID,
        nodeWidth: CGFloat,
        nodeHeight: CGFloat,
        isNodeHovered: Bool,
        isNodeSelected: Bool = false,
        isWiring: Bool,
        wireSourceNodeId: UUID?,
        hasTopConnection: Bool = false,
        hasRightConnection: Bool = false,
        hasBottomConnection: Bool = false,
        hasLeftConnection: Bool = false,
        onClickToStartWiring: @escaping (UUID, ConnectionSide) -> Void,
        onClickToConnect: @escaping (UUID, ConnectionSide) -> Void,
        onDeleteConnection: ((UUID, ConnectionSide) -> Void)? = nil
    ) {
        self.nodeId = nodeId
        self.nodeWidth = nodeWidth
        self.nodeHeight = nodeHeight
        self.isNodeHovered = isNodeHovered
        self.isNodeSelected = isNodeSelected
        self.isWiring = isWiring
        self.wireSourceNodeId = wireSourceNodeId
        self.hasTopConnection = hasTopConnection
        self.hasRightConnection = hasRightConnection
        self.hasBottomConnection = hasBottomConnection
        self.hasLeftConnection = hasLeftConnection
        self.onClickToStartWiring = onClickToStartWiring
        self.onClickToConnect = onClickToConnect
        self.onDeleteConnection = onDeleteConnection
    }
    
    var body: some View {
        ZStack {
            // Top (positioned above node with gap)
            ConnectionPointView(
                nodeId: nodeId,
                side: .top,
                isWiring: isWiring,
                isValidDropTarget: isValidDropTarget,
                hasConnection: hasTopConnection,
                onClickToStartWiring: onClickToStartWiring,
                onClickToConnect: onClickToConnect,
                onDeleteConnection: onDeleteConnection
            )
            .position(x: nodeWidth / 2, y: -edgeGap)
            
            // Right (positioned to the right of node with gap)
            ConnectionPointView(
                nodeId: nodeId,
                side: .right,
                isWiring: isWiring,
                isValidDropTarget: isValidDropTarget,
                hasConnection: hasRightConnection,
                onClickToStartWiring: onClickToStartWiring,
                onClickToConnect: onClickToConnect,
                onDeleteConnection: onDeleteConnection
            )
            .position(x: nodeWidth + edgeGap, y: nodeHeight / 2)
            
            // Bottom (positioned below node with gap)
            ConnectionPointView(
                nodeId: nodeId,
                side: .bottom,
                isWiring: isWiring,
                isValidDropTarget: isValidDropTarget,
                hasConnection: hasBottomConnection,
                onClickToStartWiring: onClickToStartWiring,
                onClickToConnect: onClickToConnect,
                onDeleteConnection: onDeleteConnection
            )
            .position(x: nodeWidth / 2, y: nodeHeight + edgeGap)
            
            // Left (positioned to the left of node with gap)
            ConnectionPointView(
                nodeId: nodeId,
                side: .left,
                isWiring: isWiring,
                isValidDropTarget: isValidDropTarget,
                hasConnection: hasLeftConnection,
                onClickToStartWiring: onClickToStartWiring,
                onClickToConnect: onClickToConnect,
                onDeleteConnection: onDeleteConnection
            )
            .position(x: -edgeGap, y: nodeHeight / 2)
        }
        .opacity(shouldShowOverlay ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.15), value: shouldShowOverlay)
        .allowsHitTesting(shouldShowOverlay)
    }
    
    private var shouldShowOverlay: Bool {
        isNodeHovered || isNodeSelected || isWiring
    }
    
    private var isValidDropTarget: Bool {
        isWiring && wireSourceNodeId != nil && wireSourceNodeId != nodeId
    }
}

