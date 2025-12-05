//
//  OrchestratorStatusView.swift
//  JamAI
//
//  Shows the status of an orchestration session in the master node
//

import SwiftUI

struct OrchestratorStatusView: View {
    let session: OrchestratorSession
    let onCancel: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with status
            HStack(spacing: 10) {
                // Status icon with animation
                statusIcon
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.status.displayName)
                        .font(.system(size: 14, weight: .semibold))
                    
                    if session.status.isActive {
                        Text(statusSubtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Cancel button for active sessions
                if session.status.isActive, let onCancel = onCancel {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Progress bar
            if session.status == .consulting {
                ProgressView(value: session.progress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .tint(.accentColor)
            }
            
            // Delegate status list
            if !session.delegateStatuses.isEmpty && session.status == .consulting {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(session.delegateStatuses) { delegate in
                        DelegateStatusRow(delegate: delegate)
                    }
                }
            }
            
            // Completion message
            if session.status == .completed {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    
                    Text("Expert panel consultation complete")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(statusBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(statusBorderColor, lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(statusIconBackground)
                .frame(width: 32, height: 32)
            
            if session.status.isActive {
                // Animated icon for active states
                Image(systemName: session.status.icon)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .rotationEffect(session.status == .consulting ? .degrees(360) : .zero)
                    .animation(
                        session.status == .consulting
                            ? .linear(duration: 2).repeatForever(autoreverses: false)
                            : .default,
                        value: session.status
                    )
            } else {
                Image(systemName: session.status.icon)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
        }
    }
    
    private var statusSubtitle: String {
        switch session.status {
        case .proposing:
            return "Analyzing your question..."
        case .awaitingApproval:
            return "Review the proposed specialists"
        case .spawning:
            return "Creating specialist nodes..."
        case .consulting:
            return "\(session.respondedCount)/\(session.totalDelegates) specialists responded"
        case .synthesizing:
            return "Combining expert insights..."
        case .completed:
            return "Consultation complete"
        case .cancelled:
            return "Cancelled by user"
        case .failed:
            return session.errorMessage ?? "An error occurred"
        }
    }
    
    private var statusBackgroundColor: Color {
        switch session.status {
        case .completed:
            return Color.green.opacity(0.1)
        case .failed:
            return Color.red.opacity(0.1)
        case .cancelled:
            return Color.secondary.opacity(0.1)
        default:
            return Color.accentColor.opacity(0.1)
        }
    }
    
    private var statusBorderColor: Color {
        switch session.status {
        case .completed:
            return Color.green.opacity(0.3)
        case .failed:
            return Color.red.opacity(0.3)
        case .cancelled:
            return Color.secondary.opacity(0.3)
        default:
            return Color.accentColor.opacity(0.3)
        }
    }
    
    private var statusIconBackground: Color {
        switch session.status {
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .secondary
        default:
            return .accentColor
        }
    }
}

// MARK: - Delegate Status Row

struct DelegateStatusRow: View {
    let delegate: DelegateStatus
    
    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            statusIndicator
            
            // Role name
            Text(delegate.roleName)
                .font(.system(size: 12))
                .foregroundColor(delegate.status == .responded ? .primary : .secondary)
            
            Spacer()
            
            // Status text
            Text(statusText)
                .font(.system(size: 11))
                .foregroundColor(statusColor)
        }
    }
    
    @ViewBuilder
    private var statusIndicator: some View {
        switch delegate.status {
        case .waiting:
            Circle()
                .stroke(Color.secondary.opacity(0.5), lineWidth: 2)
                .frame(width: 12, height: 12)
        case .thinking:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)
        case .responded:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.red)
        }
    }
    
    private var statusText: String {
        switch delegate.status {
        case .waiting: return "Waiting"
        case .thinking: return "Thinking..."
        case .responded: return "Done"
        case .failed: return "Failed"
        }
    }
    
    private var statusColor: Color {
        switch delegate.status {
        case .waiting: return .secondary
        case .thinking: return .accentColor
        case .responded: return .green
        case .failed: return .red
        }
    }
}

// MARK: - Orchestrator Badge (for node header)

struct OrchestratorBadge: View {
    let role: OrchestratorRole
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: role == .master ? "crown.fill" : "person.fill")
                .font(.system(size: 9))
            
            Text(role == .master ? "Orchestrator" : "Specialist")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(role == .master ? Color.purple : Color.blue)
        )
    }
}

// MARK: - Preview

#Preview("Consulting Status") {
    OrchestratorStatusView(
        session: OrchestratorSession(
            masterNodeId: UUID(),
            projectId: UUID(),
            originalPrompt: "Test",
            status: .consulting,
            delegateStatuses: [
                DelegateStatus(id: UUID(), roleId: "backend", roleName: "Backend Developer", status: .responded),
                DelegateStatus(id: UUID(), roleId: "frontend", roleName: "Frontend Developer", status: .thinking),
                DelegateStatus(id: UUID(), roleId: "ai-ml", roleName: "AI/ML Engineer", status: .waiting)
            ]
        ),
        onCancel: {}
    )
    .frame(width: 350)
    .padding()
}

#Preview("Completed Status") {
    OrchestratorStatusView(
        session: OrchestratorSession(
            masterNodeId: UUID(),
            projectId: UUID(),
            originalPrompt: "Test",
            status: .completed
        ),
        onCancel: nil
    )
    .frame(width: 350)
    .padding()
}
