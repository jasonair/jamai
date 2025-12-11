//
//  YouTubeNodeView.swift
//  JamAI
//
//  Compact view for YouTube video nodes on the canvas
//

import SwiftUI

/// Compact YouTube node view - shows thumbnail with video title
struct YouTubeNodeView: View {
    @Binding var node: Node
    let isSelected: Bool
    let isMultiSelected: Bool
    let onDelete: () -> Void
    let onOpenInBrowser: () -> Void
    
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
    @State private var thumbnailImage: NSImage? = nil
    @State private var isLoadingThumbnail: Bool = true
    
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail area
            ZStack {
                // Background placeholder
                Rectangle()
                    .fill(Color.black.opacity(0.1))
                
                if let image = thumbnailImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: Node.youtubeWidth - 2, height: 120)
                        .clipped()
                } else if isLoadingThumbnail {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    // Fallback YouTube icon
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.red)
                }
                
                // Play button overlay
                Circle()
                    .fill(Color.red)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: 2) // Optical centering
                    )
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .frame(height: 120)
            .clipped()
            
            // Title and actions area
            HStack(spacing: 8) {
                // YouTube icon
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.red)
                
                // Title
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.youtubeTitle ?? "YouTube Video")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .primary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                
                Spacer(minLength: 0)
                
                // Actions (shown on hover)
                if isHovering || isSelected {
                    HStack(spacing: 6) {
                        Button(action: onOpenInBrowser) {
                            Image(systemName: "safari")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Open in Browser")
                        
                        Button(action: onDelete) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Delete Video")
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(width: Node.youtubeWidth, height: Node.youtubeHeight)
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
        .onAppear {
            loadThumbnail()
        }
        .onChange(of: node.youtubeThumbnailUrl) { _, _ in
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard let urlString = node.youtubeThumbnailUrl,
              let url = URL(string: urlString) else {
            isLoadingThumbnail = false
            return
        }
        
        isLoadingThumbnail = true
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = NSImage(data: data) {
                    await MainActor.run {
                        self.thumbnailImage = image
                        self.isLoadingThumbnail = false
                    }
                } else {
                    await MainActor.run {
                        self.isLoadingThumbnail = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingThumbnail = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        YouTubeNodeView(
            node: .constant(Node(
                projectId: UUID(),
                type: .youtube,
                youtubeUrl: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                youtubeVideoId: "dQw4w9WgXcQ",
                youtubeTitle: "Rick Astley - Never Gonna Give You Up",
                youtubeThumbnailUrl: "https://img.youtube.com/vi/dQw4w9WgXcQ/mqdefault.jpg"
            )),
            isSelected: false,
            isMultiSelected: false,
            onDelete: {},
            onOpenInBrowser: {}
        )
        
        YouTubeNodeView(
            node: .constant(Node(
                projectId: UUID(),
                type: .youtube,
                youtubeVideoId: "abc123",
                youtubeTitle: "A Very Long Video Title That Should Truncate Properly When It Gets Too Long"
            )),
            isSelected: true,
            isMultiSelected: false,
            onDelete: {},
            onOpenInBrowser: {}
        )
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
