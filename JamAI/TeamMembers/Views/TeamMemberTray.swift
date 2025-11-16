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
    let onSettings: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Role icon
            if let role = role {
                Image(systemName: role.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(trayTextColor)
            }
            
            // Team member role (Expert-level by default)
            VStack(alignment: .leading, spacing: 2) {
                if let role = role {
                    Text(teamMember.displayName(with: role))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(trayTextColor.opacity(0.95))
                }
            }
            
            Spacer()
            
            // Settings button
            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundColor(trayTextColor.opacity(0.8))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Edit Team Member")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(trayBackground)
    }
    
    private var trayBackground: some View {
        if let role = role, let nodeColor = NodeColor.color(for: role.color) {
            // Use role color for tray
            return AnyView(nodeColor.color)
        } else {
            // Default pink/magenta color
            return AnyView(Color.pink)
        }
    }
    
    private var trayTextColor: Color {
        if let role = role, let nodeColor = NodeColor.color(for: role.color) {
            return nodeColor.textColor(for: nodeColor.color)
        } else {
            return .white
        }
    }
}
