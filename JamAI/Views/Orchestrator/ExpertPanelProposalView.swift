//
//  ExpertPanelProposalView.swift
//  JamAI
//
//  UI for displaying and approving proposed expert roles
//

import SwiftUI

struct ExpertPanelProposalView: View {
    @Binding var session: OrchestratorSession
    let onApprove: () -> Void
    let onCancel: () -> Void
    
    @State private var isHoveringApprove = false
    @State private var isHoveringCancel = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Jam Squad")
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text("Assemble an expert panel for this question")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Divider()
            
            // Proposed roles list
            VStack(alignment: .leading, spacing: 12) {
                Text("Recommended Specialists")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                
                ForEach($session.proposedRoles) { $role in
                    ProposedRoleRow(
                        proposedRole: $role,
                        role: RoleManager.shared.role(withId: role.roleId)
                    )
                }
            }
            
            // Credit estimate
            if !session.proposedRoles.isEmpty {
                HStack {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    
                    Text("Estimated: ~\(estimatedCredits) credits")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
            
            Divider()
            
            // Action buttons
            HStack {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isHoveringCancel ? Color.secondary.opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { isHoveringCancel = $0 }
                
                Spacer()
                
                Button(action: onApprove) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                        Text("Assemble Team")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(hasApprovedRoles ? Color.accentColor : Color.gray)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!hasApprovedRoles)
                .onHover { isHoveringApprove = $0 }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var hasApprovedRoles: Bool {
        session.proposedRoles.contains { $0.isApproved }
    }
    
    private var estimatedCredits: Int {
        // Rough estimate: 4 credits per role (question + response) + 2 for synthesis
        let approvedCount = session.proposedRoles.filter { $0.isApproved }.count
        return (approvedCount * 4) + 2
    }
}

// MARK: - Proposed Role Row

struct ProposedRoleRow: View {
    @Binding var proposedRole: ProposedRole
    let role: Role?
    
    @State private var isExpanded = false
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main row
            HStack(spacing: 12) {
                // Checkbox
                Button(action: { proposedRole.isApproved.toggle() }) {
                    Image(systemName: proposedRole.isApproved ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18))
                        .foregroundColor(proposedRole.isApproved ? .accentColor : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Role icon and color
                if let role = role {
                    Circle()
                        .fill(roleColor(role.color))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: role.icon)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        )
                }
                
                // Role info
                VStack(alignment: .leading, spacing: 2) {
                    Text(proposedRole.roleName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(proposedRole.isApproved ? .primary : .secondary)
                    
                    Text(proposedRole.justification)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(isExpanded ? nil : 1)
                }
                
                Spacer()
                
                // Expand button
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Expanded: Show tailored question
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Question for this specialist:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text(proposedRole.tailoredQuestion)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.1))
                        )
                }
                .padding(.leading, 44)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.secondary.opacity(0.08) : Color.clear)
        )
        .onHover { isHovering = $0 }
    }
    
    private func roleColor(_ colorName: String) -> Color {
        switch colorName.lowercased() {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "pink": return .pink
        case "orange": return .orange
        case "indigo": return .indigo
        case "teal": return .teal
        case "yellow": return .yellow
        case "red": return .red
        case "cyan": return .cyan
        case "mint": return .mint
        case "brown": return .brown
        default: return .gray
        }
    }
}

// MARK: - Preview

#Preview {
    ExpertPanelProposalView(
        session: .constant(OrchestratorSession(
            masterNodeId: UUID(),
            projectId: UUID(),
            originalPrompt: "How should I architect a real-time whiteboard?",
            status: .awaitingApproval,
            proposedRoles: [
                ProposedRole(
                    roleId: "backend-developer",
                    roleName: "Backend Developer",
                    justification: "For database and real-time sync architecture",
                    tailoredQuestion: "What database and sync strategy would you recommend?"
                ),
                ProposedRole(
                    roleId: "frontend-developer",
                    roleName: "Frontend Developer",
                    justification: "For canvas rendering and state management",
                    tailoredQuestion: "What frontend framework would work best?"
                )
            ]
        )),
        onApprove: {},
        onCancel: {}
    )
    .frame(width: 400)
    .padding()
}
