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
                                        Text("Downloading...")
                                    } else {
                                        Text("Download Local Model")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isInstallingLocalModel)
                                
                                if let progress = localDownloadProgress, isInstallingLocalModel {
                                    ProgressView(value: progress)
                                        .frame(width: 160)
                                    Text("\(Int(progress * 100))%")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else if isCurrentLocalModelInstalled() {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Model downloaded")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if isCurrentLocalModelInstalled() {
                                Button(role: .destructive) {
                                    do {
                                        if let descriptor = currentLocalDescriptor() {
                                            try LocalModelManager.shared.deleteModel(descriptor: descriptor)
                                        }
                                        localDownloadProgress = nil
                                        Task {
                                            await aiProviderManager.refreshHealth()
                                        }
                                    } catch {
                                        localErrorMessage = error.localizedDescription
                                    }
                                } label: {
                                    Text("Delete Downloaded Model")
                                }
                                .buttonStyle(.bordered)
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

                // Project Prompt Section (with character limit)
                sectionHeader("Project Prompt")
                VStack(alignment: .leading, spacing: 12) {
                    Text("Base system instructions applied to all nodes in this project.")
                        .font(.caption)
                        .foregroundColor(.secondary)

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
                            // Enforce 2000-character limit to keep token usage reasonable
                            let limited = String(newValue.prefix(2000))
                            if limited != customPrompt {
                                customPrompt = limited
                            }
                            viewModel.project.systemPrompt = limited
                        }

                    HStack {
                        Text("\(customPrompt.count)/2000 characters")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
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
            }
            .padding(20)
            }
        }
        .frame(width: 550, height: 700)
        .onAppear {
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

    private func currentLocalDescriptor() -> LocalModelDescriptor? {
        let modelId = aiProviderManager.activeModelName ?? AIProviderManager.availableLocalModels.first
        return LocalModelManager.shared.descriptor(for: modelId)
    }
    
    private func isCurrentLocalModelInstalled() -> Bool {
        guard let descriptor = currentLocalDescriptor() else { return false }
        return LocalModelManager.shared.isModelInstalled(descriptor)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .fontWeight(.semibold)
    }
}