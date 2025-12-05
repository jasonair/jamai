//
//  BackupService.swift
//  JamAI
//
//  Manages automatic backups of project databases to prevent data loss
//

import Foundation

/// Service for managing project backups
/// Keeps rolling backups of the database to prevent data loss
class BackupService {
    static let shared = BackupService()
    
    private let fileManager = FileManager.default
    private let backupFolderName = "Backups"
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
    
    // Track last backup time per project to avoid too-frequent backups
    private var lastAutoBackupTime: [URL: Date] = [:]
    private let autoBackupInterval: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    // MARK: - Public API
    
    /// Create a backup of the database when opening a project
    func createBackupOnOpen(projectURL: URL) {
        let bundleURL = normalizeToBundle(projectURL)
        let dbURL = bundleURL.appendingPathComponent("data.db")
        
        guard fileManager.fileExists(atPath: dbURL.path) else {
            if Config.enableVerboseLogging {
                print("📦 No database to backup at: \(dbURL.path)")
            }
            return
        }
        
        do {
            try createBackup(dbURL: dbURL, bundleURL: bundleURL, reason: "open")
            cleanupOldBackups(bundleURL: bundleURL)
            if Config.enableVerboseLogging {
                print("📦 Created backup on project open")
            }
        } catch {
            print("⚠️ Failed to create backup on open: \(error.localizedDescription)")
        }
    }
    
    /// Create a periodic auto-backup if enough time has passed
    /// Called during autosave - only creates backup every 5 minutes
    func createPeriodicBackupIfNeeded(projectURL: URL) {
        let bundleURL = normalizeToBundle(projectURL)
        let dbURL = bundleURL.appendingPathComponent("data.db")
        
        guard fileManager.fileExists(atPath: dbURL.path) else { return }
        
        // Check if enough time has passed since last auto-backup
        let now = Date()
        if let lastBackup = lastAutoBackupTime[bundleURL],
           now.timeIntervalSince(lastBackup) < autoBackupInterval {
            return // Too soon for another backup
        }
        
        do {
            try createBackup(dbURL: dbURL, bundleURL: bundleURL, reason: "autosave")
            lastAutoBackupTime[bundleURL] = now
            cleanupOldBackups(bundleURL: bundleURL)
            if Config.enableVerboseLogging {
                print("📦 Created periodic auto-backup")
            }
        } catch {
            print("⚠️ Failed to create periodic backup: \(error.localizedDescription)")
        }
    }
    
    /// Create a backup before a potentially risky operation
    func createBackupBeforeOperation(projectURL: URL, reason: String) {
        let bundleURL = normalizeToBundle(projectURL)
        let dbURL = bundleURL.appendingPathComponent("data.db")
        
        guard fileManager.fileExists(atPath: dbURL.path) else { return }
        
        do {
            try createBackup(dbURL: dbURL, bundleURL: bundleURL, reason: reason)
            cleanupOldBackups(bundleURL: bundleURL)
            if Config.enableVerboseLogging {
                print("📦 Created backup before: \(reason)")
            }
        } catch {
            print("⚠️ Failed to create backup before \(reason): \(error.localizedDescription)")
        }
    }
    
    /// Get list of available backups for a project (newest first)
    func getAvailableBackups(projectURL: URL) -> [BackupInfo] {
        let bundleURL = normalizeToBundle(projectURL)
        let backupsURL = bundleURL.appendingPathComponent(backupFolderName)
        
        guard fileManager.fileExists(atPath: backupsURL.path) else { return [] }
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: backupsURL,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
            )
            
            return contents
                .filter { $0.pathExtension == "db" }
                .compactMap { url -> BackupInfo? in
                    guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                          let createdAt = attrs[.creationDate] as? Date,
                          let size = attrs[.size] as? Int64 else {
                        return nil
                    }
                    
                    // Parse reason from filename: data_backup_REASON_TIMESTAMP.db
                    let filename = url.deletingPathExtension().lastPathComponent
                    let components = filename.components(separatedBy: "_")
                    let reason = components.count >= 3 ? components[2] : "unknown"
                    
                    return BackupInfo(
                        url: url,
                        createdAt: createdAt,
                        sizeBytes: size,
                        reason: reason
                    )
                }
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            print("⚠️ Failed to list backups: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Restore a project from a backup
    func restoreFromBackup(_ backup: BackupInfo, projectURL: URL) throws {
        let bundleURL = normalizeToBundle(projectURL)
        let dbURL = bundleURL.appendingPathComponent("data.db")
        
        // Backup current state before restoring (in case user wants to undo)
        if fileManager.fileExists(atPath: dbURL.path) {
            do {
                try createBackup(dbURL: dbURL, bundleURL: bundleURL, reason: "pre-restore")
            } catch {
                // Continue with restore even if pre-restore backup fails
                print("⚠️ Could not backup current database before restore: \(error.localizedDescription)")
            }
        }
        
        // Replace database with backup
        if fileManager.fileExists(atPath: dbURL.path) {
            try fileManager.removeItem(at: dbURL)
        }
        try fileManager.copyItem(at: backup.url, to: dbURL)
        
        if Config.enableVerboseLogging {
            print("📦 Restored from backup: \(backup.url.lastPathComponent)")
        }
    }
    
    /// Delete a specific backup
    func deleteBackup(_ backup: BackupInfo) throws {
        try fileManager.removeItem(at: backup.url)
        if Config.enableVerboseLogging {
            print("📦 Deleted backup: \(backup.url.lastPathComponent)")
        }
    }
    
    // MARK: - Private Helpers
    
    private func normalizeToBundle(_ url: URL) -> URL {
        if url.pathExtension == Config.jamFileExtension {
            return url
        }
        return url.appendingPathExtension(Config.jamFileExtension)
    }
    
    private func createBackup(dbURL: URL, bundleURL: URL, reason: String) throws {
        let backupsURL = bundleURL.appendingPathComponent(backupFolderName)
        
        // Create backups folder if needed
        if !fileManager.fileExists(atPath: backupsURL.path) {
            try fileManager.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        }
        
        // Generate backup filename with timestamp and reason
        let timestamp = dateFormatter.string(from: Date())
        let sanitizedReason = reason
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .prefix(20)
        let backupName = "data_backup_\(sanitizedReason)_\(timestamp).db"
        let backupURL = backupsURL.appendingPathComponent(backupName)
        
        // Copy database to backup location
        try fileManager.copyItem(at: dbURL, to: backupURL)
    }
    
    private func cleanupOldBackups(bundleURL: URL) {
        let backupsURL = bundleURL.appendingPathComponent(backupFolderName)
        
        guard fileManager.fileExists(atPath: backupsURL.path) else { return }
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: backupsURL,
                includingPropertiesForKeys: [.creationDateKey]
            ).filter { $0.pathExtension == "db" }
            
            // Sort by creation date, oldest first
            let sorted = contents.compactMap { url -> (URL, Date)? in
                guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                      let date = attrs[.creationDate] as? Date else {
                    return nil
                }
                return (url, date)
            }.sorted { $0.1 < $1.1 }
            
            // Keep only the most recent N backups
            let maxBackups = Config.maxAutosaveBackups
            if sorted.count > maxBackups {
                let toDelete = sorted.prefix(sorted.count - maxBackups)
                for (url, _) in toDelete {
                    try? fileManager.removeItem(at: url)
                    if Config.enableVerboseLogging {
                        print("📦 Deleted old backup: \(url.lastPathComponent)")
                    }
                }
            }
        } catch {
            print("⚠️ Failed to cleanup old backups: \(error.localizedDescription)")
        }
    }
}

// MARK: - BackupInfo

/// Information about a backup file
struct BackupInfo: Identifiable {
    let id = UUID()
    let url: URL
    let createdAt: Date
    let sizeBytes: Int64
    let reason: String
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
    
    var reasonDisplay: String {
        switch reason {
        case "open": return "Project opened"
        case "pre-restore": return "Before restore"
        case "autosave": return "Auto-save"
        default: return reason.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }
}
