//
//  SettingsView.swift
//  JamAI
//
//  Settings panel for API keys, appearance, and project configuration
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: CanvasViewModel
    @State private var apiKey: String = ""
    @State private var showAPIKey = false
    @State private var saveStatus: String?
    
    var body: some View {
        Form {
            Section("API Configuration") {
                HStack {
                    if showAPIKey {
                        TextField("Gemini API Key", text: $apiKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    } else {
                        SecureField("Gemini API Key", text: $apiKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    Button(action: { showAPIKey.toggle() }) {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                    }
                }
                
                Button("Save API Key") {
                    saveAPIKey()
                }
                
                if let status = saveStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(status.contains("Success") ? .green : .red)
                }
                
                Link("Get API Key", destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                    .font(.caption)
            }
            
            Section("Appearance") {
                Picker("Theme", selection: $viewModel.project.appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: viewModel.project.appearanceMode) {
                    viewModel.save()
                }
            }
            
            Section("System Prompt") {
                TextEditor(text: $viewModel.project.systemPrompt)
                    .frame(height: 100)
                    .font(.body)
                
                Button("Save System Prompt") {
                    viewModel.save()
                    saveStatus = "System prompt saved"
                }
            }
            
            Section("Context Settings") {
                Stepper("K-Turns: \(viewModel.project.kTurns)", value: $viewModel.project.kTurns, in: 1...50)
                
                Toggle("Include Summaries", isOn: $viewModel.project.includeSummaries)
                
                Toggle("Include RAG", isOn: $viewModel.project.includeRAG)
                
                if viewModel.project.includeRAG {
                    Stepper("RAG K: \(viewModel.project.ragK)", value: $viewModel.project.ragK, in: 1...20)
                    
                    Stepper("RAG Max Chars: \(viewModel.project.ragMaxChars)", 
                           value: $viewModel.project.ragMaxChars, 
                           in: 500...5000, 
                           step: 500)
                }
            }
            .onChange(of: viewModel.project.kTurns) { viewModel.save() }
            .onChange(of: viewModel.project.includeSummaries) { viewModel.save() }
            .onChange(of: viewModel.project.includeRAG) { viewModel.save() }
            .onChange(of: viewModel.project.ragK) { viewModel.save() }
            .onChange(of: viewModel.project.ragMaxChars) { viewModel.save() }
        }
        .padding()
        .frame(width: 500, height: 600)
        .onAppear {
            loadAPIKey()
        }
    }
    
    private func loadAPIKey() {
        if let key = try? KeychainHelper.retrieve(forKey: Config.geminiAPIKeyIdentifier) {
            apiKey = key
        }
    }
    
    private func saveAPIKey() {
        do {
            try viewModel.geminiClient.setAPIKey(apiKey)
            saveStatus = "Success! API key saved securely."
        } catch {
            saveStatus = "Error: \(error.localizedDescription)"
        }
    }
}
