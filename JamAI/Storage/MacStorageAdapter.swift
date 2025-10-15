#if canImport(AppKit)
import Foundation

struct MacStorageAdapter: StorageAdapter {
    func defaultSaveLocation(for project: Project) throws -> URL {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let projectsURL = documentsURL.appendingPathComponent("JamAI Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: true)
        let sanitizedName = project.name.replacingOccurrences(of: "/", with: "-")
        return projectsURL.appendingPathComponent(sanitizedName)
    }

    func ensureProjectBundle(at baseURL: URL) throws -> URL {
        let bundleURL = normalizeProjectURL(baseURL)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        return bundleURL
    }

    func normalizeProjectURL(_ url: URL) -> URL {
        if url.pathExtension == Config.jamFileExtension { return url }
        return url.appendingPathExtension(Config.jamFileExtension)
    }

    @discardableResult
    func startAccessing(_ bundleURL: URL) -> Bool {
        bundleURL.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ bundleURL: URL) {
        bundleURL.stopAccessingSecurityScopedResource()
    }

    func openWritableDatabase(at bundleURL: URL) throws -> Database {
        let dbURL = bundleURL.appendingPathComponent("data.db")
        let db = Database()
        try db.setup(at: dbURL)
        return db
    }

    func saveMetadata(_ project: Project, at bundleURL: URL) throws {
        let formatter = ISO8601DateFormatter()
        let metadata: [String: Any] = [
            "version": "1.0",
            "projectId": project.id.uuidString,
            "projectName": project.name,
            "createdAt": formatter.string(from: project.createdAt),
            "updatedAt": formatter.string(from: project.updatedAt)
        ]
        let url = bundleURL.appendingPathComponent("metadata.json")
        let data = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
        try data.write(to: url, options: .atomic)
    }
}
#endif
