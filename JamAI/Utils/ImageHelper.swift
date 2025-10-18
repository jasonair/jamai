//
//  ImageHelper.swift
//  JamAI
//
//  Utility for processing images for AI chat
//

import AppKit
import Foundation

enum ImageHelper {
    // Maximum dimensions for images sent to API (balance quality and efficiency)
    static let maxDimension: CGFloat = 1024
    static let jpegQuality: CGFloat = 0.85
    static let maxFileSizeBytes = 4 * 1024 * 1024 // 4MB
    
    /// Process an image for sending to AI: resize if needed and compress
    static func processImage(_ image: NSImage) -> (data: Data, mimeType: String)? {
        guard let resizedImage = resizeImage(image, maxDimension: maxDimension) else {
            return nil
        }
        
        // Try JPEG first (smaller file size)
        if let jpegData = imageToJPEG(resizedImage, quality: jpegQuality),
           jpegData.count <= maxFileSizeBytes {
            return (jpegData, "image/jpeg")
        }
        
        // Fallback to PNG if JPEG fails
        if let pngData = imageToPNG(resizedImage),
           pngData.count <= maxFileSizeBytes {
            return (pngData, "image/png")
        }
        
        // If still too large, try lower quality JPEG
        if let jpegData = imageToJPEG(resizedImage, quality: 0.6),
           jpegData.count <= maxFileSizeBytes {
            return (jpegData, "image/jpeg")
        }
        
        return nil
    }
    
    /// Resize image to fit within max dimension while maintaining aspect ratio
    static func resizeImage(_ image: NSImage, maxDimension: CGFloat) -> NSImage? {
        let size = image.size
        guard size.width > 0 && size.height > 0 else { return nil }
        
        // Check if resizing is needed
        if size.width <= maxDimension && size.height <= maxDimension {
            return image
        }
        
        // Calculate new size maintaining aspect ratio
        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = NSSize(width: size.width * ratio, height: size.height * ratio)
        
        // Create resized image
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        
        let context = NSGraphicsContext.current?.cgContext
        context?.setAllowsAntialiasing(true)
        context?.interpolationQuality = .high
        
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0
        )
        
        newImage.unlockFocus()
        return newImage
    }
    
    /// Convert NSImage to JPEG data
    static func imageToJPEG(_ image: NSImage, quality: CGFloat) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        )
    }
    
    /// Convert NSImage to PNG data
    static func imageToPNG(_ image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        return bitmap.representation(using: .png, properties: [:])
    }
    
    /// Get MIME type from file extension
    static func mimeType(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        default:
            return nil
        }
    }
    
    /// Validate if file is a supported image format
    static func isSupportedImageFormat(_ url: URL) -> Bool {
        let supportedExtensions = ["jpg", "jpeg", "png", "gif", "webp"]
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
