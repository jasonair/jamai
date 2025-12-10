import Foundation
import Combine

@MainActor
final class AIProviderManager: ObservableObject {
    static let shared = AIProviderManager()
    
    @Published private(set) var activeProvider: AIProvider
    @Published private(set) var healthStatus: AIHealthStatus = .unknown
    @Published private(set) var activeModelName: String?
    @Published private(set) var licenseAccepted: Bool = false
    
    private(set) var client: AIClient?
    
    private var cancellables = Set<AnyCancellable>()
    
    private let providerDefaultsKey = "ai.activeProvider"
    private let localModelNameKey = "ai.localModelName"
    private let licenseAcceptedKey = "ai.localLicenseAccepted"
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: providerDefaultsKey),
           let provider = AIProvider(rawValue: saved) {
            self.activeProvider = provider
        } else {
            self.activeProvider = .gemini
        }
        self.activeModelName = UserDefaults.standard.string(forKey: localModelNameKey)
        self.licenseAccepted = UserDefaults.standard.bool(forKey: licenseAcceptedKey)
        if activeProvider == .local && activeModelName == nil {
            self.activeModelName = Self.availableLocalModels.first
        }
    }
    
    func setProvider(_ provider: AIProvider) {
        guard provider != activeProvider else { return }
        Task { @MainActor in
            self.activeProvider = provider
            UserDefaults.standard.set(provider.rawValue, forKey: self.providerDefaultsKey)
        }
    }
    
    func setLocalModelName(_ name: String?) {
        Task { @MainActor in
            self.activeModelName = name
            if let n = name {
                UserDefaults.standard.set(n, forKey: self.localModelNameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: self.localModelNameKey)
            }
        }
    }
    
    func setLicenseAccepted(_ accepted: Bool) {
        Task { @MainActor in
            self.licenseAccepted = accepted
            UserDefaults.standard.set(accepted, forKey: self.licenseAcceptedKey)
        }
    }
    
    func capabilities() -> ProviderCapabilities {
        switch activeProvider {
        case .local:
            return ProviderCapabilities(
                supportsVision: false,
                supportsAudio: false,
                supportsTools: false,
                maxOutputTokens: 4096
            )
        case .gemini, .geminiByok:
            return ProviderCapabilities(
                supportsVision: true,
                supportsAudio: true,
                supportsTools: false,
                maxOutputTokens: 8192
            )
        case .openai:
            return ProviderCapabilities(
                supportsVision: true,
                supportsAudio: true,
                supportsTools: true,
                maxOutputTokens: 16384
            )
        case .claude:
            return ProviderCapabilities(
                supportsVision: true,
                supportsAudio: false,
                supportsTools: true,
                maxOutputTokens: 8192
            )
        }
    }
    
    func setClient(_ client: AIClient?) {
        self.client = client
    }
    
    func refreshHealth() async {
        if let client = client {
            self.healthStatus = await client.healthCheck()
        } else {
            self.healthStatus = .unknown
        }
    }

    static let availableLocalModels: [String] = [
        "deepseek-r1:1.5b",
        "deepseek-r1:8b"
    ]
    
    func activateLocal(modelName: String?) {
        setProvider(.local)
        let name = modelName ?? activeModelName ?? Self.availableLocalModels.first
        setLocalModelName(name)
        if let finalName = activeModelName {
            self.client = LlamaCppClient(modelId: finalName)
        }
        Task { await refreshHealth() }
    }
    
    /// Activate a BYOK provider (OpenAI, Claude, or Gemini BYOK)
    func activateByokProvider(_ provider: AIProvider) {
        guard provider.isByok else { return }
        setProvider(provider)
        
        switch provider {
        case .openai:
            self.client = OpenAIClientAdapter()
        case .claude:
            self.client = ClaudeClientAdapter()
        case .geminiByok:
            self.client = GeminiByokClientAdapter()
        default:
            break
        }
        
        Task { await refreshHealth() }
    }
    
    /// Activate hosted Gemini (your API key)
    func activateHostedGemini(geminiClient: GeminiClient) {
        setProvider(.gemini)
        self.client = GeminiClientAdapter(geminiClient: geminiClient)
        Task { await refreshHealth() }
    }
    
    /// Check if a BYOK provider has a valid API key configured
    func hasApiKey(for provider: AIProvider) -> Bool {
        return KeychainService.shared.hasKey(for: provider)
    }
    
    /// Get available providers for a user's plan
    func availableProviders(for plan: UserPlan?) -> [AIProvider] {
        // Always available: local
        var providers: [AIProvider] = [.local]
        
        // Hosted Gemini only for subscription users (not lifetime)
        if let plan = plan, plan.hasHostedCloudAccess {
            providers.append(.gemini)
        }
        
        // BYOK providers always available
        providers.append(contentsOf: [.openai, .claude, .geminiByok])
        
        return providers
    }
    
    func startLocalModelInstall(onProgress: ((Double) -> Void)? = nil) async {
        guard activeProvider == .local else { return }
        guard licenseAccepted else {
            self.healthStatus = .error("License not accepted")
            return
        }
        self.healthStatus = .installing
        do {
            let modelId = activeModelName ?? Self.availableLocalModels.first
            guard let descriptor = LocalModelManager.shared.descriptor(for: modelId) else {
                self.healthStatus = .error("Unknown model")
                return
            }
            try await LocalModelManager.shared.downloadModel(descriptor: descriptor) { p in
                Task { @MainActor in
                    self.healthStatus = .downloading(progress: p)
                    onProgress?(p)
                }
            }
            if let finalName = activeModelName {
                self.client = LlamaCppClient(modelId: finalName)
            }
            self.healthStatus = .ready
        } catch {
            self.healthStatus = .error("Download failed")
        }
    }
}

