//
//  VectorMath.swift
//  JamAI
//
//  Vector math utilities using Accelerate framework for RAG
//

import Foundation
import Accelerate

enum VectorMath {
    /// Calculate cosine similarity between two vectors using vDSP
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        
        let n = vDSP_Length(a.count)
        var dotProduct: Float = 0
        var magnitudeA: Float = 0
        var magnitudeB: Float = 0
        
        // Dot product
        vDSP_dotpr(a, 1, b, 1, &dotProduct, n)
        
        // Magnitude of A
        var sumSquaresA: Float = 0
        vDSP_svesq(a, 1, &sumSquaresA, n)
        magnitudeA = sqrt(sumSquaresA)
        
        // Magnitude of B
        var sumSquaresB: Float = 0
        vDSP_svesq(b, 1, &sumSquaresB, n)
        magnitudeB = sqrt(sumSquaresB)
        
        guard magnitudeA > 0, magnitudeB > 0 else { return 0 }
        
        return dotProduct / (magnitudeA * magnitudeB)
    }
    
    /// Normalize a vector to unit length
    static func normalize(_ vector: [Float]) -> [Float] {
        guard !vector.isEmpty else { return [] }
        
        let n = vDSP_Length(vector.count)
        var magnitude: Float = 0
        var sumSquares: Float = 0
        
        vDSP_svesq(vector, 1, &sumSquares, n)
        magnitude = sqrt(sumSquares)
        
        guard magnitude > 0 else { return vector }
        
        var result = [Float](repeating: 0, count: vector.count)
        var divisor = magnitude
        vDSP_vsdiv(vector, 1, &divisor, &result, 1, n)
        
        return result
    }
    
    /// Find top-k most similar vectors
    static func topK(query: [Float], vectors: [(id: UUID, embedding: [Float])], k: Int) -> [(id: UUID, similarity: Float)] {
        let similarities = vectors.map { (id: $0.id, similarity: cosineSimilarity(query, $0.embedding)) }
        return Array(similarities.sorted { $0.similarity > $1.similarity }.prefix(k))
    }
}
