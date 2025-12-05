//
//  BackupListView.swift
//  JamAI
//
//  Shows available backups and allows restoration
//

import SwiftUI

struct BackupListView: View {
    let projectURL: URL
    let onRestore: () -> Void
    let onDismiss: () -> Void
    
    @State private var backups: [BackupInfo] = []
    @State private var selectedBackup: BackupInfo?
    @State private var showRestoreConfirmation = false
    @State private var isRestoring = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project Backups")
                        .font(.headline)
                    Text("Restore your project from a previous backup")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            if backups.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No Backups Available")
                        .font(.headline)
                    
                    Text("Backups are created automatically when you open a project and every 5 minutes during active use.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                // Backup list
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(backups) { backup in
                            BackupRowView(
                                backup: backup,
                                isSelected: selectedBackup?.id == backup.id,
                                onSelect: { selectedBackup = backup }
                            )
                        }
                    }
                    .padding()
                }
                
                Divider()
                
                // Action buttons
                HStack {
                    if let selected = selectedBackup {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Selected: \(selected.formattedDate)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(selected.reasonDisplay)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button("Cancel") {
                        onDismiss()
                    }
                    .keyboardShortcut(.escape)
                    
                    Button("Restore Selected") {
                        showRestoreConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedBackup == nil || isRestoring)
                }
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(width: 500, height: 450)
        .onAppear {
            loadBackups()
        }
        .alert("Restore Backup?", isPresented: $showRestoreConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                restoreSelectedBackup()
            }
        } message: {
            Text("This will replace your current project data with the backup from \(selectedBackup?.formattedDate ?? "unknown date"). A backup of the current state will be created first.")
        }
        .alert("Restore Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .overlay {
            if isRestoring {
                Color.black.opacity(0.3)
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Restoring backup...")
                        .font(.headline)
                        .padding(.top)
                }
                .padding(40)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private func loadBackups() {
        backups = BackupService.shared.getAvailableBackups(projectURL: projectURL)
    }
    
    private func restoreSelectedBackup() {
        guard let backup = selectedBackup else { return }
        
        isRestoring = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try BackupService.shared.restoreFromBackup(backup, projectURL: projectURL)
                
                DispatchQueue.main.async {
                    isRestoring = false
                    onRestore()
                }
            } catch {
                DispatchQueue.main.async {
                    isRestoring = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

struct BackupRowView: View {
    let backup: BackupInfo
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon based on reason
            Image(systemName: iconForReason(backup.reason))
                .font(.title2)
                .foregroundColor(colorForReason(backup.reason))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(backup.formattedDate)
                    .font(.system(.body, design: .default))
                
                HStack(spacing: 8) {
                    Text(backup.reasonDisplay)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(backup.formattedSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
    
    private func iconForReason(_ reason: String) -> String {
        switch reason {
        case "open": return "folder.badge.gearshape"
        case "autosave": return "clock.arrow.circlepath"
        case "pre-restore": return "arrow.counterclockwise"
        default: return "doc.badge.clock"
        }
    }
    
    private func colorForReason(_ reason: String) -> Color {
        switch reason {
        case "open": return .blue
        case "autosave": return .green
        case "pre-restore": return .orange
        default: return .secondary
        }
    }
}
