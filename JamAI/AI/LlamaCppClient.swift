import Foundation

final class LlamaCppClient: AIClient {
    private let modelId: String
    private var currentProcess: Process?
    private var streamingTasks = [Task<Void, Never>]()
    
    let capabilities: ProviderCapabilities = ProviderCapabilities(
        supportsVision: false,
        supportsAudio: false,
        supportsTools: false,
        maxOutputTokens: 4096
    )
    
    init(modelId: String) {
        self.modelId = modelId
    }
    
    private func binaryURL() -> URL? {
        if let url = Bundle.main.url(forResource: "llama-cli-static", withExtension: nil) {
            return url
        }
        return Bundle.main.url(forResource: "llama-cli", withExtension: nil)
    }
    
    func healthCheck() async -> AIHealthStatus {
        #if !arch(arm64)
        return .missingDependency
        #else
        guard let descriptor = LocalModelManager.shared.descriptor(for: modelId) else {
            return .error("Unknown model")
        }
        guard LocalModelManager.shared.isModelInstalled(descriptor) else {
            return .error("Model not installed")
        }
        guard binaryURL() != nil else {
            return .missingDependency
        }
        return .ready
        #endif
    }
    
    private func buildPrompt(prompt: String, systemPrompt: String?, context: [AIChatMessage]) -> String {
        var systemText = systemPrompt ?? ""
        var parts: [String] = []
        for msg in context {
            switch msg.role {
            case .system:
                if !msg.content.isEmpty {
                    if !systemText.isEmpty {
                        systemText += "\n\n"
                    }
                    systemText += msg.content
                }
            case .user:
                parts.append("<｜User｜>" + msg.content)
            case .assistant:
                parts.append("<｜Assistant｜>" + msg.content)
            }
        }
        parts.append("<｜User｜>" + prompt)
        let prefix = "<｜begin▁of▁sentence｜>" + systemText
        let conversation = parts.joined()
        return prefix + conversation + "<｜Assistant｜>"
    }
    
    private func runCli(prompt: String) throws -> String {
        guard let descriptor = LocalModelManager.shared.descriptor(for: modelId) else {
            throw NSError(domain: "LlamaCppClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown model"])
        }
        guard let binary = binaryURL() else {
            throw NSError(domain: "LlamaCppClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "Local engine not available"])
        }
        let modelURL = try LocalModelManager.shared.localFileURL(for: descriptor)
        let process = Process()
        process.executableURL = binary
        let threads = 2
        process.arguments = [
            "--model", modelURL.path,
            "-t", String(threads),
            "--temp", "0.75",
            "--top-p", "0.95",
            "--repeat-penalty", "1.1",
            "-n", "2048",
            "-no-cnv",
            "-p", prompt
        ]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        currentProcess = process
        do {
            try process.run()
        } catch {
            currentProcess = nil
            throw error
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        currentProcess = nil
        if process.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: errData, encoding: .utf8) ?? "Local engine failed"
            throw NSError(domain: "LlamaCppClient", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: msg])
        }
        let text = String(data: outData, encoding: .utf8) ?? ""
        var output = text
        if output.hasPrefix(prompt) {
            output = String(output.dropFirst(prompt.count))
        } else if let range = output.range(of: prompt) {
            output.removeSubrange(range)
        }
        if let thinkStart = output.range(of: "<think>") {
            if let thinkEnd = output.range(of: "</think>", range: thinkStart.upperBound..<output.endIndex) {
                output.removeSubrange(output.startIndex..<thinkEnd.upperBound)
            } else {
                output.removeSubrange(thinkStart.lowerBound..<output.endIndex)
            }
        }
        if let endRange = output.range(of: "[end of text]") {
            output = String(output[..<endRange.lowerBound])
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func generate(
        prompt: String,
        systemPrompt: String?,
        context: [AIChatMessage]
    ) async throws -> String {
        let combinedPrompt = buildPrompt(prompt: prompt, systemPrompt: systemPrompt, context: context)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                do {
                    let result = try self.runCli(prompt: combinedPrompt)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func generateStreaming(
        prompt: String,
        systemPrompt: String?,
        context: [AIChatMessage],
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        let t = Task { [weak self] in
            guard let self = self else { return }
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
    
    func cancelAll() {
        currentProcess?.terminate()
        currentProcess = nil
        streamingTasks.forEach { $0.cancel() }
        streamingTasks.removeAll()
    }
}
