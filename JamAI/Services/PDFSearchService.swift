//
//  PDFSearchService.swift
//  JamAI
//
//  Service for searching PDF content using Gemini File Search tool
//

import Foundation

/// Result from a PDF file search query
struct PDFSearchResult: Codable {
    let query: String
    let answer: String
    let citations: [PDFCitation]
}

/// Citation from a PDF document
struct PDFCitation: Codable {
    let fileName: String
    let pageNumber: Int?
    let snippet: String
}

/// Error types for PDF search operations
enum PDFSearchError: LocalizedError {
    case noAPIKey
    case invalidURL
    case searchFailed(String)
    case invalidResponse
    case noFilesProvided
    case fileNotActive
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "API key not configured"
        case .invalidURL:
            return "Invalid API URL"
        case .searchFailed(let message):
            return "Search failed: \(message)"
        case .invalidResponse:
            return "Invalid response from API"
        case .noFilesProvided:
            return "No PDF files provided for search"
        case .fileNotActive:
            return "One or more PDF files are not active"
        }
    }
}

/// Service for searching PDF content using Gemini File Search tool
@MainActor
class PDFSearchService {
    static let shared = PDFSearchService()
    
    private let session: URLSession
    private let pdfFileService = PDFFileService.shared
    
    private var apiKey: String? {
        ProcessInfo.processInfo.environment["GOOGLE_GEMINI_API_KEY"]
    }
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Search PDFs
    
    /// Search across PDF files using Gemini File Search tool
    /// - Parameters:
    ///   - query: The search query
    ///   - pdfNodes: PDF nodes to search within
    /// - Returns: Search result with answer and citations
    func searchPDFs(query: String, pdfNodes: [Node]) async throws -> PDFSearchResult {
        guard let apiKey = apiKey else {
            throw PDFSearchError.noAPIKey
        }
        
        // Filter to only PDF nodes with file URIs
        let validPdfNodes = pdfNodes.filter { $0.type == .pdf && $0.pdfFileUri != nil }
        guard !validPdfNodes.isEmpty else {
            throw PDFSearchError.noFilesProvided
        }
        
        // Ensure all files are active (re-upload if expired)
        var activeFiles: [(uri: String, mimeType: String, displayName: String)] = []
        for node in validPdfNodes {
            let displayName = node.pdfFileName ?? "Document"
            if let existingUri = node.pdfFileUri {
                // Check if file is still active
                do {
                    if let fileId = node.pdfFileId {
                        let file = try await pdfFileService.getFileStatus(fileId: fileId)
                        if file.isActive {
                            activeFiles.append((uri: file.uri, mimeType: file.mimeType, displayName: displayName))
                            continue
                        }
                    }
                } catch {
                    // File not found or error, will need re-upload
                }
                
                // Re-upload if needed
                if let newFile = try await pdfFileService.ensureFileActive(node: node) {
                    activeFiles.append((uri: newFile.uri, mimeType: newFile.mimeType, displayName: displayName))
                } else {
                    // Fallback: we only have the URI, assume PDF for legacy nodes
                    activeFiles.append((uri: existingUri, mimeType: "application/pdf", displayName: displayName))
                }
            }
        }
        
        guard !activeFiles.isEmpty else {
            throw PDFSearchError.noFilesProvided
        }
        
        // Build file search request (use dedicated file-search-capable model)
        let urlString = "\(Config.geminiAPIBaseURL)/\(Config.geminiFileSearchModel):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw PDFSearchError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build request body with file search tool (include filenames so model knows what files it has)
        let body = buildFileSearchRequest(query: query, files: activeFiles)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                throw PDFSearchError.searchFailed(errorText)
            }
            throw PDFSearchError.invalidResponse
        }
        
        return try parseSearchResponse(data: data, query: query)
    }
    
    /// Build context string from connected PDF nodes for AI prompts
    /// - Parameters:
    ///   - query: The user's query
    ///   - pdfNodes: Connected PDF nodes
    /// - Returns: Context string to include in AI prompt
    func buildPDFContext(query: String, pdfNodes: [Node]) async throws -> String {
        let result = try await searchPDFs(query: query, pdfNodes: pdfNodes)
        
        var contextParts: [String] = []
        contextParts.append("### Knowledge from PDF Documents ###")
        contextParts.append(result.answer)
        
        if !result.citations.isEmpty {
            contextParts.append("\n**Sources:**")
            for citation in result.citations {
                var sourceInfo = "- \(citation.fileName)"
                if let page = citation.pageNumber {
                    sourceInfo += " (page \(page))"
                }
                contextParts.append(sourceInfo)
            }
        }
        
        return contextParts.joined(separator: "\n")
    }
    
    // MARK: - Private Helpers
    
    private func buildFileSearchRequest(query: String, files: [(uri: String, mimeType: String, displayName: String)]) -> [String: Any] {
        // Build file data parts for each document
        var fileParts: [[String: Any]] = []
        for file in files {
            fileParts.append([
                "file_data": [
                    "file_uri": file.uri,
                    "mime_type": file.mimeType
                ]
            ])
        }
        
        // Build a preamble that tells the model what files it has access to
        let fileList = files.map { $0.displayName }.joined(separator: ", ")
        let preamble = "You have access to the following document(s): \(fileList)\n\nUser question: "
        
        // Add the query as text with the preamble
        fileParts.append(["text": preamble + query])
        
        return [
            "contents": [
                [
                    "role": "user",
                    "parts": fileParts
                ]
            ],
            "generationConfig": [
                "temperature": 0.2, // Lower temperature for factual retrieval
                "topK": 40,
                "topP": 0.95,
                "maxOutputTokens": 4096
            ],
            "systemInstruction": [
                "parts": [[
                    "text": """
                    You are a helpful assistant that answers questions based on the provided PDF documents.
                    
                    Instructions:
                    1. Answer questions using ONLY information from the provided documents
                    2. If the answer is not in the documents, say "I couldn't find this information in the provided documents"
                    3. Be specific and cite which document contains the information
                    4. Quote relevant passages when helpful
                    5. Keep answers concise but complete
                    """
                ]]
            ]
        ]
    }
    
    private func parseSearchResponse(data: Data, query: String) throws -> PDFSearchResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw PDFSearchError.invalidResponse
        }
        
        // Parse citations from grounding metadata if available
        var citations: [PDFCitation] = []
        if let groundingMetadata = firstCandidate["groundingMetadata"] as? [String: Any],
           let groundingChunks = groundingMetadata["groundingChunks"] as? [[String: Any]] {
            for chunk in groundingChunks {
                if let retrievedContext = chunk["retrievedContext"] as? [String: Any],
                   let uri = retrievedContext["uri"] as? String {
                    let fileName = uri.components(separatedBy: "/").last ?? "Unknown"
                    let snippet = retrievedContext["text"] as? String ?? ""
                    citations.append(PDFCitation(
                        fileName: fileName,
                        pageNumber: nil,
                        snippet: snippet
                    ))
                }
            }
        }
        
        return PDFSearchResult(
            query: query,
            answer: text,
            citations: citations
        )
    }
}
