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
    let onColorChange: (String) -> Void
    let onRetryIndexing: () -> Void
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
    @State private var thumbnailImage: NSImage? = nil
    @State private var isLoadingThumbnail: Bool = true
    @State private var showingExternalLinkAlert: Bool = false
    @State private var showingColorPicker: Bool = false
    
    // Indexing status - uses external isIndexing flag from CanvasViewModel
    private var indexingStatus: IndexingStatus {
        // Treat as indexed if we have a Gemini file URI
        if node.youtubeFileUri != nil {
            return .indexed
        }
        
        // While actively indexing, always show "Indexing..."
        if isIndexing {
            return .indexing
        }
        
        // If we're no longer indexing but do have a transcript cached, consider it indexed
        if let transcript = node.youtubeTranscript, !transcript.isEmpty {
            return .indexed
        }
        
        // Otherwise, no transcript available
        return .noTranscript
    }
    
    enum IndexingStatus {
        case indexing
        case indexed
        case noTranscript  // No transcript available or indexing failed
    }
    
    private var backgroundColor: Color {
        if colorScheme == .dark {
            return Color(white: 0.15)
        } else {
            return Color.white
        }
    }
    
    /// Returns the node's color if set, otherwise nil
    private var nodeColor: Color? {
        guard node.color != "none" else { return nil }
        return NodeColor.color(for: node.color)?.color
    }
    
    /// Background tint for header and info bar based on node color
    private var colorTint: Color {
        if let color = nodeColor {
            return colorScheme == .dark 
                ? color.opacity(0.25) 
                : color.opacity(0.15)
        }
        return colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.95)
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
    
    // Computed thumbnail height (16:9 aspect ratio based on node width)
    private var thumbnailHeight: CGFloat {
        Node.youtubeWidth * (9.0 / 16.0)
    }
    
    // Info bar height
    private let infoBarHeight: CGFloat = 60
    
    // Info bar background - dark with optional color tint
    private var infoBarBackground: Color {
        if let color = nodeColor {
            return color.opacity(0.85)
        }
        return Color(white: 0.15)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail at the top
            thumbnailView
                .frame(width: Node.youtubeWidth, height: thumbnailHeight)
                .clipped()
            
            // Info bar at bottom
            infoBar
                .frame(width: Node.youtubeWidth, height: infoBarHeight)
        }
        .frame(width: Node.youtubeWidth, height: Node.youtubeHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: isSelected || isMultiSelected ? 2 : 1)
        )
        // Color picker overlay - always visible in top-left corner
        .overlay(alignment: .topLeading) {
            Button(action: { showingColorPicker.toggle() }) {
                Circle()
                    .fill(nodeColor ?? (colorScheme == .dark ? Color(white: 0.3) : Color(white: 0.85)))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .help("Change Color")
            .padding(8)
            .popover(isPresented: $showingColorPicker) {
                ColorPickerPopover(selectedColorId: node.color) { newColorId in
                    onColorChange(newColorId)
                }
            }
        }
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.1),
            radius: isSelected ? 6 : 3,
            x: 0,
            y: isSelected ? 3 : 1
        )
        .overlay(
            ConnectionPointsOverlayInline(
                nodeId: node.id,
                nodeWidth: Node.youtubeWidth,
                nodeHeight: Node.youtubeHeight,
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
            // Debug logging
            print("📺 [YouTubeView] Node \(node.id) appeared. URI: \(node.youtubeFileUri ?? "nil"), Transcript: \(node.youtubeTranscript?.prefix(20) ?? "nil"), Indexing: \(isIndexing)")
        }
        .onChange(of: node.youtubeThumbnailUrl) { _, _ in
            loadThumbnail()
        }
        .onChange(of: isIndexing) { _, newValue in
            print("📺 [YouTubeView] Node \(node.id) indexing changed to: \(newValue)")
        }
        .onChange(of: node.youtubeFileUri) { _, newValue in
            print("📺 [YouTubeView] Node \(node.id) URI changed to: \(newValue ?? "nil")")
        }
        .alert("Open YouTube Video?", isPresented: $showingExternalLinkAlert) {
            Button("Open in Browser") {
                onOpenInBrowser()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You're about to leave Jam AI and open YouTube in your browser.")
        }
    }
    
    // MARK: - Subviews
    
    private var thumbnailView: some View {
        ZStack {
            // Background
            Rectangle()
                .fill(Color.black)
            
            // Thumbnail image - preserve full 16:9 frame without side cropping
            if let image = thumbnailImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Node.youtubeWidth, height: thumbnailHeight)
                    .clipped()
            } else if isLoadingThumbnail {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                // Fallback
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
            }
            
            // Play button - only this is clickable for opening video
            Button(action: {
                showingExternalLinkAlert = true
            }) {
                Circle()
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: 2)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var infoBar: some View {
        HStack(spacing: 8) {
            // YouTube icon
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 16))
                .foregroundColor(.red)
            
            // Title and status
            VStack(alignment: .leading, spacing: 2) {
                Text(node.youtubeTitle ?? "YouTube Video")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                // Indexing status
                HStack(spacing: 4) {
                    switch indexingStatus {
                    case .indexing:
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 10, height: 10)
                        Text("Indexing...")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    case .indexed:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                        Text("Indexed")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                    case .noTranscript:
                        HStack(spacing: 4) {
                            Image(systemName: "text.badge.xmark")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                            Text("No transcript")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                            
                            // Retry button
                            Button(action: onRetryIndexing) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white)
                                    .padding(2)
                                    .background(Color.white.opacity(0.2))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Retry Indexing")
                        }
                    }
                }
            }
            
            Spacer(minLength: 0)
            
            // Delete button (shown on hover)
            if isHovering || isSelected {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Delete Video")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(infoBarBackground)
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
            onOpenInBrowser: {},
            onColorChange: { _ in },
            onRetryIndexing: {}
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
            onOpenInBrowser: {},
            onColorChange: { _ in },
            onRetryIndexing: {}
        )
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
