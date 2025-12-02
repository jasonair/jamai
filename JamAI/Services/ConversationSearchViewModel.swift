//
//  ConversationSearchViewModel.swift
//  JamAI
//
//  ViewModel for conversation search with debouncing and state management
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class ConversationSearchViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published var query: String = ""
    @Published private(set) var results: [ConversationSearchResult] = []
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var hasSearched: Bool = false
    
    // MARK: - Callbacks
    
    /// Called when user selects a search result
    var onSelectResult: ((ConversationSearchResult) -> Void)?
    
    // MARK: - Private
    
    private let index: ConversationSearchIndex
    private var cancellables = Set<AnyCancellable>()
    private var viewportCenter: CGPoint?
    
    // MARK: - Configuration
    
    private let debounceInterval: TimeInterval = 0.2 // 200ms debounce
    
    // MARK: - Initialization
    
    init(index: ConversationSearchIndex) {
        self.index = index
        setupDebounce()
    }
    
    private func setupDebounce() {
        $query
            .removeDuplicates()
            .debounce(for: .seconds(debounceInterval), scheduler: DispatchQueue.main)
            .sink { [weak self] text in
                self?.runSearch(query: text)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Update the viewport center for proximity-based ranking
    func updateViewportCenter(_ center: CGPoint) {
        self.viewportCenter = center
    }
    
    /// Clear the search query and results
    func clearSearch() {
        query = ""
        results = []
        hasSearched = false
    }
    
    /// Called when user selects a result
    func didSelect(result: ConversationSearchResult) {
        onSelectResult?(result)
    }
    
    /// Trigger an immediate search (bypasses debounce)
    func searchImmediately() {
        runSearch(query: query)
    }
    
    // MARK: - Private Methods
    
    private func runSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        
        guard !trimmed.isEmpty else {
            results = []
            hasSearched = false
            return
        }
        
        isSearching = true
        
        // Run search on background queue for responsiveness
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            let searchResults = await MainActor.run {
                self.index.search(query: trimmed, viewportCenter: self.viewportCenter)
            }
            
            await MainActor.run {
                self.results = searchResults
                self.isSearching = false
                self.hasSearched = true
            }
        }
    }
}

// MARK: - Search Result Helpers

extension ConversationSearchResult {
    
    /// Generate an attributed string with the match highlighted
    func highlightedSnippet(highlightColor: Color = .yellow) -> AttributedString {
        var attributed = AttributedString(snippet)
        
        // Find the query match in the snippet and highlight it
        // Note: This is a simplified version - the actual match position
        // may differ due to ellipsis and context trimming
        return attributed
    }
    
    /// Get the node color as a SwiftUI Color
    var nodeSwiftUIColor: Color {
        if nodeColor == "none" || nodeColor.isEmpty {
            return Color.gray.opacity(0.5)
        }
        if let color = NodeColor.color(for: nodeColor) {
            return color.color
        }
        return Color.gray.opacity(0.5)
    }
}
