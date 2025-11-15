import Foundation

struct LocalModelDescriptor {
    let id: String
    let displayName: String
    let fileName: String
    let downloadURL: URL
}

final class LocalModelManager {
    static let shared = LocalModelManager()
    let models: [LocalModelDescriptor]
    
    private init() {
        models = [
            LocalModelDescriptor(
                id: "deepseek-r1:1.5b",
                displayName: "DeepSeek-R1 1.5B Q4_K_M",
                fileName: "DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf",
                downloadURL: URL(string: "https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf")!
            ),
            LocalModelDescriptor(
                id: "deepseek-r1:8b",
                displayName: "DeepSeek-R1 8B Q4_K_M",
                fileName: "DeepSeek-R1-Distill-Llama-8B-Q4_K_M.gguf",
                downloadURL: URL(string: "https://huggingface.co/bartowski/DeepSeek-R1-Distill-Llama-8B-GGUF/resolve/main/DeepSeek-R1-Distill-Llama-8B-Q4_K_M.gguf")!
            )
        ]
    }
    
    func descriptor(for id: String?) -> LocalModelDescriptor? {
        guard let id = id else { return nil }
        return models.first { $0.id == id }
    }
    
    private func modelsDirectory() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("JamAI").appendingPathComponent("Models")
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        print("[LocalModelManager] modelsDirectory=\(dir.path)")
        return dir
    }
    
    func localFileURL(for descriptor: LocalModelDescriptor) throws -> URL {
        let dir = try modelsDirectory()
        return dir.appendingPathComponent(descriptor.fileName)
    }
    
    func isModelInstalled(_ descriptor: LocalModelDescriptor) -> Bool {
        guard let url = try? localFileURL(for: descriptor) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    func downloadModel(descriptor: LocalModelDescriptor, onProgress: ((Double) -> Void)? = nil) async throws {
        onProgress?(0.0)
        let (tempURL, response) = try await URLSession.shared.download(from: descriptor.downloadURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "LocalModelManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Download failed"])
        }
        let fm = FileManager.default
        let dest = try localFileURL(for: descriptor)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        let parent = dest.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try fm.moveItem(at: tempURL, to: dest)
        print("[LocalModelManager] download complete path=\(dest.path)")
        onProgress?(1.0)
    }
}
