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
            print("📄 Found roles.json at: \(url.path)")
            print("📄 File size: \(data.count) bytes")
            
            let decoder = JSONDecoder()
            roles = try decoder.decode([Role].self, from: data)
            isLoaded = true
            print("✅ Successfully loaded \(roles.count) roles")
            
            // Print first 3 roles
            for (i, role) in roles.prefix(3).enumerated() {
                print("  \(i+1). \(role.name) - \(role.category.displayName)")
            }
        } catch let DecodingError.keyNotFound(key, context) {
            print("❌ Decoding error - Missing key: '\(key.stringValue)'")
            print("   Path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            print("   Debug: \(context.debugDescription)")
        } catch let DecodingError.typeMismatch(type, context) {
            print("❌ Decoding error - Type mismatch for: \(type)")
            print("   Path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            print("   Debug: \(context.debugDescription)")
        } catch {
            print("❌ Error loading roles: \(error)")
            print("   Type: \(type(of: error))")
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
