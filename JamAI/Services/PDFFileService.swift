//
//  PDFFileService.swift
//  JamAI
//
//  Service for uploading PDFs to Gemini File API and managing file lifecycle
//

import Foundation

/// Represents an uploaded PDF file in Gemini File API
struct GeminiFile: Codable {
    let name: String          // e.g., "files/abc123"
    let displayName: String   // Original filename
    let mimeType: String
    let sizeBytes: String
    let createTime: String
    let updateTime: String
    let expirationTime: String?
    let sha256Hash: String?
    let uri: String           // Full URI for use in requests
    let state: String         // PROCESSING, ACTIVE, FAILED
    
    var isActive: Bool {
        state == "ACTIVE"
    }
    
    var fileId: String {
        // Extract ID from "files/abc123" format
        name.replacingOccurrences(of: "files/", with: "")
    }
}

/// Error types for PDF file operations
enum PDFFileError: LocalizedError {
    case noAPIKey
    case invalidURL
    case uploadFailed(String)
    case fileNotFound
    case fileNotActive
    case fileProcessing
    case invalidResponse
    case fileTooLarge
    case unsupportedFormat
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "API key not configured"
        case .invalidURL:
            return "Invalid API URL"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .fileNotFound:
            return "File not found"
        case .fileNotActive:
            return "File is not active for use"
        case .fileProcessing:
            return "File is still being processed"
        case .invalidResponse:
            return "Invalid response from API"
        case .fileTooLarge:
            return "File exceeds maximum size (20MB)"
        case .unsupportedFormat:
            return "Unsupported file format. Only PDF and text-based documents are supported."
        }
    }
}

/// Service for managing PDF files with Gemini File API
@MainActor
class PDFFileService {
    static let shared = PDFFileService()
    
    private let session: URLSession
    private let maxFileSize: Int = 20 * 1024 * 1024 // 20MB limit
    
    private var apiKey: String? {
        ProcessInfo.processInfo.environment["GOOGLE_GEMINI_API_KEY"]
    }
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120 // Longer timeout for uploads
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Upload Files
    
    /// Upload a text file (transcript) to Gemini File API
    /// - Parameters:
    ///   - text: The text content to upload
    ///   - filename: Filename for display (should end in .txt)
    /// - Returns: The uploaded GeminiFile object
    func uploadText(text: String, filename: String) async throws -> GeminiFile {
        guard let data = text.data(using: .utf8) else {
            throw PDFFileError.uploadFailed("Failed to encode text as UTF-8")
        }
        return try await uploadFile(data: data, filename: filename, mimeType: "text/plain")
    }
    
    /// Upload a PDF file to Gemini File API
    /// - Parameters:
    ///   - data: The PDF file data
    ///   - filename: Original filename for display
    /// - Returns: The uploaded GeminiFile object
    func uploadPDF(data: Data, filename: String) async throws -> GeminiFile {
        let mimeType = inferMimeType(from: filename)
        return try await uploadFile(data: data, filename: filename, mimeType: mimeType)
    }
    
    /// Upload a file to Gemini File API with explicit MIME type
    /// - Parameters:
    ///   - data: The file data
    ///   - filename: Filename for display
    ///   - mimeType: MIME type of the file
    /// - Returns: The uploaded GeminiFile object
    func uploadFile(data: Data, filename: String, mimeType: String) async throws -> GeminiFile {
        guard let apiKey = apiKey else {
            throw PDFFileError.noAPIKey
        }
        
        // Validate file size
        guard data.count <= maxFileSize else {
            throw PDFFileError.fileTooLarge
        }
        
        // Step 1: Initiate resumable upload
        let uploadUrl = try await initiateUpload(filename: filename, mimeType: mimeType, fileSize: data.count, apiKey: apiKey)
        
        // Step 2: Upload the file data
        let file = try await uploadData(data: data, uploadUrl: uploadUrl)
        
        // Step 3: Wait for processing if needed
        if !file.isActive {
            return try await waitForProcessing(fileId: file.fileId)
        }
        
        return file
    }
    
    /// Initiate a resumable upload session
    private func initiateUpload(filename: String, mimeType: String, fileSize: Int, apiKey: String) async throws -> URL {
        let urlString = "https://generativelanguage.googleapis.com/upload/v1beta/files?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw PDFFileError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        request.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        request.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        request.setValue("\(fileSize)", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "file": [
                "display_name": filename
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let uploadUrlString = httpResponse.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let uploadUrl = URL(string: uploadUrlString) else {
            throw PDFFileError.invalidResponse
        }
        
        return uploadUrl
    }
    
    /// Upload file data to the resumable upload URL
    private func uploadData(data: Data, uploadUrl: URL) async throws -> GeminiFile {
        var request = URLRequest(url: uploadUrl)
        request.httpMethod = "POST"
        request.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        request.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        request.httpBody = data
        
        let (responseData, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            if let errorText = String(data: responseData, encoding: .utf8) {
                throw PDFFileError.uploadFailed(errorText)
            }
            throw PDFFileError.invalidResponse
        }
        
        // Parse the file response
        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let fileJson = json["file"] as? [String: Any] else {
            throw PDFFileError.invalidResponse
        }
        
        return try parseFileResponse(fileJson)
    }
    
    // MARK: - File Status
    
    /// Get the status of an uploaded file
    func getFileStatus(fileId: String) async throws -> GeminiFile {
        guard let apiKey = apiKey else {
            throw PDFFileError.noAPIKey
        }
        
        let urlString = "\(Config.geminiAPIBaseURL)/files/\(fileId)?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw PDFFileError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PDFFileError.invalidResponse
        }
        
        if httpResponse.statusCode == 404 {
            throw PDFFileError.fileNotFound
        }
        
        guard httpResponse.statusCode == 200 else {
            throw PDFFileError.invalidResponse
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PDFFileError.invalidResponse
        }
        
        return try parseFileResponse(json)
    }
    
    /// Wait for a file to finish processing
    func waitForProcessing(fileId: String, maxAttempts: Int = 30, delaySeconds: Double = 2.0) async throws -> GeminiFile {
        for attempt in 1...maxAttempts {
            let file = try await getFileStatus(fileId: fileId)
            
            switch file.state {
            case "ACTIVE":
                return file
            case "FAILED":
                throw PDFFileError.uploadFailed("File processing failed")
            case "PROCESSING":
                if attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                }
            default:
                throw PDFFileError.invalidResponse
            }
        }
        
        throw PDFFileError.fileProcessing
    }
    
    // MARK: - Delete File
    
    /// Delete a file from Gemini File API
    func deleteFile(fileId: String) async throws {
        guard let apiKey = apiKey else {
            throw PDFFileError.noAPIKey
        }
        
        let urlString = "\(Config.geminiAPIBaseURL)/files/\(fileId)?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw PDFFileError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 || httpResponse.statusCode == 204 else {
            // Ignore errors on delete - file may already be expired
            return
        }
    }
    
    // MARK: - Helpers
    
    private func parseFileResponse(_ json: [String: Any]) throws -> GeminiFile {
        guard let name = json["name"] as? String,
              let mimeType = json["mimeType"] as? String,
              let uri = json["uri"] as? String,
              let state = json["state"] as? String else {
            throw PDFFileError.invalidResponse
        }
        
        return GeminiFile(
            name: name,
            displayName: json["displayName"] as? String ?? "Unknown",
            mimeType: mimeType,
            sizeBytes: json["sizeBytes"] as? String ?? "0",
            createTime: json["createTime"] as? String ?? "",
            updateTime: json["updateTime"] as? String ?? "",
            expirationTime: json["expirationTime"] as? String,
            sha256Hash: json["sha256Hash"] as? String,
            uri: uri,
            state: state
        )
    }
    
    /// Infer an appropriate MIME type for the uploaded document based on its extension.
    /// PDFs use application/pdf. All other supported document formats are treated as
    /// text/plain so Gemini reads the raw text while preserving structure.
    private func inferMimeType(from filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        if ext == "pdf" {
            return "application/pdf"
        }
        return "text/plain"
    }
    
    // MARK: - Re-upload on Expiration
    
    /// Re-upload a PDF if the file has expired (files expire after 48 hours)
    /// Returns the new file URI if re-upload was needed, nil if file is still active
    func ensureFileActive(node: Node) async throws -> GeminiFile? {
        guard let fileId = node.pdfFileId else {
            // No file ID means we need to upload
            guard let pdfData = node.pdfData,
                  let filename = node.pdfFileName else {
                return nil
            }
            return try await uploadPDF(data: pdfData, filename: filename)
        }
        
        do {
            let file = try await getFileStatus(fileId: fileId)
            if file.isActive {
                return nil // File is still active, no re-upload needed
            }
        } catch PDFFileError.fileNotFound {
            // File expired or deleted, re-upload
        }
        
        // Re-upload the file
        guard let pdfData = node.pdfData,
              let filename = node.pdfFileName else {
            throw PDFFileError.fileNotFound
        }
        
        return try await uploadPDF(data: pdfData, filename: filename)
    }
    
    /// Re-upload a YouTube transcript if the file has expired (files expire after 48 hours)
    /// Returns the new file URI if re-upload was needed, nil if file is still active
    func ensureYouTubeFileActive(node: Node) async throws -> GeminiFile? {
        guard let fileId = node.youtubeFileId else {
            // No file ID means we need to upload
            guard let transcript = node.youtubeTranscript,
                  let title = node.youtubeTitle else {
                return nil
            }
            let filename = "\(title).txt"
            return try await uploadText(text: transcript, filename: filename)
        }
        
        do {
            let file = try await getFileStatus(fileId: fileId)
            if file.isActive {
                return nil // File is still active, no re-upload needed
            }
        } catch PDFFileError.fileNotFound {
            // File expired or deleted, re-upload
        }
        
        // Re-upload the file
        guard let transcript = node.youtubeTranscript,
              let title = node.youtubeTitle else {
            throw PDFFileError.fileNotFound
        }
        
        let filename = "\(title).txt"
        return try await uploadText(text: transcript, filename: filename)
    }
}
