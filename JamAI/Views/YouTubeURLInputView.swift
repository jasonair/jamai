//
//  YouTubeURLInputView.swift
//  JamAI
//
//  Simple input view for entering YouTube URLs
//

import SwiftUI

struct YouTubeURLInputView: View {
    @Binding var urlInput: String
    let onSubmit: () -> Void
    let onCancel: () -> Void
    
    @State private var isValidURL: Bool = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.red)
                
                Text("Add YouTube Video")
                    .font(.headline)
                
                Spacer()
                
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // URL Input
            VStack(alignment: .leading, spacing: 6) {
                Text("Paste YouTube URL")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    TextField("https://www.youtube.com/watch?v=...", text: $urlInput)
                        .textFieldStyle(.roundedBorder)
                        .focused($isFocused)
                        .onSubmit {
                            if isValidURL {
                                onSubmit()
                            }
                        }
                        .onChange(of: urlInput) { _, newValue in
                            isValidURL = YouTubeService.shared.isValidYouTubeURL(newValue)
                        }
                    
                    // Paste button
                    Button(action: {
                        if let clipboardString = NSPasteboard.general.string(forType: .string) {
                            urlInput = clipboardString
                        }
                    }) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.bordered)
                    .help("Paste from clipboard")
                }
                
                // Validation indicator
                if !urlInput.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: isValidURL ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(isValidURL ? .green : .orange)
                        
                        Text(isValidURL ? "Valid YouTube URL" : "Enter a valid YouTube URL")
                            .font(.caption)
                            .foregroundColor(isValidURL ? .green : .orange)
                    }
                }
            }
            
            // Supported formats hint
            Text("Supports: youtube.com/watch, youtu.be, youtube.com/shorts")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Action buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button("Add Video") {
                    onSubmit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValidURL)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(20)
        .frame(width: 400, height: 220)
        .onAppear {
            isFocused = true
            // Check if clipboard already has a YouTube URL
            if let clipboardString = NSPasteboard.general.string(forType: .string),
               YouTubeService.shared.isValidYouTubeURL(clipboardString) {
                urlInput = clipboardString
            }
        }
    }
}

// MARK: - Preview

#Preview {
    YouTubeURLInputView(
        urlInput: .constant("https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
        onSubmit: {},
        onCancel: {}
    )
}
