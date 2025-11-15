//
//  SettingsView.swift
//  JamAI
//
//  Settings panel for API keys, appearance, and project configuration
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var viewModel: CanvasViewModel
    @ObservedObject var appState: AppState
    @ObservedObject private var aiProviderManager = AIProviderManager.shared
    @State private var apiKey: String = ""
    @State private var showAPIKey = false
    @State private var saveStatus: String?
    @State private var selectedTemplate: SystemPromptTemplate?
    @State private var customPrompt: String = ""
    @State private var localDownloadProgress: Double?
    @State private var isInstallingLocalModel = false
    @State private var localErrorMessage: String?
    var onDismiss: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Close button bar
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button(action: {
                    onDismiss?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("AI Provider")
                VStack(alignment: .leading, spacing: 12) {
                    Picker("", selection: Binding(
                        get: { aiProviderManager.activeProvider },
                        set: { provider in
                            switch provider {
                            case .local:
                                aiProviderManager.activateLocal(modelName: aiProviderManager.activeModelName)
                            case .gemini:
                                aiProviderManager.setProvider(.gemini)
                                aiProviderManager.setClient(GeminiClientAdapter(geminiClient: viewModel.geminiClient))
                                Task {
                                    await aiProviderManager.refreshHealth()
                                }
                            }
                        }
                    )) {
                        Text("Local (Free)").tag(AIProvider.local)
                        Text("Gemini (Cloud)").tag(AIProvider.gemini)
                    }
                    .pickerStyle(.segmented)
                    
                    if aiProviderManager.activeProvider == .local {
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Check Status") {
                                Task {
                                    await aiProviderManager.refreshHealth()
                                }
                            }
                            .buttonStyle(.bordered)
                            
                            Toggle("I accept the DeepSeek license", isOn: Binding(
                                get: { aiProviderManager.licenseAccepted },
                                set: { value in
                                    aiProviderManager.setLicenseAccepted(value)
                                }
                            ))
                            
                            Picker("Local model", selection: Binding(
                                get: { aiProviderManager.activeModelName ?? AIProviderManager.availableLocalModels.first ?? "deepseek-r1:1.5b" },
                                set: { name in
                                    aiProviderManager.setLocalModelName(name)
                                    aiProviderManager.activateLocal(modelName: name)
                                }
                            )) {
                                ForEach(AIProviderManager.availableLocalModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            
                            HStack(spacing: 8) {
                                Button {
                                    guard aiProviderManager.licenseAccepted else { return }
                                    isInstallingLocalModel = true
                                    localErrorMessage = nil
                                    localDownloadProgress = 0
                                    Task {
                                        await aiProviderManager.startLocalModelInstall { progress in
                                            localDownloadProgress = progress
                                        }
                                        isInstallingLocalModel = false
                                        switch aiProviderManager.healthStatus {
                                        case .error(let message):
                                            localErrorMessage = message
                                        default:
                                            break
                                        }
                                    }
                                } label: {
                                    if isInstallingLocalModel {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Text("Download Local Model")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                
                                if let progress = localDownloadProgress {
                                    Text("\(Int(progress * 100))%")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Text(localStatusText())
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let error = localErrorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
            
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
                    Text("Theme (applies to entire app)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $appState.appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
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
        }
        .frame(width: 550, height: 700)
        .onAppear {
            loadAPIKey()
            customPrompt = viewModel.project.systemPrompt
            // Check if current prompt matches a template
            selectedTemplate = SystemPromptTemplate.allCases.first { $0.prompt == viewModel.project.systemPrompt }
        }
    }
    
    private func localStatusText() -> String {
        switch aiProviderManager.healthStatus {
        case .unknown:
            return "Status: Unknown"
        case .ready:
            return "Status: Ready"
        case .installing:
            return "Status: Installing"
        case .downloading(let progress):
            let percent = Int(progress * 100)
            return "Status: Downloading \(percent)%"
        case .missingDependency:
            return "Status: Local engine not available"
        case .serverDown:
            return "Status: Local engine error"
        case .error(let message):
            return "Status: \(message)"
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
