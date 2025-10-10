//
//  MarkdownText.swift
//  JamAI
//
//  Properly formatted markdown text view
//

import SwiftUI

struct MarkdownText: View {
    let text: String
    
    var body: some View {
        if #available(macOS 12.0, *) {
            Text(.init(text))
                .textSelection(.enabled)
        } else {
            Text(text)
                .textSelection(.enabled)
        }
    }
}
