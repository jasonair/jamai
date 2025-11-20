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
    @State private var customPrompt: String = ""
    @State private var localDownloadProgress: Double?
    @State private var isInstallingLocalModel = false
    @State private var localErrorMessage: String?
    @State private var hoveredSection: String?
    
    var onDismiss: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                Text("Settings")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    onDismiss?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(
                Divider()
                    .opacity(0.5),
                alignment: .bottom
            )
            
            ScrollView {
                VStack(spacing: 24) {
                    // AI Provider Section
                    SettingsSection(
                        title: "AI Provider",
                        icon: "cpu",
                        description: "Choose between local processing or cloud-based AI."
                    ) {
                        aiProviderContent
                    }
                    
                    // Appearance Section
                    SettingsSection(
                        title: "Appearance",
                        icon: "paintpalette",
                        description: "Customize how the app looks."
                    ) {
                        appearanceContent
                    }
                    
                    // Project Prompt Section
                    SettingsSection(
                        title: "Project Prompt",
                        icon: "text.quote",
                        description: "Base system instructions applied to all nodes in this project."
                    ) {
                        projectPromptContent
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 600, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            customPrompt = viewModel.project.systemPrompt
        }
    }
    
    // MARK: - Content Views
    
    private var aiProviderContent: some View {
        VStack(alignment: .leading, spacing: 16) {
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
            .labelsHidden()
            
            if aiProviderManager.activeProvider == .local {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                    
                    // Status Row
                    HStack {
                        StatusIndicator(status: aiProviderManager.healthStatus)
                        
                        Spacer()
                        
                        Button("Check Status") {
                            Task {
                                await aiProviderManager.refreshHealth()
                            }
                        }
                        .controlSize(.small)
                    }
                    
                    // License Toggle
                    Toggle(isOn: Binding(
                        get: { aiProviderManager.licenseAccepted },
                        set: { value in aiProviderManager.setLicenseAccepted(value) }
                    )) {
                        Text("I accept the DeepSeek license")
                            .font(.callout)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    
                    // Model Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Model Selection")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Picker("", selection: Binding(
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
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }
                    }
                    
                    // Actions Area
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Button {
                                startDownload()
                            } label: {
                                HStack {
                                    if isInstallingLocalModel {
                                        ProgressView()
                                            .controlSize(.small)
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "arrow.down.circle")
                                    }
                                    Text(isInstallingLocalModel ? "Downloading..." : "Download Model")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!aiProviderManager.licenseAccepted || isInstallingLocalModel)
                            .controlSize(.large)
                            
                            if isCurrentLocalModelInstalled() {
                                Button(role: .destructive) {
                                    deleteModel()
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                                .help("Delete downloaded model")
                            }
                        }
                        
                        if let progress = localDownloadProgress, isInstallingLocalModel {
                            VStack(spacing: 4) {
                                ProgressView(value: progress)
                                    .progressViewStyle(.linear)
                                HStack {
                                    Text("\(Int(progress * 100))%")
                                    Spacer()
                                    Text("Downloading model assets...")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        } else if isCurrentLocalModelInstalled() {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Model installed and ready")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let error = localErrorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(nsColor: .quaternaryLabelColor))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    private var appearanceContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $appState.appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            
            Text("This setting applies to the entire application immediately.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var projectPromptContent: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                if customPrompt.isEmpty {
                    Text("Enter system instructions...")
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        .padding(12)
                }
                
                TextEditor(text: $customPrompt)
                    .font(.body)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
            .frame(height: 140)
            .onChange(of: customPrompt) { _, newValue in
                let limited = String(newValue.prefix(2000))
                if limited != customPrompt {
                    customPrompt = limited
                }
                viewModel.project.systemPrompt = limited
            }
            
            HStack {
                Text("\(customPrompt.count)/2000")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button {
                    viewModel.save()
                    withAnimation {
                        saveStatus = "Saved"
                    }
                    
                    // Reset status after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            saveStatus = nil
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if saveStatus == "Saved" {
                            Image(systemName: "checkmark")
                        }
                        Text(saveStatus ?? "Save Changes")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(saveStatus == "Saved")
            }
        }
    }
    
    // MARK: - Logic Helpers
    
    private func startDownload() {
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
    }
    
    private func deleteModel() {
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
    }
    
    private func currentLocalDescriptor() -> LocalModelDescriptor? {
        let modelId = aiProviderManager.activeModelName ?? AIProviderManager.availableLocalModels.first
        return LocalModelManager.shared.descriptor(for: modelId)
    }
    
    private func isCurrentLocalModelInstalled() -> Bool {
        guard let descriptor = currentLocalDescriptor() else { return false }
        return LocalModelManager.shared.isModelInstalled(descriptor)
    }
}

// MARK: - Components

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let description: String?
    let content: Content
    
    init(title: String, icon: String, description: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.description = description
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let description = description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

struct StatusIndicator: View {
    let status: AIHealthStatus
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var statusColor: Color {
        switch status {
        case .ready: return .green
        case .installing, .downloading: return .blue
        case .unknown: return .gray
        default: return .red
        }
    }
    
    private var statusText: String {
        switch status {
        case .unknown: return "Unknown"
        case .ready: return "Ready"
        case .installing: return "Installing..."
        case .downloading: return "Downloading..."
        case .missingDependency: return "Engine Missing"
        case .serverDown: return "Engine Error"
        case .error: return "Error"
        }
    }
}
