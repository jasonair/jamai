//
//  PDFFileService.swift
//  JamAI
//
//  Service for uploading PDFs to Gemini File API and managing file lifecycle
//  Uses Cloud Functions to proxy requests with server-side API key
//

import Foundation
import FirebaseAuth

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
    case notAuthenticated
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
        case .notAuthenticated:
            return "Please sign in to upload files"
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

/// Service for managing PDF files with Gemini File API via Cloud Functions
@MainActor
class PDFFileService {
    static let shared = PDFFileService()
    
    private let session: URLSession
    private let maxFileSize: Int = 20 * 1024 * 1024 // 20MB limit
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120 // Longer timeout for uploads
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
    
    /// Get Firebase ID token for authentication
    private func getAuthToken() async throws -> String {
        guard let currentUser = FirebaseAuthService.shared.currentUser else {
            throw PDFFileError.notAuthenticated
        }
        return try await currentUser.getIDToken()
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
    
    /// Upload a file to Gemini File API via Cloud Function
    /// - Parameters:
    ///   - data: The file data
    ///   - filename: Filename for display
    ///   - mimeType: MIME type of the file
    /// - Returns: The uploaded GeminiFile object
    func uploadFile(data: Data, filename: String, mimeType: String) async throws -> GeminiFile {
        // Validate file size
        guard data.count <= maxFileSize else {
            throw PDFFileError.fileTooLarge
        }
        
        print("📤 [PDFFileService] Getting auth token...")
        let token = try await getAuthToken()
        print("📤 [PDFFileService] Got auth token, preparing request to: \(Config.geminiFileUploadURL)")
        
        guard let url = URL(string: Config.geminiFileUploadURL) else {
            throw PDFFileError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        // Send file as base64 encoded data
        let payload: [String: Any] = [
            "filename": filename,
            "mimeType": mimeType,
            "data": data.base64EncodedString()
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        print("📤 [PDFFileService] Sending request (payload size: \(request.httpBody?.count ?? 0) bytes)...")
        let (responseData, response) = try await session.data(for: request)
        print("📤 [PDFFileService] Got response")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PDFFileError.invalidResponse
        }
        
        print("📤 [PDFFileService] HTTP status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let responseText = String(data: responseData, encoding: .utf8) ?? "no body"
            print("❌ [PDFFileService] Error response: \(responseText)")
            if let errorJson = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let errorMsg = errorJson["error"] as? String {
                throw PDFFileError.uploadFailed(errorMsg)
            }
            throw PDFFileError.uploadFailed("HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let ok = json["ok"] as? Bool, ok,
              let fileJson = json["file"] as? [String: Any] else {
            let responseText = String(data: responseData, encoding: .utf8) ?? "no body"
            print("❌ [PDFFileService] Invalid response format: \(responseText)")
            throw PDFFileError.invalidResponse
        }
        
        print("📤 [PDFFileService] Upload successful, parsing file response...")
        let file = try parseFileResponse(fileJson)
        
        // Wait for processing if needed
        if !file.isActive {
            print("📤 [PDFFileService] File is processing, waiting...")
            return try await waitForProcessing(fileId: file.fileId)
        }
        
        print("📤 [PDFFileService] File is active: \(file.uri)")
        return file
    }
    
    // MARK: - File Status
    
    /// Get the status of an uploaded file via Cloud Function
    func getFileStatus(fileId: String) async throws -> GeminiFile {
        let token = try await getAuthToken()
        
        guard let url = URL(string: Config.geminiFileStatusURL) else {
            throw PDFFileError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let payload: [String: Any] = ["fileId": fileId]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
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
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = json["ok"] as? Bool, ok,
              let fileJson = json["file"] as? [String: Any] else {
            throw PDFFileError.invalidResponse
        }
        
        return try parseFileResponse(fileJson)
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
    /// Note: Files auto-expire after 48 hours, so deletion is optional
    func deleteFile(fileId: String) async throws {
        // Files auto-expire after 48 hours; explicit deletion not implemented via Cloud Function
        // This is intentionally a no-op to avoid requiring an additional Cloud Function endpoint
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
