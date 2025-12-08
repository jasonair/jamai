import Foundation
import SwiftUI
import AppKit

/// Service for handling external URLs with confirmation dialogs
/// Provides URL detection and a standard macOS-style confirmation before opening external websites
final class ExternalLinkService {
    static let shared = ExternalLinkService()
    
    private init() {}
    
    // MARK: - URL Detection
    
    /// Detect URLs in text and return attributed string with clickable links
    /// Uses NSDataDetector for reliable URL detection
    @available(macOS 12.0, *)
    func detectLinks(in text: String) -> [(range: Range<String.Index>, url: URL)] {
        var links: [(range: Range<String.Index>, url: URL)] = []
        
        let types: NSTextCheckingResult.CheckingType = [.link]
        guard let detector = try? NSDataDetector(types: types.rawValue) else {
            return links
        }
        
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: nsRange)
        
        for match in matches {
            guard let range = Range(match.range, in: text),
                  let url = match.url else { continue }
            links.append((range: range, url: url))
        }
        
        return links
    }
    
    /// Add link attributes to NSMutableAttributedString for detected URLs
    /// - Parameters:
    ///   - attributedString: The attributed string to modify
    ///   - textColor: The color to use for links (should match the text color for the node)
    func addLinkAttributes(to attributedString: NSMutableAttributedString, textColor: NSColor) {
        let text = attributedString.string
        let types: NSTextCheckingResult.CheckingType = [.link]
        
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return }
        
        let nsRange = NSRange(location: 0, length: attributedString.length)
        let matches = detector.matches(in: text, options: [], range: nsRange)
        
        let boldFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
        
        for match in matches {
            guard let url = match.url else { continue }
            
            // Add link attribute
            attributedString.addAttribute(.link, value: url, range: match.range)
            
            // Style the link - bold + underline, using same color as text
            attributedString.addAttribute(.foregroundColor, value: textColor, range: match.range)
            attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
            attributedString.addAttribute(.font, value: boldFont, range: match.range)
        }
    }
    
    // MARK: - Link Opening
    
    /// Show confirmation dialog and open URL if user confirms
    func openWithConfirmation(url: URL, from sourceView: NSView? = nil) {
        // Extract domain for display
        let domain = url.host ?? url.absoluteString
        let displayURL = url.absoluteString
        
        // Create confirmation alert
        let alert = NSAlert()
        alert.messageText = "Open External Link?"
        alert.informativeText = "You're about to leave Jam AI and open:\n\n\(displayURL)\n\nThis will open in your default browser."
        alert.alertStyle = .informational
        
        // Add icon
        alert.icon = NSImage(systemSymbolName: "link.circle", accessibilityDescription: "External link")
        
        // Add buttons (order matters for return codes)
        alert.addButton(withTitle: "Open in Browser")
        alert.addButton(withTitle: "Copy Link")
        alert.addButton(withTitle: "Cancel")
        
        // Show the alert
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            // Open in browser
            NSWorkspace.shared.open(url)
        case .alertSecondButtonReturn:
            // Copy link to clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        case .alertThirdButtonReturn:
            // Cancel - do nothing
            break
        default:
            break
        }
    }
    
    /// Check if URL is external (not a local/internal link)
    func isExternalURL(_ url: URL) -> Bool {
        // Mail, tel, and other special schemes should be handled differently
        let scheme = url.scheme?.lowercased() ?? ""
        
        // HTTP/HTTPS are always external
        if scheme == "http" || scheme == "https" {
            return true
        }
        
        // Other common external schemes
        if scheme == "mailto" || scheme == "tel" {
            return false // Let system handle these directly
        }
        
        return false
    }
}

// MARK: - SwiftUI Link Handler

/// Environment key for custom URL opening with confirmation
struct ExternalLinkOpenURLAction: EnvironmentKey {
    static let defaultValue: OpenURLAction? = nil
}

extension EnvironmentValues {
    var externalLinkOpenURL: OpenURLAction? {
        get { self[ExternalLinkOpenURLAction.self] }
        set { self[ExternalLinkOpenURLAction.self] = newValue }
    }
}

// MARK: - NSTextView Delegate for Link Handling

/// Delegate that intercepts link clicks in NSTextView to show confirmation dialog
class LinkClickDelegate: NSObject, NSTextViewDelegate {
    static let shared = LinkClickDelegate()
    
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        // Handle URL clicks
        if let url = link as? URL {
            if ExternalLinkService.shared.isExternalURL(url) {
                ExternalLinkService.shared.openWithConfirmation(url: url, from: textView)
                return true // We handled it
            } else {
                // Let system handle non-external URLs (mailto, tel, etc.)
                NSWorkspace.shared.open(url)
                return true
            }
        }
        
        // Handle string URLs
        if let urlString = link as? String, let url = URL(string: urlString) {
            if ExternalLinkService.shared.isExternalURL(url) {
                ExternalLinkService.shared.openWithConfirmation(url: url, from: textView)
                return true
            } else {
                NSWorkspace.shared.open(url)
                return true
            }
        }
        
        return false // Not handled
    }
}

// MARK: - AttributedString Extension

@available(macOS 12.0, *)
extension String {
    /// Convert string to AttributedString with detected URLs as clickable links
    func withDetectedLinks(baseFont: Font = .system(size: 15), textColor: Color = .primary) -> AttributedString {
        var attributedString = AttributedString(self)
        
        let types: NSTextCheckingResult.CheckingType = [.link]
        guard let detector = try? NSDataDetector(types: types.rawValue) else {
            return attributedString
        }
        
        let matches = detector.matches(in: self, options: [], range: NSRange(location: 0, length: self.utf16.count))
        
        for match in matches {
            guard let url = match.url else { continue }
            
            // Convert NSRange to AttributedString.Index range
            let startIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: match.range.location)
            let endIndex = attributedString.index(startIndex, offsetByCharacters: match.range.length)
            let range = startIndex..<endIndex
            
            // Set link attribute
            attributedString[range].link = url
            
            // Style the link - bold + underline (color inherits from parent or uses primary)
            attributedString[range].underlineStyle = .single
            attributedString[range].font = .system(size: 15, weight: .semibold)
        }
        
        return attributedString
    }
}
