import Foundation

struct LocalModelDescriptor {
    let id: String
    let displayName: String
    let fileName: String
    let downloadURL: URL
}

final class LocalModelManager: NSObject, URLSessionDownloadDelegate {
    static let shared = LocalModelManager()
    let models: [LocalModelDescriptor]
    
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 3600
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()
    
    private var activeDownloadTask: URLSessionDownloadTask?
    private var activeDownloadContinuation: CheckedContinuation<Void, Error>?
    private var activeDownloadDescriptor: LocalModelDescriptor?
    private var activeProgressHandler: ((Double) -> Void)?
    
    private override init() {
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
        super.init()
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
        activeDownloadDescriptor = descriptor
        activeProgressHandler = onProgress
        activeProgressHandler?(0.0)
        
        defer {
            activeDownloadTask = nil
            activeDownloadContinuation = nil
            activeDownloadDescriptor = nil
            activeProgressHandler = nil
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            activeDownloadContinuation = continuation
            let task = downloadSession.downloadTask(with: descriptor.downloadURL)
            activeDownloadTask = task
            task.resume()
        }
    }
    
    func deleteModel(descriptor: LocalModelDescriptor) throws {
        let url = try localFileURL(for: descriptor)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard downloadTask == activeDownloadTask else { return }
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        activeProgressHandler?(progress)
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard downloadTask == activeDownloadTask else { return }
        guard let descriptor = activeDownloadDescriptor else { return }
        
        guard let http = downloadTask.response as? HTTPURLResponse, http.statusCode == 200 else {
            let error = NSError(
                domain: "LocalModelManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Download failed"]
            )
            activeDownloadContinuation?.resume(throwing: error)
            activeDownloadContinuation = nil
            return
        }
        
        do {
            let fm = FileManager.default
            let dest = try localFileURL(for: descriptor)
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            let parent = dest.deletingLastPathComponent()
            if !fm.fileExists(atPath: parent.path) {
                try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            try fm.moveItem(at: location, to: dest)
            print("[LocalModelManager] download complete path=\(dest.path)")
            activeProgressHandler?(1.0)
            activeDownloadContinuation?.resume(returning: ())
            activeDownloadContinuation = nil
        } catch {
            activeDownloadContinuation?.resume(throwing: error)
            activeDownloadContinuation = nil
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task == activeDownloadTask else { return }
        if let error = error {
            activeDownloadContinuation?.resume(throwing: error)
            activeDownloadContinuation = nil
        }
    }
}
