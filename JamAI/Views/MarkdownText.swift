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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(parseMarkdownBlocks(text), id: \.id) { block in
                switch block.type {
                case .table(let headers, let rows):
                    MarkdownTableView(headers: headers, rows: rows)
                case .text(let content):
                    FormattedTextView(content: content)
                }
            }
            
            // Copy button at the end
            if let onCopy = onCopy {
                HStack {
                    Spacer()
                    Button(action: {
                        onCopy(text)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                            Text("Copy")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true) // Fix disappearing content on resize
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
            // Increase font size for headers (bold text followed by colon)
            for run in attributed.runs {
                if let inlinePresentationIntent = run.inlinePresentationIntent,
                   inlinePresentationIntent.contains(.stronglyEmphasized) {
                    // Check if this bold text is followed by a colon (likely a header)
                    let runText = String(attributed[run.range].characters)
                    if runText.hasSuffix(":") {
                        attributed[run.range].font = .system(size: 15, weight: .semibold)
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
                            .font(.body.weight(.semibold))
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
        .padding(.vertical, 4)
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
