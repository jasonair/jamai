//
//  TabBarView.swift
//  JamAI
//
//  Tab bar for managing multiple open projects
//

import SwiftUI

struct TabBarView: View {
    let tabs: [ProjectTab]
    let activeTabId: UUID?
    let onTabSelect: (UUID) -> Void
    let onTabClose: (UUID) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    TabItemView(
                        tab: tab,
                        isActive: tab.id == activeTabId,
                        onSelect: { onTabSelect(tab.id) },
                        onClose: { onTabClose(tab.id) }
                    )
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 36)
    }
}

struct TabItemView: View {
    let tab: ProjectTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundColor(isActive ? .accentColor : .secondary)
            
            Text(tab.projectName)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 14, height: 14)
                    .background(
                        Circle()
                            .fill(isHovering ? Color.secondary.opacity(0.2) : Color.clear)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(isHovering || isActive ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
