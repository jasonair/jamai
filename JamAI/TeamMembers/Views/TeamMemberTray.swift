//
//  TeamMemberTray.swift
//  JamAI
//
//  Displays the team member info in a horizontal tray at the top of a node
//

import SwiftUI

struct TeamMemberTray: View {
    let teamMember: TeamMember
    let role: Role?
    let personality: Personality
    let onSettings: () -> Void
    let onPersonalityChange: (Personality) -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        // Entire tray is clickable to open settings
        Button(action: onSettings) {
            HStack(spacing: 12) {
                // Role icon
                if let role = role {
                    Image(systemName: role.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(trayTextColor)
                }
                
                // Team member role name
                if let role = role {
                    Text(teamMember.displayName(with: role))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(trayTextColor.opacity(0.95))
                }
                
                Spacer()
                
                // Personality badge (non-interactive, just shows current)
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                    Text(personality.displayName)
                }
                .font(.system(size: 11))
                .foregroundColor(trayTextColor.opacity(0.8))
                
                // Gear icon for settings
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundColor(trayTextColor.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(trayBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .help("Edit Team Member Settings")
    }
    
    private var trayBaseColor: Color {
        if let role = role, let nodeColor = NodeColor.color(for: role.color) {
            return nodeColor.color
        } else {
            return Color.pink
        }
    }
    
    private var trayBackground: some View {
        AnyView(trayBaseColor)
    }
    
    private var trayTextColor: Color {
        if let role = role, let nodeColor = NodeColor.color(for: role.color) {
            return nodeColor.textColor(for: nodeColor.color)
        } else {
            return .white
        }
    }
}
