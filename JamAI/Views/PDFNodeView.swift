//
//  PDFNodeView.swift
//  JamAI
//
//  Compact view for PDF document nodes on the canvas
//

import SwiftUI

/// Compact PDF node view - shows filename with PDF icon
/// Approximately 50% smaller than standard nodes
struct PDFNodeView: View {
    @Binding var node: Node
    let isSelected: Bool
    let isMultiSelected: Bool
    let onDelete: () -> Void
    let onRevealInFinder: () -> Void
    var isIndexing: Bool = false  // Passed from CanvasViewModel.indexingNodeIds
    
    // Wiring props
    var isWiring: Bool = false
    var wireSourceNodeId: UUID? = nil
    var onClickToStartWiring: ((UUID, ConnectionSide) -> Void)? = nil
    var onClickToConnect: ((UUID, ConnectionSide) -> Void)? = nil
    var onDeleteConnection: ((UUID, ConnectionSide) -> Void)? = nil
    var hasTopConnection: Bool = false
    var hasRightConnection: Bool = false
    var hasBottomConnection: Bool = false
    var hasLeftConnection: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var isHovering: Bool = false
    
    // Computed upload status based on node state and external indexing flag
    private var uploadStatus: UploadStatus {
        if node.pdfFileUri != nil {
            return .active
        } else if isIndexing {
            return .uploading
        } else if node.pdfData != nil {
            return .uploading  // Has data, will be indexed
        } else {
            return .error("No PDF data")
        }
    }
    
    enum UploadStatus: Equatable {
        case uploading
        case active
        case error(String)
    }
    
    private var backgroundColor: Color {
        if colorScheme == .dark {
            return Color(white: 0.15)
        } else {
            return Color.white
        }
    }
    
    private var borderColor: Color {
        if isSelected {
            return .accentColor
        } else if isMultiSelected {
            return .blue
        } else {
            return colorScheme == .dark ? Color(white: 0.3) : Color(white: 0.85)
        }
    }
    
    private var statusColor: Color {
        switch uploadStatus {
        case .uploading:
            return .orange
        case .active:
            return .green
        case .error:
            return .red
        }
    }
    
    private var statusIcon: String {
        switch uploadStatus {
        case .uploading:
            return "arrow.up.circle.fill"
        case .active:
            return "checkmark.circle.fill"
        case .error:
            return "xmark.circle.fill"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            HStack(spacing: 10) {
                // PDF Icon
                Image(systemName: "doc.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.blue)
                
                // Filename
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.pdfFileName ?? "Untitled.pdf")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    // Status indicator
                    HStack(spacing: 4) {
                        if uploadStatus == .uploading {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 10, height: 10)
                        } else {
                            Image(systemName: statusIcon)
                                .font(.system(size: 10))
                                .foregroundColor(statusColor)
                        }
                        
                        Text(statusText)
                            .font(.system(size: 10))
                            .foregroundColor(uploadStatus == .uploading ? .orange : .secondary)
                    }
                }
                
                Spacer(minLength: 0)
                
                // Actions (shown on hover)
                if isHovering || isSelected {
                    HStack(spacing: 6) {
                        Button(action: onRevealInFinder) {
                            Image(systemName: "folder")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")
                        
                        Button(action: onDelete) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Delete Document")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: Node.pdfWidth, height: Node.pdfHeight)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: isSelected || isMultiSelected ? 2 : 1)
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.1),
            radius: isSelected ? 6 : 3,
            x: 0,
            y: isSelected ? 3 : 1
        )
        .overlay(
            ConnectionPointsOverlayInline(
                nodeId: node.id,
                nodeWidth: node.width,
                nodeHeight: node.height,
                isNodeHovered: isHovering,
                isNodeSelected: isSelected,
                isWiring: isWiring,
                wireSourceNodeId: wireSourceNodeId,
                hasTopConnection: hasTopConnection,
                hasRightConnection: hasRightConnection,
                hasBottomConnection: hasBottomConnection,
                hasLeftConnection: hasLeftConnection,
                onClickToStartWiring: onClickToStartWiring ?? { _, _ in },
                onClickToConnect: onClickToConnect ?? { _, _ in },
                onDeleteConnection: onDeleteConnection
            )
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var statusText: String {
        switch uploadStatus {
        case .uploading:
            return "Indexing..."
        case .active:
            return "Indexed"
        case .error(let message):
            return message
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        PDFNodeView(
            node: .constant(Node(
                projectId: UUID(),
                type: .pdf,
                pdfFileUri: "files/abc123",
                pdfFileName: "Research_Paper_2024.pdf"
            )),
            isSelected: false,
            isMultiSelected: false,
            onDelete: {},
            onRevealInFinder: {}
        )
        
        PDFNodeView(
            node: .constant(Node(
                projectId: UUID(),
                type: .pdf,
                pdfFileName: "Very_Long_Document_Name_That_Should_Truncate.pdf"
            )),
            isSelected: true,
            isMultiSelected: false,
            onDelete: {},
            onRevealInFinder: {}
        )
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
