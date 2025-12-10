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
    @ObservedObject private var dataService = FirebaseDataService.shared
    
    @State private var saveStatus: String?
    @State private var customPrompt: String = ""
    @State private var localDownloadProgress: Double?
    @State private var isInstallingLocalModel = false
    @State private var localErrorMessage: String?
    @State private var hoveredSection: String?
    
    // BYOK API key inputs
    @State private var openaiApiKey: String = ""
    @State private var claudeApiKey: String = ""
    @State private var geminiByokApiKey: String = ""
    @State private var showingUpgradeAlert = false
    @State private var apiKeySaveStatus: String?
    
    // BYOK configuration popover
    @State private var showingApiKeyPopover = false
    @State private var pendingByokProvider: AIProvider?
    @State private var popoverApiKey: String = ""
    @State private var popoverKeyError: String?
    
    var onDismiss: (() -> Void)?
    
    /// Check if user has a lifetime plan
    private var isLifetimeUser: Bool {
        dataService.userAccount?.plan.isLifetimeDeal ?? false
    }
    
    /// Current user plan
    private var userPlan: UserPlan? {
        dataService.userAccount?.plan
    }
    
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
                    
                    // API Keys Section (for BYOK)
                    SettingsSection(
                        title: "API Keys",
                        icon: "key.fill",
                        description: "Configure your own API keys for cloud AI providers."
                    ) {
                        apiKeysContent
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
            loadApiKeys()
        }
        .alert("Upgrade Required", isPresented: $showingUpgradeAlert) {
            Button("View Plans") {
                if let url = URL(string: "https://usejamai.com/account") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cloud AI with our hosted Gemini is only available for subscription plans. Upgrade to Pro or Teams to access this feature, or use your own API key with BYOK providers.")
        }
        .overlay {
            if showingApiKeyPopover {
                ApiKeyConfigOverlay(
                    provider: pendingByokProvider ?? .openai,
                    apiKey: $popoverApiKey,
                    errorMessage: $popoverKeyError,
                    onConfirm: confirmByokSelection,
                    onCancel: {
                        showingApiKeyPopover = false
                        pendingByokProvider = nil
                        popoverApiKey = ""
                        popoverKeyError = nil
                    }
                )
            }
        }
    }
    
    // MARK: - Load/Save API Keys
    
    private func loadApiKeys() {
        openaiApiKey = KeychainService.shared.getKey(for: .openai) ?? ""
        claudeApiKey = KeychainService.shared.getKey(for: .claude) ?? ""
        geminiByokApiKey = KeychainService.shared.getKey(for: .geminiByok) ?? ""
    }
    
    private func saveApiKey(_ key: String, for provider: AIProvider) {
        do {
            if key.isEmpty {
                try KeychainService.shared.deleteKey(for: provider)
            } else {
                try KeychainService.shared.saveKey(key, for: provider)
            }
            withAnimation {
                apiKeySaveStatus = "Saved"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    apiKeySaveStatus = nil
                }
            }
            // Refresh health if this is the active provider
            if aiProviderManager.activeProvider == provider {
                Task { await aiProviderManager.refreshHealth() }
            }
        } catch {
            print("Failed to save API key: \(error)")
        }
    }
    
    // MARK: - Content Views
    
    private var aiProviderContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Provider selection list
            VStack(spacing: 8) {
                ForEach(AIProvider.allCases, id: \.self) { provider in
                    ProviderRow(
                        provider: provider,
                        isSelected: aiProviderManager.activeProvider == provider,
                        isDisabled: provider == .gemini && isLifetimeUser,
                        hasApiKey: provider.isByok ? aiProviderManager.hasApiKey(for: provider) : true,
                        onSelect: {
                            selectProvider(provider)
                        }
                    )
                }
            }
            
            // Status indicator for active provider
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
            
            // Local model specific controls
            if aiProviderManager.activeProvider == .local {
                localModelControls
            }
        }
    }
    
    private func selectProvider(_ provider: AIProvider) {
        // Check if trying to select hosted Gemini as lifetime user
        if provider == .gemini && isLifetimeUser {
            showingUpgradeAlert = true
            return
        }
        
        // For BYOK providers, check if API key exists first
        if provider.isByok && !aiProviderManager.hasApiKey(for: provider) {
            // Show popover to enter API key
            pendingByokProvider = provider
            popoverApiKey = ""
            popoverKeyError = nil
            showingApiKeyPopover = true
            return
        }
        
        activateProvider(provider)
    }
    
    private func activateProvider(_ provider: AIProvider) {
        switch provider {
        case .local:
            aiProviderManager.activateLocal(modelName: aiProviderManager.activeModelName)
        case .gemini:
            aiProviderManager.activateHostedGemini(geminiClient: viewModel.geminiClient)
        case .openai, .claude, .geminiByok:
            aiProviderManager.activateByokProvider(provider)
        }
    }
    
    private func confirmByokSelection() {
        guard let provider = pendingByokProvider else { return }
        
        // Validate key is not empty
        let trimmedKey = popoverApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            popoverKeyError = "Please enter an API key"
            return
        }
        
        // Basic format validation
        if provider == .openai && !trimmedKey.hasPrefix("sk-") {
            popoverKeyError = "OpenAI keys start with 'sk-'"
            return
        }
        
        // Save the key
        do {
            try KeychainService.shared.saveKey(trimmedKey, for: provider)
            
            // Update the corresponding text field
            switch provider {
            case .openai: openaiApiKey = trimmedKey
            case .claude: claudeApiKey = trimmedKey
            case .geminiByok: geminiByokApiKey = trimmedKey
            default: break
            }
            
            // Activate the provider
            activateProvider(provider)
            
            // Close popover
            showingApiKeyPopover = false
            pendingByokProvider = nil
            popoverApiKey = ""
            popoverKeyError = nil
        } catch {
            popoverKeyError = "Failed to save API key"
        }
    }
    
    private var localModelControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
            
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
    
    // MARK: - API Keys Content
    
    private var apiKeysContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // OpenAI
            ApiKeyRow(
                provider: .openai,
                apiKey: $openaiApiKey,
                onSave: { saveApiKey(openaiApiKey, for: .openai) }
            )
            
            Divider()
            
            // Claude
            ApiKeyRow(
                provider: .claude,
                apiKey: $claudeApiKey,
                onSave: { saveApiKey(claudeApiKey, for: .claude) }
            )
            
            Divider()
            
            // Gemini BYOK
            ApiKeyRow(
                provider: .geminiByok,
                apiKey: $geminiByokApiKey,
                onSave: { saveApiKey(geminiByokApiKey, for: .geminiByok) }
            )
            
            if let status = apiKeySaveStatus {
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(status)
                            .foregroundColor(.green)
                    }
                    .font(.caption)
                }
            }
            
            // Help text
            VStack(alignment: .leading, spacing: 4) {
                Text("Get your API keys:")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    Link("OpenAI", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    Link("Anthropic", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    Link("Google AI", destination: URL(string: "https://aistudio.google.com/apikey")!)
                }
                .font(.caption)
            }
            .padding(.top, 8)
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

// MARK: - Provider Row

struct ProviderRow: View {
    let provider: AIProvider
    let isSelected: Bool
    let isDisabled: Bool
    let hasApiKey: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                
                // Provider icon
                Image(systemName: providerIcon)
                    .font(.system(size: 16))
                    .foregroundColor(iconColor)
                    .frame(width: 24)
                
                // Provider info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.displayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isDisabled ? .secondary : .primary)
                        
                        if provider.isByok {
                            Text("BYOK")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.8))
                                .cornerRadius(4)
                        }
                        
                        if isDisabled {
                            Text("Subscription Only")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(provider.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // API key status for BYOK providers
                if provider.isByok {
                    if hasApiKey {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    } else {
                        Text("Configure")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(isDisabled ? 0.6 : 1.0)
    }
    
    private var providerIcon: String {
        switch provider {
        case .local: return "desktopcomputer"
        case .gemini, .geminiByok: return "sparkles"
        case .openai: return "brain"
        case .claude: return "cpu"
        }
    }
    
    private var iconColor: Color {
        switch provider {
        case .local: return .green
        case .gemini: return .blue
        case .geminiByok: return .purple
        case .openai: return .teal
        case .claude: return .orange
        }
    }
}

// MARK: - API Key Row

struct ApiKeyRow: View {
    let provider: AIProvider
    @Binding var apiKey: String
    let onSave: () -> Void
    
    @State private var isSecure = true
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: providerIcon)
                    .foregroundColor(iconColor)
                Text(provider.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if !apiKey.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            
            // Input field
            HStack(spacing: 8) {
                Group {
                    if isSecure {
                        SecureField("Enter API key...", text: $apiKey)
                    } else {
                        TextField("Enter API key...", text: $apiKey)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .focused($isFocused)
                .onSubmit {
                    onSave()
                }
                
                Button(action: { isSecure.toggle() }) {
                    Image(systemName: isSecure ? "eye" : "eye.slash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(isSecure ? "Show API key" : "Hide API key")
                
                Button(action: onSave) {
                    Text("Save")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isFocused ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    private var providerIcon: String {
        switch provider {
        case .openai: return "brain"
        case .claude: return "cpu"
        case .geminiByok: return "sparkles"
        default: return "key"
        }
    }
    
    private var iconColor: Color {
        switch provider {
        case .openai: return .teal
        case .claude: return .orange
        case .geminiByok: return .purple
        default: return .secondary
        }
    }
}

// MARK: - API Key Configuration Overlay

struct ApiKeyConfigOverlay: View {
    let provider: AIProvider
    @Binding var apiKey: String
    @Binding var errorMessage: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @State private var isSecure = true
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }
            
            // Modal card
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: providerIcon)
                        .font(.system(size: 24))
                        .foregroundColor(iconColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Configure \(provider.displayName)")
                            .font(.headline)
                        Text("Enter your API key to use this provider")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
                
                Divider()
                
                // Content
                VStack(alignment: .leading, spacing: 16) {
                    Text(provider.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // API Key input
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Key")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            Group {
                                if isSecure {
                                    SecureField("Paste your API key here...", text: $apiKey)
                                } else {
                                    TextField("Paste your API key here...", text: $apiKey)
                                }
                            }
                            .textFieldStyle(.plain)
                            .font(.system(.body, design: .monospaced))
                            .focused($isFocused)
                            .onSubmit {
                                onConfirm()
                            }
                            
                            Button {
                                isSecure.toggle()
                            } label: {
                                Image(systemName: isSecure ? "eye" : "eye.slash")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(errorMessage != nil ? Color.red : (isFocused ? Color.accentColor : Color.secondary.opacity(0.2)), lineWidth: 1)
                        )
                        
                        if let error = errorMessage {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text(error)
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }
                    }
                    
                    // Help link
                    HStack {
                        Text("Don't have a key?")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button {
                            openAPIKeyURL()
                        } label: {
                            Text("Get one here →")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                
                Divider()
                
                // Actions
                HStack {
                    Button {
                        onCancel()
                    } label: {
                        Text("Cancel")
                            .frame(minWidth: 80)
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button {
                        onConfirm()
                    } label: {
                        Text("Save & Activate")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .frame(width: 420)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            .onTapGesture { } // Prevent tap-through to background
        }
        .onAppear {
            isFocused = true
        }
    }
    
    private func openAPIKeyURL() {
        let urlString: String
        switch provider {
        case .openai:
            urlString = "https://platform.openai.com/api-keys"
        case .claude:
            urlString = "https://console.anthropic.com/settings/keys"
        case .geminiByok:
            urlString = "https://aistudio.google.com/apikey"
        default:
            urlString = "https://usejamai.com"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private var providerIcon: String {
        switch provider {
        case .openai: return "brain"
        case .claude: return "cpu"
        case .geminiByok: return "sparkles"
        default: return "key"
        }
    }
    
    private var iconColor: Color {
        switch provider {
        case .openai: return .teal
        case .claude: return .orange
        case .geminiByok: return .purple
        default: return .secondary
        }
    }
}
