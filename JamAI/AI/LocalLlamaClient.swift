import Foundation

final class LocalLlamaClient: NSObject, AIClient, URLSessionDataDelegate {
    private let baseURL: URL
    private let session: URLSession
    private var inflightTasks = [URLSessionTask]()
    private var streamingTasks = [Task<Void, Never>]()
    private let modelName: String
    
    let capabilities: ProviderCapabilities = ProviderCapabilities(
        supportsVision: false,
        supportsAudio: false,
        supportsTools: false,
        maxOutputTokens: 4096
    )
    
    init(modelName: String, baseURL: URL = URL(string: "http://127.0.0.1:11434")!) {
        self.modelName = modelName
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }
    
    func healthCheck() async -> AIHealthStatus {
        let url = baseURL.appendingPathComponent("api/version")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .serverDown
            }
        } catch {
            return .serverDown
        }
        let tagsURL = baseURL.appendingPathComponent("api/tags")
        var tagsReq = URLRequest(url: tagsURL)
        tagsReq.httpMethod = "GET"
        do {
            let (data, response) = try await session.data(for: tagsReq)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .ready
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                let exists = models.contains { dict in
                    if let name = dict["name"] as? String { return name == modelName }
                    if let model = dict["model"] as? String { return model == modelName }
                    return false
                }
                return exists ? .ready : .error("Model not installed")
            } else {
                return .ready
            }
        } catch {
            return .ready
        }
    }
    
    private func mapContext(prompt: String, systemPrompt: String?, context: [AIChatMessage]) -> [[String: String]] {
        var messages: [[String: String]] = []
        if let sys = systemPrompt, !sys.isEmpty {
            messages.append(["role": "system", "content": sys])
        }
        for m in context {
            switch m.role {
            case .user:
                messages.append(["role": "user", "content": m.content])
            case .assistant:
                messages.append(["role": "assistant", "content": m.content])
            case .system:
                messages.append(["role": "system", "content": m.content])
            }
        }
        messages.append(["role": "user", "content": prompt])
        return messages
    }
    
    func generate(
        prompt: String,
        systemPrompt: String?,
        context: [AIChatMessage]
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": modelName,
            "messages": mapContext(prompt: prompt, systemPrompt: systemPrompt, context: context),
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "LocalLlamaClient", code: 1)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "LocalLlamaClient", code: 2)
        }
        return content
    }
    
    func generateStreaming(
        prompt: String,
        systemPrompt: String?,
        context: [AIChatMessage],
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        let t = Task {
            do {
                let text = try await self.generate(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    context: context
                )
                onChunk(text)
                onComplete(.success(text))
            } catch {
                if !Task.isCancelled {
                    onComplete(.failure(error))
                }
            }
        }
        streamingTasks.append(t)
    }

    func pullModel(progress: ((Double) -> Void)? = nil) async throws {
        let url = baseURL.appendingPathComponent("api/pull")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": modelName,
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "LocalLlamaClient", code: 3)
        }
        for try await line in bytes.lines {
            if line.isEmpty { continue }
            if let data = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var prog: Double?
                if let completed = json["completed"] as? Double, let total = json["total"] as? Double, total > 0 {
                    prog = min(1, max(0, completed / total))
                } else if let completedI = json["completed"] as? Int, let totalI = json["total"] as? Int, totalI > 0 {
                    prog = min(1, max(0, Double(completedI) / Double(totalI)))
                }
                if let p = prog { progress?(p) }
                if let status = json["status"] as? String, status.lowercased().contains("success") {
                    break
                }
                if let done = json["done"] as? Bool, done == true { break }
            }
        }
    }
    
    func cancelAll() {
        inflightTasks.forEach { $0.cancel() }
        inflightTasks.removeAll()
        streamingTasks.forEach { $0.cancel() }
        streamingTasks.removeAll()
    }
}

