//
//  TeamMemberModal.swift
//  JamAI
//
//  Modal for selecting and configuring a team member
//

import SwiftUI

struct TeamMemberModal: View {
    @StateObject private var roleManager = RoleManager.shared
    @StateObject private var dataService = FirebaseDataService.shared
    
    let existingMember: TeamMember?
    let projectTeamMembers: [(nodeName: String, teamMember: TeamMember, role: Role?)] // Team members already in project
    let onSave: (TeamMember) -> Void
    let onRemove: (() -> Void)?
    let onDismiss: () -> Void
    
    @State private var searchQuery = ""
    @State private var selectedCategory: RoleCategory?
    @State private var selectedRole: Role?
    @State private var selectedLevel: ExperienceLevel = .intermediate
    @State private var customName: String = ""
    
    private var currentTier: PlanTier {
        guard let account = dataService.userAccount else { return .free }
        // Map UserPlan to PlanTier for experience level access
        switch account.plan {
        case .trial, .pro: return .pro
        case .teams, .enterprise: return .enterprise
        case .free: return .free
        }
    }
    
    @FocusState private var isSearchFocused: Bool
    
    var filteredRoles: [Role] {
        var results = roleManager.roles
        
        // Filter by category
        if let category = selectedCategory {
            results = results.filter { $0.category == category }
        }
        
        // Filter by search query
        if !searchQuery.isEmpty {
            results = results.filter { role in
                role.name.localizedCaseInsensitiveContains(searchQuery) ||
                role.description.localizedCaseInsensitiveContains(searchQuery)
            }
        }
        
        return results
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(existingMember == nil ? "Add Team Member" : "Edit Team Member")
                    .font(.system(size: 18, weight: .semibold))
                
                Spacer()
                
                Button(action: { 
                    onDismiss() 
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            
            Divider()
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search roles...", text: $searchQuery)
                    .textFieldStyle(PlainTextFieldStyle())
                    .focused($isSearchFocused)
                
                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .padding()
            
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // All categories button
                    FilterChip(
                        title: "All",
                        isSelected: selectedCategory == nil,
                        action: { selectedCategory = nil }
                    )
                    
                    ForEach(RoleCategory.allCases, id: \.self) { category in
                        FilterChip(
                            title: category.displayName,
                            isSelected: selectedCategory == category,
                            action: { selectedCategory = category }
                        )
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .contentShape(Rectangle())
            .padding(.bottom, 12)
            
            // Project Team section
            if !projectTeamMembers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Team on this Project")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(projectTeamMembers.enumerated()), id: \.offset) { _, member in
                                ProjectTeamMemberPill(
                                    nodeName: member.nodeName,
                                    teamMember: member.teamMember,
                                    role: member.role,
                                    isSelected: selectedRole?.id == member.teamMember.roleId && 
                                               selectedLevel == member.teamMember.experienceLevel &&
                                               customName == (member.teamMember.name ?? ""),
                                    onTap: {
                                        // Quick-select this team member's configuration
                                        selectedRole = member.role
                                        selectedLevel = member.teamMember.experienceLevel
                                        customName = member.teamMember.name ?? ""
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 40)
                }
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.05))
            }
            
            Divider()
            
            // Role list
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 8) {
                    ForEach(filteredRoles) { role in
                        RoleRow(
                            role: role,
                            isSelected: selectedRole?.id == role.id,
                            action: { 
                                selectedRole = role 
                            }
                        )
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .frame(height: selectedRole == nil ? 350 : 200)
            .contentShape(Rectangle())
            .clipped()
            
            if selectedRole != nil {
                Divider()
                
                // Configuration section
                VStack(alignment: .leading, spacing: 16) {
                    // Custom name field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        TextField("Enter a name (required)", text: $customName)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                    }
                    
                    // Experience level selector
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Experience Level")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            ForEach(ExperienceLevel.allCases, id: \.self) { level in
                                let isAvailable = selectedRole?.isLevelAvailable(level, for: currentTier) ?? false
                                
                                ExperienceLevelButton(
                                    level: level,
                                    isSelected: selectedLevel == level,
                                    isAvailable: isAvailable,
                                    action: {
                                        if isAvailable {
                                            selectedLevel = level
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Action buttons
            HStack {
                if existingMember != nil, let onRemove = onRemove {
                    Button(action: {
                        onRemove()
                        onDismiss()
                    }) {
                        Text("Remove")
                            .foregroundColor(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Spacer()
                
                Button(action: { onDismiss() }) {
                    Text("Cancel")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: saveTeamMember) {
                    Text("Save")
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selectedRole != nil && !customName.trimmingCharacters(in: .whitespaces).isEmpty ? Color.accentColor : Color.gray)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(selectedRole == nil || customName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 600, alignment: .leading)
        .frame(maxHeight: 680)
        .allowsHitTesting(true)
        .onAppear {
            
            // Load existing member if editing
            if let member = existingMember {
                customName = member.name ?? ""
                selectedLevel = member.experienceLevel
                selectedRole = roleManager.role(withId: member.roleId)
            }
            
            // Focus search on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
    }
    
    private func saveTeamMember() {
        guard let role = selectedRole else { return }
        let trimmedName = customName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        
        let member = TeamMember(
            roleId: role.id,
            name: trimmedName,
            experienceLevel: selectedLevel,
            promptAddendum: nil,
            knowledgePackIds: nil
        )
        
        onSave(member)
        onDismiss()
    }
}

// MARK: - Supporting Views

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct RoleRow: View {
    let role: Role
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon with color
                ZStack {
                    Circle()
                        .fill(roleColor.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: role.icon)
                        .font(.system(size: 18))
                        .foregroundColor(roleColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(role.name)
                        .font(.system(size: 14, weight: .medium))
                    
                    Text(role.description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(12)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var roleColor: Color {
        if let nodeColor = NodeColor.color(for: role.color) {
            return nodeColor.color
        }
        return .accentColor
    }
}

struct ExperienceLevelButton: View {
    let level: ExperienceLevel
    let isSelected: Bool
    let isAvailable: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if !isAvailable {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Text(level.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundColor(isSelected ? .white : (isAvailable ? .primary : .secondary))
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isAvailable)
    }
}

struct ProjectTeamMemberPill: View {
    let nodeName: String
    let teamMember: TeamMember
    let role: Role?
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                // Role icon
                Image(systemName: role?.icon ?? "person.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .white : roleColor)
                
                // Team member name and node
                VStack(alignment: .leading, spacing: 1) {
                    Text(teamMember.name ?? "Team Member")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    
                    Text("from \(nodeName)")
                        .font(.system(size: 10))
                        .opacity(0.8)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? roleColor : roleColor.opacity(0.15))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var roleColor: Color {
        guard let role = role,
              let nodeColor = NodeColor.color(for: role.color) else {
            return .accentColor
        }
        return nodeColor.color
    }
}

// MARK: - Team Reassignment Feature
// The "Team on this Project" section shows existing team members as clickable pills.
// Clicking a pill populates the modal with that team member's configuration,
// allowing quick reassignment to the current node.
//
// TODO: RAG Context Feature (Future Enhancement)
// When a team member is added, implement context sharing:
// 1. Collect conversation history from all nodes with team members
// 2. Create context summary using RAG (Retrieval Augmented Generation)
// 3. Include in system prompt so team members have awareness of:
//    - What other team members discussed
//    - Project context and decisions made
//    - Relevant information from previous conversations
//
// Implementation approach:
// - Use vector embeddings to find relevant context when responding
// - Append project context to baseSystemPrompt in TeamMember.assembleSystemPrompt()
// - Add "Project Context" section in assembled prompt
