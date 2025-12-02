//
//  SearchModal.swift
//  JamAI
//
//  Command-palette style search modal for finding conversations
//

import SwiftUI

struct SearchModal: View {
    @ObservedObject var viewModel: ConversationSearchViewModel
    let onDismiss: () -> Void
    
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Search bar
            searchBarView
                .padding()
            
            // Results
            if !viewModel.query.isEmpty {
                Divider()
                resultsView
            }
        }
        .frame(width: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .allowsHitTesting(true)
        .onAppear {
            // Focus search on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
            
            Text("Search Conversations")
                .font(.system(size: 18, weight: .semibold))
            
            Spacer()
            
            // Keyboard shortcut hint
            Text("⌘F")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(4)
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
    }
    
    // MARK: - Search Bar
    
    private var searchBarView: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            
            TextField("Search for text in nodes...", text: $viewModel.query)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 15))
                .focused($isSearchFocused)
                .onSubmit {
                    // Select first result on Enter
                    if let first = viewModel.results.first {
                        viewModel.didSelect(result: first)
                        onDismiss()
                    }
                }
            
            if viewModel.isSearching {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            }
            
            if !viewModel.query.isEmpty {
                Button(action: { viewModel.clearSearch() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Results
    
    private var resultsView: some View {
        Group {
            if viewModel.results.isEmpty && viewModel.hasSearched {
                // No results
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("No results found")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    
                    Text("Try different keywords")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if !viewModel.results.isEmpty {
                // Results list
                VStack(alignment: .leading, spacing: 4) {
                    // Results count
                    HStack {
                        Text("\(viewModel.results.count) result\(viewModel.results.count == 1 ? "" : "s")")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.results) { result in
                                SearchResultRow(
                                    result: result,
                                    query: viewModel.query,
                                    onSelect: {
                                        viewModel.didSelect(result: result)
                                        onDismiss()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                }
                .frame(maxHeight: 400) // Cap height similar to TeamMemberModal
            }
        }
    }
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let result: ConversationSearchResult
    let query: String
    let onSelect: () -> Void
    
    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                // Node title row
                HStack(spacing: 8) {
                    // Color indicator
                    Circle()
                        .fill(result.nodeSwiftUIColor)
                        .frame(width: 8, height: 8)
                    
                    // Node title
                    Text(result.nodeTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Navigate hint
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .opacity(isHovered ? 1 : 0.5)
                }
                
                // Snippet with highlighted match
                highlightedSnippetView
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered 
                        ? Color.accentColor.opacity(0.1) 
                        : Color.secondary.opacity(colorScheme == .dark ? 0.1 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    // MARK: - Highlighted Snippet
    
    @ViewBuilder
    private var highlightedSnippetView: some View {
        let snippet = result.snippet
        let lowercaseSnippet = snippet.lowercased()
        let lowercaseQuery = query.lowercased()
        
        // Find match range in snippet
        if let range = lowercaseSnippet.range(of: lowercaseQuery) {
            let startIndex = snippet.distance(from: snippet.startIndex, to: range.lowerBound)
            let endIndex = snippet.distance(from: snippet.startIndex, to: range.upperBound)
            
            let before = String(snippet.prefix(startIndex))
            let match = String(snippet[snippet.index(snippet.startIndex, offsetBy: startIndex)..<snippet.index(snippet.startIndex, offsetBy: endIndex)])
            let after = String(snippet.suffix(from: snippet.index(snippet.startIndex, offsetBy: endIndex)))
            
            // Use string interpolation instead of deprecated Text concatenation
            HStack(spacing: 0) {
                Text(before)
                Text(match)
                    .foregroundColor(.accentColor)
                    .fontWeight(.semibold)
                Text(after)
            }
        } else {
            Text(snippet)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SearchModal_Previews: PreviewProvider {
    static var previews: some View {
        SearchModal(
            viewModel: ConversationSearchViewModel(index: ConversationSearchIndex()),
            onDismiss: {}
        )
        .frame(height: 500)
    }
}
#endif
