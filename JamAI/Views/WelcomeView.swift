//
//  WelcomeView.swift
//  JamAI
//
//  Welcome screen for creating/opening projects
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct WelcomeView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 30) {
            // Logo/Title
            VStack(spacing: 8) {
                // App logo - automatically adapts to light/dark mode
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                
                Text("Jam AI")
                    .font(.system(size: 40, weight: .bold))
                
                Text("Build your AI dream team")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .padding(.horizontal, 40)
            
            // Actions
            VStack(spacing: 16) {
                Button(action: {
                    appState.createNewProject()
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                        Text("New Project")
                            .font(.headline)
                    }
                    .frame(width: 250)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    openExistingProject()
                }) {
                    HStack {
                        Image(systemName: "folder.fill")
                            .font(.title2)
                        Text("Open Project")
                            .font(.headline)
                    }
                    .frame(width: 250)
                    .padding()
                    .background(Color.secondary.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Recent Projects - Show first 5 (industry standard for welcome screens)
            if !appState.recentProjects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Projects")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(Array(appState.recentProjects.prefix(5)), id: \.self) { url in
                                Button(action: {
                                    appState.openRecent(url: url)
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "folder")
                                            .foregroundColor(.secondary)
                                        Text(url.deletingPathExtension().lastPathComponent)
                                            .font(.body)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .frame(height: 160)  // Fits ~5 items perfectly
                    
                    // Show "More in File menu" if there are more than 5
                    if appState.recentProjects.count > 5 {
                        Text("+ \(appState.recentProjects.count - 5) more in File > Open Recent")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 40)
                .frame(maxWidth: 700)
            }
            
            Spacer()
            
            // Footer
            VStack(spacing: 4) {
                Text("Version: \(fullVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Refresh the recent projects list to ensure only valid projects are shown
            appState.refreshRecentProjects()
        }
    }
    
    private var fullVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        if let build = info?["CFBundleVersion"] as? String, !build.isEmpty {
            return "\(short) (\(build))"
        }
        return short
    }
    
    private func openExistingProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Select a Jam AI project folder (.jam)"
        
        panel.begin { [weak appState] response in
            guard let appState = appState else { return }
            guard response == .OK, let url = panel.url else { return }
            appState.openProjectInNewTab(url: url)
        }
    }
}
