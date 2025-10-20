//
//  MarkdownText.swift
//  JamAI
//
//  Properly formatted markdown text view with table and bullet support
//

import SwiftUI

// NOTE: NSParagraphStyle Sendable warnings in this file are expected and safe to ignore
// Apple's AppKit hasn't adopted Sendable yet, but usage here is synchronous on main thread

// Environment keys for canvas transform states
private struct IsZoomingKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct IsPanningKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isZooming: Bool {
        get { self[IsZoomingKey.self] }
        set { self[IsZoomingKey.self] = newValue }
    }
    
    var isPanning: Bool {
        get { self[IsPanningKey.self] }
        set { self[IsPanningKey.self] = newValue }
    }
}

struct MarkdownText: View {
    let text: String
    var onCopy: ((String) -> Void)?
    
    @State private var showCopiedToast = false
    @State private var cachedBlocks: [MarkdownBlock] = []
    @State private var parseTask: Task<Void, Never>?
    @Environment(\.isZooming) private var isZooming
    
    var body: some View {
        // PERFORMANCE OPTIMIZATION: Use LazyVStack to defer off-screen rendering
        // Only visible blocks are rendered, invisible ones wait until scrolled into view
        // User sees no difference, but zoom/scroll performance is dramatically improved
        LazyVStack(alignment: .leading, spacing: 8, pinnedViews: []) {
            ForEach(cachedBlocks, id: \.id) { block in
                Group {
                    switch block.type {
                    case .table(let headers, let rows):
                        // CALayer-based rendering for 60fps performance
                        // Eliminates SwiftUI layout overhead during zoom/pan/drag
                        CATableView(headers: headers, rows: rows)
                            .padding(.bottom, 20)
                    case .codeBlock(let code, let language):
                        // Code blocks with syntax highlighting
                        HStack {
                            Spacer(minLength: 0)
                            CodeBlockView(code: code, language: language)
                                .frame(maxWidth: 700)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                    case .text(let content):
                        // Text is centered with max reading width and padding
                        HStack {
                            Spacer(minLength: 0)
                            FormattedTextView(content: content)
                                .frame(maxWidth: 700)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            
            // Copy button at the end - centered within text content width
            if let onCopy = onCopy {
                HStack {
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Button(action: {
                            onCopy(text)
                            // Show toast
                            showCopiedToast = true
                            // Hide after 2 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showCopiedToast = false
                            }
                        }) {
                            Image(systemName: showCopiedToast ? "checkmark.circle.fill" : "doc.on.doc")
                                .font(.system(size: 13))
                                .foregroundColor(showCopiedToast ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(6)
                        .help(showCopiedToast ? "Copied!" : "Copy response")
                        
                        if showCopiedToast {
                            Text("Copied!")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.green)
                                .transition(.opacity.combined(with: .scale))
                        }
                        
                        Spacer()
                    }
                    .frame(maxWidth: 700)
                    .padding(.horizontal, 8)
                    .padding(.top, 0)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true) // Prevent content from disappearing on resize
        .onAppear {
            // Initial parse on appear
            cachedBlocks = parseMarkdownBlocks(text)
        }
        .onChange(of: text) { oldValue, newValue in
            // Cancel any pending parse task
            parseTask?.cancel()
            
            // Debounce parsing: wait 100ms before parsing
            // This prevents re-parsing on every character during AI streaming
            parseTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                
                // Check if task was cancelled
                guard !Task.isCancelled else { return }
                
                // Update state directly - we're already on MainActor
                cachedBlocks = parseMarkdownBlocks(newValue)
            }
        }
        .onDisappear {
            // Cancel parse task when view disappears
            parseTask?.cancel()
        }
    }
}

// MARK: - Formatted Text View

private struct FormattedTextView: View {
    let content: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        if #available(macOS 12.0, *) {
            let formatted = formatText(content)
            let nsAttributed = convertToNSAttributedString(formatted, colorScheme: colorScheme)
            NSTextViewWrapper(attributedString: nsAttributed)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(content)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    @available(macOS 12.0, *)
    private func convertToNSAttributedString(_ attributedString: AttributedString, colorScheme: ColorScheme) -> NSAttributedString {
        let nsAttrString = NSMutableAttributedString()
        
        // Build NSAttributedString from scratch with proper NSFont attributes
        let baseFont = NSFont.systemFont(ofSize: 15)
        let baseBoldFont = NSFont.systemFont(ofSize: 15, weight: .bold)
        let codeFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let headerFont = NSFont.systemFont(ofSize: 20, weight: .semibold)
        
        // Set text color based on color scheme
        let textColor: NSColor = colorScheme == .dark ? .white : .black
        
        // Process runs from the original AttributedString
        for run in attributedString.runs {
            let runText = String(attributedString[run.range].characters)
            let runLength = runText.utf16.count
            
            // Check if this run is bold (has stronglyEmphasized intent)
            let isBold = run.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false
            
            // Check if this run is code (has code intent)
            let isCode = run.inlinePresentationIntent?.contains(.code) ?? false
            
            // Check if this is a standalone header (bold text ending with colon at line start)
            var isHeader = false
            if isBold && runText.hasSuffix(":") {
                let currentLength = nsAttrString.length
                let isAtStart = currentLength == 0
                let isAfterNewline = currentLength > 0 && (nsAttrString.string as NSString).character(at: currentLength - 1) == UInt16(UnicodeScalar("\n").value)
                
                // Check it's not part of a bullet line
                var isBulletItem = false
                let lineStartRange = (nsAttrString.string as NSString).range(of: "\n", options: .backwards, range: NSRange(location: 0, length: currentLength))
                if lineStartRange.location != NSNotFound {
                    let lineContent = (nsAttrString.string as NSString).substring(with: NSRange(location: lineStartRange.location + 1, length: currentLength - lineStartRange.location - 1))
                    isBulletItem = lineContent.contains("•")
                } else if currentLength > 0 {
                    let lineContent = (nsAttrString.string as NSString).substring(with: NSRange(location: 0, length: currentLength))
                    isBulletItem = lineContent.contains("•")
                }
                
                isHeader = (isAtStart || isAfterNewline) && !isBulletItem
            }
            
            // Choose appropriate font
            let font: NSFont
            if isHeader {
                font = headerFont
            } else if isCode {
                font = codeFont
            } else if isBold {
                font = baseBoldFont
            } else {
                font = baseFont
            }
            
            // Create attributed string for this run
            let runAttrString = NSMutableAttributedString(string: runText)
            runAttrString.addAttribute(.font, value: font, range: NSRange(location: 0, length: runLength))
            runAttrString.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: runLength))
            
            // Add background color and padding for inline code
            if isCode {
                let codeBackgroundColor: NSColor = colorScheme == .dark 
                    ? NSColor.white.withAlphaComponent(0.15) 
                    : NSColor.black.withAlphaComponent(0.08)
                runAttrString.addAttribute(.backgroundColor, value: codeBackgroundColor, range: NSRange(location: 0, length: runLength))
                
                // Add slight padding effect with baseline offset
                runAttrString.addAttribute(.baselineOffset, value: 1, range: NSRange(location: 0, length: runLength))
            }
            
            nsAttrString.append(runAttrString)
        }
        
        // Apply paragraph styles for bullets and numbered lists
        let fullString = nsAttrString.string
        var location = 0
        for line in fullString.components(separatedBy: "\n") {
            let length = (line as NSString).length
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Detect bullet points with different indentation levels
            if trimmed.hasPrefix("•") && length > 0 {
                let ps = NSMutableParagraphStyle()
                ps.firstLineHeadIndent = 0
                
                // Count leading spaces to determine nesting level
                let leadingSpaces = line.prefix(while: { $0 == " " }).count
                if leadingSpaces >= 4 {
                    // Second-level bullet (4+ spaces): more indent
                    ps.headIndent = 38
                } else if leadingSpaces >= 2 {
                    // First-level nested bullet (2-3 spaces): medium indent
                    ps.headIndent = 38
                } else {
                    // Top-level bullet: base indent (increased from 17 to 19)
                    ps.headIndent = 19
                }
                nsAttrString.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: location, length: length))
            }
            // Detect numbered lists (e.g., "1. ", "2. ", etc.)
            else if let firstChar = trimmed.first, firstChar.isNumber {
                // Check if it's followed by a period and space
                let pattern = "^[0-9]+\\. "
                if trimmed.range(of: pattern, options: .regularExpression) != nil {
                    let ps = NSMutableParagraphStyle()
                    ps.firstLineHeadIndent = 0
                    
                    // Count leading spaces to determine nesting level
                    let leadingSpaces = line.prefix(while: { $0 == " " }).count
                    if leadingSpaces >= 4 {
                        // Nested numbered list: more indent
                        ps.headIndent = 42
                    } else if leadingSpaces >= 2 {
                        // First-level nested: medium indent
                        ps.headIndent = 42
                    } else {
                        // Top-level numbered list: base indent
                        ps.headIndent = 24
                    }
                    nsAttrString.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: location, length: length))
                }
            }
            
            location += length + 1 // account for newline
        }
        
        return nsAttrString
    }
    
    @available(macOS 12.0, *)
    private func formatText(_ text: String) -> AttributedString {
        // Replace asterisk bullets with proper bullet points
        var processedText = text.replacingOccurrences(of: "\n* ", with: "\n• ")
        processedText = processedText.replacingOccurrences(of: "\n  * ", with: "\n  • ")
        processedText = processedText.replacingOccurrences(of: "\n    * ", with: "\n    • ")
        
        // If starts with asterisk, replace it too
        if processedText.hasPrefix("* ") {
            processedText = "• " + processedText.dropFirst(2)
        }
        
        // Parse as markdown with proper options
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        
        if var attributed = try? AttributedString(markdown: processedText, options: options) {
            // Get full text for processing
            let fullText = String(attributed.characters)
            
            
            // Increase font size ONLY for standalone section headers (bold text with colon at start of line)
            for run in attributed.runs {
                if let inlinePresentationIntent = run.inlinePresentationIntent,
                   inlinePresentationIntent.contains(.stronglyEmphasized) {
                    let runText = String(attributed[run.range].characters)
                    
                    // Only increase size if it ends with colon AND is a standalone header
                    if runText.hasSuffix(":") {
                        // Check if this bold text starts at beginning of content or after a newline
                        let startIndex = attributed.characters.distance(from: attributed.startIndex, to: run.range.lowerBound)
                        let isAtStart = startIndex == 0
                        let isAfterNewline = startIndex > 0 && fullText.dropFirst(startIndex - 1).first == "\n"
                        
                        // Check it's not part of a bullet point line (no bullet before it on same line)
                        var isBulletItem = false
                        if let lineStart = fullText[..<fullText.index(fullText.startIndex, offsetBy: startIndex)].lastIndex(of: "\n") {
                            let lineContent = fullText[fullText.index(after: lineStart)..<fullText.index(fullText.startIndex, offsetBy: startIndex)]
                            isBulletItem = lineContent.contains("•")
                        } else if startIndex > 0 {
                            // Check from start if no newline found
                            let lineContent = fullText[..<fullText.index(fullText.startIndex, offsetBy: startIndex)]
                            isBulletItem = lineContent.contains("•")
                        }
                        
                        // Only apply larger font if it's a standalone header (not in a bullet)
                        if (isAtStart || isAfterNewline) && !isBulletItem {
                            attributed[run.range].font = .system(size: 22, weight: .semibold)
                        }
                    }
                }
            }
            return attributed
        } else {
            return AttributedString(processedText)
        }
    }
}

// MARK: - Markdown Block Parsing

private enum MarkdownBlockType {
    case text(String)
    case table([String], [[String]]) // headers, rows
    case codeBlock(String, String?) // code, language
}

private struct MarkdownBlock {
    let id = UUID()
    let type: MarkdownBlockType
}

private func parseMarkdownBlocks(_ text: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    let lines = text.components(separatedBy: .newlines)
    var i = 0
    var currentTextLines: [String] = []
    
    while i < lines.count {
        let line = lines[i]
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Check if this is a code block start (```)
        if trimmed.hasPrefix("```") {
            // Flush any accumulated text
            if !currentTextLines.isEmpty {
                blocks.append(MarkdownBlock(type: .text(currentTextLines.joined(separator: "\n"))))
                currentTextLines = []
            }
            
            // Extract language if present
            let language = trimmed.count > 3 ? String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces) : nil
            var codeLines: [String] = []
            var j = i + 1
            
            // Collect code until closing ```
            while j < lines.count {
                let codeLine = lines[j]
                if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    j += 1
                    break
                }
                codeLines.append(codeLine)
                j += 1
            }
            
            blocks.append(MarkdownBlock(type: .codeBlock(codeLines.joined(separator: "\n"), language)))
            i = j
        }
        // Check if this is a table row (contains pipes)
        else if line.contains("|") && trimmed.hasPrefix("|") {
            // Flush any accumulated text
            if !currentTextLines.isEmpty {
                blocks.append(MarkdownBlock(type: .text(currentTextLines.joined(separator: "\n"))))
                currentTextLines = []
            }
            
            // Parse table
            var tableLines: [String] = []
            var j = i
            
            // Collect all consecutive table lines
            while j < lines.count {
                let tableLine = lines[j]
                if tableLine.contains("|") {
                    tableLines.append(tableLine)
                    j += 1
                } else if tableLine.trimmingCharacters(in: .whitespaces).isEmpty && j > i {
                    // Allow empty lines within table
                    j += 1
                    break
                } else {
                    break
                }
            }
            
            if let table = parseTable(tableLines) {
                blocks.append(MarkdownBlock(type: .table(table.headers, table.rows)))
            }
            
            i = j
        } else {
            // Regular text line
            currentTextLines.append(line)
            i += 1
        }
    }
    
    // Flush remaining text
    if !currentTextLines.isEmpty {
        blocks.append(MarkdownBlock(type: .text(currentTextLines.joined(separator: "\n"))))
    }
    
    return blocks
}

private func parseTable(_ lines: [String]) -> (headers: [String], rows: [[String]])? {
    guard lines.count >= 2 else { return nil }
    
    let cleanLines = lines.filter { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != "|"
    }
    
    guard cleanLines.count >= 2 else { return nil }
    
    // First line is headers
    let headerLine = cleanLines[0]
    var headers = parseTableRow(headerLine)
    
    // Remove trailing empty headers (fixes extra column issue)
    while headers.last?.isEmpty == true {
        headers.removeLast()
    }
    
    guard !headers.isEmpty else { return nil }
    
    // Second line should be separator (|---|---|), skip it
    let separatorLine = cleanLines[1]
    let isSeparator = separatorLine.contains("-")
    let startIndex = isSeparator ? 2 : 1
    
    // Remaining lines are data rows
    var rows: [[String]] = []
    for i in startIndex..<cleanLines.count {
        var row = parseTableRow(cleanLines[i])
        
        // Normalize row length to match headers
        // Remove trailing empty cells
        while row.count > headers.count && row.last?.isEmpty == true {
            row.removeLast()
        }
        
        // Pad with empty strings if row is shorter than headers
        while row.count < headers.count {
            row.append("")
        }
        
        // Truncate if row is longer than headers
        if row.count > headers.count {
            row = Array(row.prefix(headers.count))
        }
        
        if !row.isEmpty {
            rows.append(row)
        }
    }
    
    return (headers, rows)
}

private func parseTableRow(_ line: String) -> [String] {
    let cells = line.components(separatedBy: "|")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.allSatisfy({ $0 == "-" }) }
    return cells
}

// MARK: - Code Block View

private struct CodeBlockView: View {
    let code: String
    let language: String?
    @Environment(\.colorScheme) var colorScheme
    @State private var showCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language label and copy button
            HStack {
                if let lang = language, !lang.isEmpty {
                    Text(lang.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Copy button
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showCopied = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        if showCopied {
                            Text("Copied")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .foregroundColor(showCopied ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(headerBackground)
            
            // Code content - expands to fit all content
            Text(code)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(codeBackground)
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
    }
    
    private var headerBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.04)
    }
    
    private var codeBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.05)
            : Color.black.opacity(0.03)
    }
    
    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.15)
            : Color.black.opacity(0.12)
    }
}

// MARK: - CALayer-Based High-Performance Table View

// Custom NSView that uses CALayer for GPU-accelerated table rendering
// This approach eliminates SwiftUI layout overhead for 60fps performance
private class TableLayerView: NSView {
    var headers: [String] = []
    var rows: [[String]] = []
    var columnWidths: [CGFloat] = []
    var isDarkMode: Bool = false
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.shouldRasterize = true // GPU-accelerated cache
        layer?.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2.0
        layer?.masksToBounds = true
    }
    
    // CRITICAL: Flip coordinate system so y=0 is at TOP (headers first)
    override var isFlipped: Bool { return true }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateTable(headers: [String], rows: [[String]], isDarkMode: Bool) {
        guard self.headers != headers || self.rows != rows || self.isDarkMode != isDarkMode else {
            return // Skip update if nothing changed
        }
        
        self.headers = headers
        self.rows = rows
        self.isDarkMode = isDarkMode
        calculateColumnWidths()
        rebuildLayers()
    }
    
    private func calculateColumnWidths() {
        // Pre-calculate all widths using NSAttributedString measurement
        // This happens ONCE when table content changes, not every frame
        guard bounds.width > 0 else {
            columnWidths = []
            return
        }
        
        let totalWidth = bounds.width
        let columnCount = CGFloat(max(headers.count, 1))
        
        // For now, use equal column widths
        // Could be enhanced with content-based sizing later
        let columnWidth = totalWidth / columnCount
        columnWidths = Array(repeating: columnWidth, count: headers.count)
    }
    
    private func rebuildLayers() {
        // Remove all existing sublayers
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        
        guard !headers.isEmpty, !columnWidths.isEmpty else { return }
        
        var yOffset: CGFloat = 0
        let minRowHeight: CGFloat = 32
        
        // Header row with darker background
        var headerHeight = minRowHeight
        for (index, header) in headers.enumerated() {
            let requiredHeight = calculateTextHeight(text: header, width: columnWidths[index], isHeader: true)
            headerHeight = max(headerHeight, requiredHeight + 16) // +16 for padding
        }
        
        for (index, header) in headers.enumerated() {
            let xOffset = columnWidths[..<index].reduce(0, +)
            let cellLayer = createCellLayer(
                text: header,
                frame: CGRect(x: xOffset, y: yOffset, 
                            width: columnWidths[index], height: headerHeight),
                isHeader: true
            )
            layer?.addSublayer(cellLayer)
        }
        
        yOffset += headerHeight
        
        // Data rows - calculate height per row based on content
        for row in rows {
            var rowHeight = minRowHeight
            
            // Calculate max height needed for this row
            for index in 0..<headers.count {
                let cellText = index < row.count ? row[index] : ""
                let requiredHeight = calculateTextHeight(text: cellText, width: columnWidths[index], isHeader: false)
                rowHeight = max(rowHeight, requiredHeight + 16) // +16 for padding
            }
            
            // Render all cells in this row with the calculated height
            for index in 0..<headers.count {
                let cellText = index < row.count ? row[index] : ""
                let xOffset = columnWidths[..<index].reduce(0, +)
                let cellLayer = createCellLayer(
                    text: cellText,
                    frame: CGRect(x: xOffset, y: yOffset, 
                                width: columnWidths[index], height: rowHeight),
                    isHeader: false
                )
                layer?.addSublayer(cellLayer)
            }
            yOffset += rowHeight
        }
        
        // Update container height
        invalidateIntrinsicContentSize()
    }
    
    private func calculateTextHeight(text: String, width: CGFloat, isHeader: Bool) -> CGFloat {
        guard width > 24 else { return 20 } // Min height for very narrow cells
        
        let attributedText = parseMarkdownBold(text, isHeader: isHeader)
        let mutableAttrString = NSMutableAttributedString(attributedString: attributedText)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.alignment = .left
        mutableAttrString.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: mutableAttrString.length)
        )
        
        let constraintRect = CGSize(width: width - 24, height: .greatestFiniteMagnitude)
        let boundingBox = mutableAttrString.boundingRect(
            with: constraintRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        
        return ceil(boundingBox.height)
    }
    
    private func createCellLayer(text: String, frame: CGRect, isHeader: Bool) -> CALayer {
        let container = CALayer()
        container.frame = frame
        container.masksToBounds = true  // Clip text to cell bounds
        
        // Border color based on dark mode
        let borderColor: CGColor = isDarkMode 
            ? NSColor.white.withAlphaComponent(0.15).cgColor
            : NSColor.black.withAlphaComponent(0.15).cgColor
        
        container.borderColor = borderColor
        container.borderWidth = 0.5
        
        // Background for header cells
        if isHeader {
            let bgColor: CGColor = isDarkMode
                ? NSColor.white.withAlphaComponent(0.08).cgColor
                : NSColor.black.withAlphaComponent(0.05).cgColor
            container.backgroundColor = bgColor
        }
        
        // Render text to image for reliable display with truncation
        // CATextLayer has issues with truncation, so we pre-render to bitmap
        let textFrame = container.bounds.insetBy(dx: 12, dy: 8)
        
        if let textImage = renderTextToImage(text: text, frame: textFrame, isHeader: isHeader) {
            let imageLayer = CALayer()
            imageLayer.frame = textFrame
            imageLayer.contents = textImage
            imageLayer.contentsGravity = .resizeAspect
            imageLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
            container.addSublayer(imageLayer)
        }
        
        return container
    }
    
    // Render text to image using NSString drawing for reliable truncation
    private func renderTextToImage(text: String, frame: CGRect, isHeader: Bool) -> CGImage? {
        guard frame.width > 0 && frame.height > 0 else { return nil }
        
        // Parse markdown and create attributed string
        let attributedText = parseMarkdownBold(text, isHeader: isHeader)
        
        // Add paragraph style for word wrapping
        let mutableAttrString = NSMutableAttributedString(attributedString: attributedText)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping  // Changed from truncating to wrapping
        paragraphStyle.alignment = .left
        mutableAttrString.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: mutableAttrString.length)
        )
        
        // Create bitmap context
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let pixelWidth = Int(frame.width * scale)
        let pixelHeight = Int(frame.height * scale)
        
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        // Scale for retina
        context.scaleBy(x: scale, y: scale)
        
        // Create flipped graphics context (y=0 at top, matching TableLayerView)
        let nsGraphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsGraphicsContext
        
        // Draw text in flipped coordinate system - text will be right-side up
        mutableAttrString.draw(in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        
        NSGraphicsContext.restoreGraphicsState()
        
        // Create image from the context
        guard let cgImage = context.makeImage() else { return nil }
        
        // CRITICAL: The rendered image is now in standard coordinates (not flipped)
        // We need to flip it vertically so it displays correctly in our flipped view
        let flippedSize = CGSize(width: pixelWidth, height: pixelHeight)
        
        guard let flippedContext = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return cgImage }
        
        // Flip the image vertically
        flippedContext.translateBy(x: 0, y: CGFloat(pixelHeight))
        flippedContext.scaleBy(x: 1, y: -1)
        flippedContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight)))
        
        return flippedContext.makeImage() ?? cgImage
    }
    
    // Parse markdown bold syntax **text** and return NSAttributedString
    private func parseMarkdownBold(_ text: String, isHeader: Bool) -> NSAttributedString {
        let fontSize: CGFloat = isHeader ? 14 : 13
        let baseFont = isHeader 
            ? NSFont.systemFont(ofSize: fontSize, weight: .semibold)
            : NSFont.systemFont(ofSize: fontSize)
        let boldFont = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        
        let textColor: NSColor = isDarkMode ? .white : .black
        
        let attributedString = NSMutableAttributedString()
        
        // Simple regex-based markdown bold parser
        let pattern = "\\*\\*([^*]+)\\*\\*"
        let regex = try? NSRegularExpression(pattern: pattern)
        
        var lastIndex = text.startIndex
        let nsString = text as NSString
        let matches = regex?.matches(in: text, range: NSRange(location: 0, length: nsString.length)) ?? []
        
        for match in matches {
            // Add text before bold
            let beforeRange = lastIndex..<text.index(text.startIndex, offsetBy: match.range.location)
            if !beforeRange.isEmpty {
                let beforeText = String(text[beforeRange])
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: baseFont,
                    .foregroundColor: textColor
                ]
                attributedString.append(NSAttributedString(string: beforeText, attributes: attrs))
            }
            
            // Add bold text (without ** markers)
            if match.numberOfRanges > 1 {
                let boldRange = match.range(at: 1)
                let boldText = nsString.substring(with: boldRange)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: boldFont,
                    .foregroundColor: textColor
                ]
                attributedString.append(NSAttributedString(string: boldText, attributes: attrs))
            }
            
            lastIndex = text.index(text.startIndex, offsetBy: match.range.location + match.range.length)
        }
        
        // Add remaining text after last bold
        if lastIndex < text.endIndex {
            let remainingText = String(text[lastIndex...])
            let attrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: textColor
            ]
            attributedString.append(NSAttributedString(string: remainingText, attributes: attrs))
        }
        
        // If no bold markers found, return plain attributed string
        if attributedString.length == 0 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: textColor
            ]
            return NSAttributedString(string: text, attributes: attrs)
        }
        
        return attributedString
    }
    
    override var intrinsicContentSize: NSSize {
        // Calculate total height from actual layer positions
        guard let sublayers = layer?.sublayers, !sublayers.isEmpty else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 100)
        }
        
        let maxY = sublayers.map { $0.frame.maxY }.max() ?? 100
        return NSSize(width: NSView.noIntrinsicMetric, height: maxY)
    }
    
    override func layout() {
        super.layout()
        // Recalculate layout when view bounds change (e.g., during resize)
        if columnWidths.isEmpty || bounds.width != columnWidths.reduce(0, +) {
            calculateColumnWidths()
            rebuildLayers()
        }
    }
}

// SwiftUI wrapper with copy-as-image functionality
private struct CATableView: View {
    let headers: [String]
    let rows: [[String]]
    @State private var isHovering = false
    @State private var showCopied = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // The actual table view
            CATableViewRepresentable(headers: headers, rows: rows)
            
            // Copy button (appears on hover)
            if isHovering {
                Button(action: copyTableAsImage) {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        if showCopied {
                            Text("Copied")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .foregroundColor(showCopied ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.95))
                    .cornerRadius(4)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .padding(8)
                .help("Copy table as image")
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
    
    private func copyTableAsImage() {
        // Find the TableLayerView and render it to an image
        guard let window = NSApp.keyWindow,
              let contentView = window.contentView else { return }
        
        // Search for TableLayerView in the view hierarchy
        var tableView: TableLayerView?
        func findTableView(in view: NSView) {
            if let found = view as? TableLayerView {
                tableView = found
                return
            }
            for subview in view.subviews {
                findTableView(in: subview)
                if tableView != nil { return }
            }
        }
        findTableView(in: contentView)
        
        guard let tableView = tableView else { return }
        
        // Force layout to ensure all content is rendered
        tableView.layoutSubtreeIfNeeded()
        
        // Render to image using actual bounds (full table size)
        let bounds = tableView.bounds
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        
        // Ensure we capture the full table by checking intrinsic size
        let intrinsicSize = tableView.intrinsicContentSize
        let captureSize = CGSize(
            width: max(bounds.width, intrinsicSize.width == NSView.noIntrinsicMetric ? bounds.width : intrinsicSize.width),
            height: max(bounds.height, intrinsicSize.height)
        )
        
        let size = CGSize(width: captureSize.width * scale, height: captureSize.height * scale)
        
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }
        
        bitmap.size = size
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        
        if let context = NSGraphicsContext.current?.cgContext {
            // CRITICAL: Flip coordinate system to match isFlipped view
            // Without this, the image appears mirrored/backwards
            context.translateBy(x: 0, y: captureSize.height * scale)
            context.scaleBy(x: scale, y: -scale)  // Negative y flips the coordinate system
            tableView.layer?.render(in: context)
        }
        
        NSGraphicsContext.restoreGraphicsState()
        
        let image = NSImage(size: captureSize)
        image.addRepresentation(bitmap)
        
        // Copy to pasteboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        
        // Show "Copied" feedback
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopied = false
        }
    }
}

// Internal NSViewRepresentable for CALayer-based table view
private struct CATableViewRepresentable: NSViewRepresentable {
    let headers: [String]
    let rows: [[String]]
    @Environment(\.colorScheme) var colorScheme
    
    func makeNSView(context: Context) -> TableLayerView {
        let view = TableLayerView()
        return view
    }
    
    func updateNSView(_ nsView: TableLayerView, context: Context) {
        nsView.updateTable(
            headers: headers, 
            rows: rows, 
            isDarkMode: colorScheme == .dark
        )
    }
}

// MARK: - Table View (Legacy SwiftUI Grid - Kept for Reference)

private struct MarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]
    
    @Environment(\.colorScheme) var colorScheme
    
    // Stable ID prevents unnecessary re-renders during zoom transitions
    private var tableID: String {
        "\(headers.joined())-\(rows.count)"
    }
    
    var body: some View {
        if #available(macOS 12.0, *) {
            // Use Grid for automatic column alignment (industry best practice)
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                // Header row
                GridRow(alignment: .top) {
                    ForEach(0..<headers.count, id: \.self) { index in
                        ZStack(alignment: .topLeading) {
                            headerBackground
                            Text(headers[index])
                                .font(.system(size: 14, weight: .semibold))
                                .textSelection(.enabled)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .overlay(
                            Rectangle()
                                .stroke(borderColor, lineWidth: 1)
                        )
                        .gridColumnAlignment(.leading)
                    }
                }
                
                // Data rows
                ForEach(0..<rows.count, id: \.self) { rowIndex in
                    GridRow(alignment: .top) {
                        ForEach(0..<headers.count, id: \.self) { colIndex in
                            let cellText = colIndex < rows[rowIndex].count ? rows[rowIndex][colIndex] : ""
                            ZStack(alignment: .topLeading) {
                                Color.clear
                                Text(.init(cellText))
                                    .font(.system(size: 13))
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                            .overlay(
                                Rectangle()
                                    .stroke(borderColor, lineWidth: 1)
                            )
                            .gridColumnAlignment(.leading)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(borderColor, lineWidth: 1)
            )
            .cornerRadius(4)
            .clipped()
            .drawingGroup()  // Always rasterize for performance - prevents layout shifts
            .id(tableID)  // Stable ID prevents re-renders during zoom transitions
        } else {
            // Fallback for older macOS versions
            VStack(spacing: 0) {
                // Header row
                HStack(alignment: .top, spacing: 0) {
                    ForEach(0..<headers.count, id: \.self) { index in
                        Text(headers[index])
                            .font(.system(size: 14, weight: .semibold))
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(headerBackground)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                
                // Data rows
                ForEach(0..<rows.count, id: \.self) { rowIndex in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(0..<headers.count, id: \.self) { colIndex in
                            let cellText = colIndex < rows[rowIndex].count ? rows[rowIndex][colIndex] : ""
                            Text(cellText)
                                .font(.system(size: 13))
                                .textSelection(.enabled)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .overlay(
                Rectangle()
                    .stroke(borderColor, lineWidth: 1)
            )
            .cornerRadius(4)
            .drawingGroup()  // Always rasterize for performance - prevents layout shifts
            .id(tableID)  // Stable ID prevents re-renders during zoom transitions
        }
    }
    
    private var headerBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.05)
    }
    
    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.15)
            : Color.black.opacity(0.15)
    }
}

// MARK: - NSTextView Wrapper

// Custom NSScrollView that prevents scroll event propagation to parent views
@available(macOS 12.0, *)
private class NonPropagatingScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        // Only propagate if we can't scroll in the event direction
        guard let documentView = documentView else {
            super.scrollWheel(with: event)
            return
        }
        
        let scrollDeltaY = event.scrollingDeltaY
        let contentView = self.contentView
        let bounds = contentView.bounds
        let documentFrame = documentView.frame
        
        // Check if we can scroll
        let canScrollUp = bounds.origin.y > 0
        let canScrollDown = bounds.maxY < documentFrame.maxY
        
        let shouldPropagate: Bool
        if scrollDeltaY < 0 {
            // Scrolling down
            shouldPropagate = !canScrollDown
        } else if scrollDeltaY > 0 {
            // Scrolling up
            shouldPropagate = !canScrollUp
        } else {
            shouldPropagate = false
        }
        
        if shouldPropagate {
            // Let parent handle scroll
            nextResponder?.scrollWheel(with: event)
        } else {
            // Handle scroll ourselves
            super.scrollWheel(with: event)
        }
    }
}

@available(macOS 12.0, *)
private struct NSTextViewWrapper: NSViewRepresentable {
    let attributedString: NSAttributedString
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NonPropagatingScrollView()
        
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.size = CGSize(width: 700, height: CGFloat.greatestFiniteMagnitude)
        
        // Set base font to match prompt size (15pt)
        textView.font = .systemFont(ofSize: 15)
        textView.allowsUndo = false
        textView.autoresizingMask = [.width]
        
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        let width: CGFloat = {
            if scrollView.bounds.width > 0 { return scrollView.bounds.width }
            if let superWidth = scrollView.superview?.bounds.width, superWidth > 0 { return superWidth }
            return 700
        }()
        textView.textContainer?.size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        
        if textView.attributedString() != attributedString {
            textView.textStorage?.setAttributedString(attributedString)
            
            // Force layout to ensure all attributes are applied
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        }
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    }
    
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let textView = nsView.documentView as? NSTextView else {
            return nil
        }
        
        let measuredWidth: CGFloat = {
            if let w = proposal.width, w > 0 { return w }
            if nsView.bounds.width > 0 { return nsView.bounds.width }
            return 700
        }()
        
        textView.textContainer?.size = CGSize(width: measuredWidth, height: CGFloat.greatestFiniteMagnitude)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let height = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0
        
        return CGSize(width: measuredWidth, height: height)
    }
}
