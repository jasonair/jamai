//
//  Config.swift
//  JamAI
//
//  App configuration and constants
//

import Foundation

enum Config {
    // Logging
    static let enableVerboseLogging: Bool = false
    
    // API
    static let geminiAPIBaseURL = "https://generativelanguage.googleapis.com/v1beta"
    static let geminiModel = "gemini-2.0-flash-exp"
    static let geminiEmbeddingModel = "models/text-embedding-004"
    // Call Cloud Function directly for Gemini SaaS backend
    static let geminiBackendURL = "https://europe-west1-jamai-dev.cloudfunctions.net/generateWithGemini"
    
    // Keychain
    static let keychainService = "com.jamai.api-keys"
    static let geminiAPIKeyIdentifier = "gemini-api-key"
    static let deviceIdKey = "device-id"
    
    // Performance
    static let targetFPS = 60
    static let maxNodes = 5000
    static let maxEdges = 6000
    static let viewCullingMargin: CGFloat = 100
    
    // Node defaults
    static let defaultKTurns = 8
    static let defaultRAGK = 5
    static let defaultRAGMaxChars = 2000
    
    // Canvas
    static let gridSize: CGFloat = 50
    static let minZoom: CGFloat = 0.1
    static let maxZoom: CGFloat = 1.5
    static let defaultZoom: CGFloat = 1.0
    
    // Note: SwiftUI Canvas has inherent clipping limitations
    // Edges may not render correctly when nodes exceed ~10,000 pixels from origin
    // See CANVAS_LIMITATIONS.md for details
    
    // Undo/Redo
    static let maxUndoSteps = 200
    
    // RAG Chunking
    static let ragChunkSize = 1500
    static let ragChunkOverlap = 200
    
    // File types
    static let jamFileExtension = "jam"
    static let jamUTType = "com.jamai.project"
    
    // Auto-save
    static let autoSaveInterval: TimeInterval = 30
    static let maxAutosaveBackups = 10  // Keep last 10 backups for recovery
    
    // Retry policy
    static let maxRetries = 3
    static let initialBackoffDelay: TimeInterval = 1.0
    static let maxBackoffDelay: TimeInterval = 32.0
    
    // Visual Effects
    static let thinkingGlowEnabledKey = "thinkingGlowEnabled"
}
