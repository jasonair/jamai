//
//  MarkdownText.swift
//  JamAI
//
//  Properly formatted markdown text view with table and bullet support
//

import SwiftUI

struct MarkdownText: View {
    let text: String
    var onCopy: ((String) -> Void)?
    
    @State private var showCopiedToast = false
    @State private var cachedBlocks: [MarkdownBlock] = []
    @State private var parseTask: Task<Void, Never>?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(cachedBlocks, id: \.id) { block in
                Group {
                    switch block.type {
                    case .table(let headers, let rows):
                        // Tables take full width
                        MarkdownTableView(headers: headers, rows: rows)
                            .padding(.bottom, 20)
                    case .text(let content):
                        // Text is centered with max reading width
                        HStack {
                            Spacer(minLength: 0)
                            FormattedTextView(content: content)
                                .frame(maxWidth: 700)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            
            // Copy button at the end
            if let onCopy = onCopy {
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
                .padding(.top, 4)
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
            parseTask = Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                
                // Check if task was cancelled
                guard !Task.isCancelled else { return }
                
                // Parse on main actor to update UI
                await MainActor.run {
                    cachedBlocks = parseMarkdownBlocks(newValue)
                }
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
    
    var body: some View {
        if #available(macOS 12.0, *) {
            let formatted = formatText(content)
            Text(formatted)
                .textSelection(.enabled)
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
            // Increase font size ONLY for standalone section headers (bold text with colon at start of line)
            let fullText = String(attributed.characters)
            
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
                            attributed[run.range].font = .system(size: 19, weight: .heavy)
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
        
        // Check if this is a table row (contains pipes)
        if line.contains("|") && line.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
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
    let headers = parseTableRow(headerLine)
    
    // Second line should be separator (|---|---|), skip it
    let separatorLine = cleanLines[1]
    let isSeparator = separatorLine.contains("-")
    let startIndex = isSeparator ? 2 : 1
    
    // Remaining lines are data rows
    var rows: [[String]] = []
    for i in startIndex..<cleanLines.count {
        let row = parseTableRow(cleanLines[i])
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

// MARK: - Table View

private struct MarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(0..<headers.count, id: \.self) { index in
                    ZStack {
                        headerBackground
                        Text(headers[index])
                            .font(.system(size: 14, weight: .semibold))
                            .textSelection(.enabled)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity)
                    
                    if index < headers.count - 1 {
                        Divider()
                    }
                }
            }
            .overlay(
                Rectangle()
                    .stroke(borderColor, lineWidth: 1)
            )
            
            // Data rows
            ForEach(0..<rows.count, id: \.self) { rowIndex in
                HStack(spacing: 0) {
                    ForEach(0..<min(headers.count, rows[rowIndex].count), id: \.self) { colIndex in
                        let cellText = rows[rowIndex][colIndex]
                        if #available(macOS 12.0, *) {
                            Text(.init(cellText))
                                .font(.body)
                                .textSelection(.enabled)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(cellText)
                                .font(.body)
                                .textSelection(.enabled)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        if colIndex < headers.count - 1 {
                            Divider()
                        }
                    }
                }
                .overlay(
                    Rectangle()
                        .stroke(borderColor, lineWidth: 1)
                )
            }
        }
        .cornerRadius(4)
        .fixedSize(horizontal: false, vertical: true)
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
