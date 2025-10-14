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
                // Custom logo if available, otherwise fallback to SF Symbol
                if let logo = NSImage(named: "AppLogo") {
                    Image(nsImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                } else {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)
                }
                
                Text("JamAI")
                    .font(.system(size: 40, weight: .bold))
                
                Text("Visual AI Thinking Canvas")
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
            
            // Recent Projects
            if !appState.recentProjects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recent Projects")
                            .font(.headline)
                        Text("(\(appState.recentProjects.count))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                    
                    VStack(spacing: 4) {
                        ForEach(appState.recentProjects, id: \.self) { url in
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
                                    Text(url.deletingPathExtension().path)
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 40)
                .frame(maxWidth: 700)
            }
            
            Spacer()
            
            // Footer
            VStack(spacing: 4) {
                Text("v0.0.1")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                
                Text("Powered by Gemini 2.0 Flash")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            print("👁️ WelcomeView appeared: \(appState.recentProjects.count) recent projects")
            // Refresh the recent projects list to ensure only valid projects are shown
            appState.refreshRecentProjects()
        }
    }
    
    private func openExistingProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Select a JamAI project folder (.jam)"
        
        panel.begin { [weak appState] response in
            guard let appState = appState else { return }
            guard response == .OK, let url = panel.url else { return }
            appState.openProject(url: url)
        }
    }
}
