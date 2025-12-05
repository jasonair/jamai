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
    @State private var isPersonalityPickerPresented = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Clickable role icon and name - launches edit modal
            Button(action: onSettings) {
                HStack(spacing: 8) {
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
                }
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .help("Edit Team Member")
            
            Spacer()
            
            // Personality dropdown (custom popover for full color control)
            Button(action: {
                isPersonalityPickerPresented.toggle()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                    Text(personality.displayName)
                }
                .font(.system(size: 11))
                .foregroundColor(trayTextColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(trayTextColor.opacity(0.15))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .help("Change AI personality for this node")
            .popover(
                isPresented: $isPersonalityPickerPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Personality.allCases, id: \.self) { option in
                        Button(action: {
                            onPersonalityChange(option)
                            isPersonalityPickerPresented = false
                        }) {
                            HStack {
                                if option == personality {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(trayTextColor)
                                } else {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .medium))
                                        .opacity(0)
                                }
                                Text(option.displayName)
                                    .font(.system(size: 11))
                                    .foregroundColor(trayTextColor)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(trayBaseColor.opacity(0.95))
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(trayBackground)
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
