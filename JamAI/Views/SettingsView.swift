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
    @State private var selectedTemplate: SystemPromptTemplate?
    @State private var customPrompt: String = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // API Configuration Section
                sectionHeader("API Configuration")
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        if showAPIKey {
                            TextField("Gemini API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Gemini API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    HStack(spacing: 12) {
                        Button("Save API Key") {
                            saveAPIKey()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Link("Get API Key", destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                            .font(.caption)
                    }
                    
                    if let status = saveStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(status.contains("Success") ? .green : .red)
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
            
                // Appearance Section
                sectionHeader("Appearance")
                VStack(alignment: .leading, spacing: 12) {
                    Text("Theme")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $viewModel.project.appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: viewModel.project.appearanceMode) { _, _ in
                        viewModel.save()
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
            
                // Customise Team Section
                sectionHeader("Customise Team")
                VStack(alignment: .leading, spacing: 12) {
                    Text("Define how AI team members interact across this project")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Select Template")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $selectedTemplate) {
                        Text("Custom").tag(nil as SystemPromptTemplate?)
                        ForEach(SystemPromptTemplate.allCases) { template in
                            Text(template.rawValue).tag(template as SystemPromptTemplate?)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedTemplate) { _, newTemplate in
                        if let template = newTemplate {
                            customPrompt = template.prompt
                            viewModel.project.systemPrompt = template.prompt
                        }
                    }
                    
                    Text("Project Prompt")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    
                    TextEditor(text: $customPrompt)
                        .frame(height: 120)
                        .font(.body)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .onChange(of: customPrompt) { _, newValue in
                            viewModel.project.systemPrompt = newValue
                            // Check if it matches a template
                            selectedTemplate = SystemPromptTemplate.allCases.first { $0.prompt == newValue }
                        }
                    
                    Button("Save Changes") {
                        viewModel.save()
                        saveStatus = "Project prompt saved"
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
            
                // Context Settings Section
                sectionHeader("Context Settings")
                VStack(alignment: .leading, spacing: 12) {
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
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                .onChange(of: viewModel.project.kTurns) { _, _ in viewModel.save() }
                .onChange(of: viewModel.project.includeSummaries) { _, _ in viewModel.save() }
                .onChange(of: viewModel.project.includeRAG) { _, _ in viewModel.save() }
                .onChange(of: viewModel.project.ragK) { _, _ in viewModel.save() }
                .onChange(of: viewModel.project.ragMaxChars) { _, _ in viewModel.save() }
            }
            .padding(20)
        }
        .frame(width: 550, height: 700)
        .onAppear {
            loadAPIKey()
            customPrompt = viewModel.project.systemPrompt
            // Check if current prompt matches a template
            selectedTemplate = SystemPromptTemplate.allCases.first { $0.prompt == viewModel.project.systemPrompt }
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
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .fontWeight(.semibold)
    }
}
