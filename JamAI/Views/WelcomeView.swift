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
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                
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
            
            Spacer()
            
            // Footer
            Text("Powered by Gemini 2.0 Flash")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
