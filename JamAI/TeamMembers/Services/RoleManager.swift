//
//  RoleManager.swift
//  JamAI
//
//  Manages loading and accessing role definitions
//

import Foundation
import Combine

@MainActor
final class RoleManager: ObservableObject {
    static let shared = RoleManager()
    
    @Published private(set) var roles: [Role] = []
    @Published private(set) var isLoaded = false
    
    private init() {
        loadRoles()
    }
    
    /// Load roles from local JSON file
    func loadRoles() {
        // Try multiple paths to find the roles.json file
        let possiblePaths = [
            Bundle.main.url(forResource: "roles", withExtension: "json"),
            Bundle.main.url(forResource: "roles", withExtension: "json", subdirectory: "TeamMembers/Resources"),
            Bundle.main.url(forResource: "roles", withExtension: "json", subdirectory: "Resources")
        ]
        
        guard let url = possiblePaths.compactMap({ $0 }).first else {
            print("⚠️ Could not find roles.json in bundle")
            print("📂 Searched paths:")
            print("   - Root of bundle")
            print("   - TeamMembers/Resources subdirectory")
            print("   - Resources subdirectory")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            print("📄 Found roles.json, file size: \(data.count) bytes")
            
            let decoder = JSONDecoder()
            roles = try decoder.decode([Role].self, from: data)
            isLoaded = true
            print("✅ Loaded \(roles.count) roles from \(url.lastPathComponent)")
            
            // List first 3 roles
            for (index, role) in roles.prefix(3).enumerated() {
                print("  \(index + 1). \(role.name) (\(role.industry.displayName) - \(role.category.displayName))")
            }
        } catch let DecodingError.keyNotFound(key, context) {
            print("❌ Missing key '\(key.stringValue)' - \(context.debugDescription)")
            print("   Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
        } catch let DecodingError.typeMismatch(type, context) {
            print("❌ Type mismatch for type '\(type)' - \(context.debugDescription)")
            print("   Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
        } catch let DecodingError.valueNotFound(type, context) {
            print("❌ Value not found for type '\(type)' - \(context.debugDescription)")
            print("   Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
        } catch {
            print("❌ Error loading roles: \(error)")
            print("   Error type: \(type(of: error))")
        }
    }
    
    /// Get a specific role by ID
    func role(withId id: String) -> Role? {
        roles.first(where: { $0.id == id })
    }
    
    /// Get all roles in a category
    func roles(in category: RoleCategory) -> [Role] {
        roles.filter { $0.category == category }
    }
    
    /// Search roles by name or description
    func searchRoles(query: String) -> [Role] {
        guard !query.isEmpty else { return roles }
        
        let lowercasedQuery = query.lowercased()
        return roles.filter { role in
            role.name.lowercased().contains(lowercasedQuery) ||
            role.description.lowercased().contains(lowercasedQuery) ||
            role.category.displayName.lowercased().contains(lowercasedQuery)
        }
    }
    
    /// Get available experience levels for a role based on plan tier
    func availableLevels(for role: Role, tier: PlanTier = .free) -> [ExperienceLevel] {
        ExperienceLevel.allCases.filter { level in
            role.isLevelAvailable(level, for: tier)
        }
    }
}
