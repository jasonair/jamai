import Foundation
import Combine

@MainActor
final class AIProviderManager: ObservableObject {
    static let shared = AIProviderManager()
    
    @Published private(set) var activeProvider: AIProvider
    @Published private(set) var healthStatus: AIHealthStatus = .unknown
    @Published private(set) var activeModelName: String?
    
    private(set) var client: AIClient?
    
    private var cancellables = Set<AnyCancellable>()
    
    private let providerDefaultsKey = "ai.activeProvider"
    private let localModelNameKey = "ai.localModelName"
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: providerDefaultsKey),
           let provider = AIProvider(rawValue: saved) {
            self.activeProvider = provider
        } else {
            self.activeProvider = .gemini
        }
        self.activeModelName = UserDefaults.standard.string(forKey: localModelNameKey)
    }
    
    func setProvider(_ provider: AIProvider) {
        guard provider != activeProvider else { return }
        activeProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: providerDefaultsKey)
    }
    
    func setLocalModelName(_ name: String?) {
        activeModelName = name
        if let n = name {
            UserDefaults.standard.set(n, forKey: localModelNameKey)
        } else {
            UserDefaults.standard.removeObject(forKey: localModelNameKey)
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
        case .gemini:
            return ProviderCapabilities(
                supportsVision: true,
                supportsAudio: true,
                supportsTools: false,
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
}
