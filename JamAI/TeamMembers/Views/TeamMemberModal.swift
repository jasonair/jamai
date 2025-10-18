//
//  TeamMemberModal.swift
//  JamAI
//
//  Modal for selecting and configuring a team member
//

import SwiftUI

struct TeamMemberModal: View {
    @StateObject private var roleManager = RoleManager.shared
    
    let existingMember: TeamMember?
    let onSave: (TeamMember) -> Void
    let onRemove: (() -> Void)?
    let onDismiss: () -> Void
    
    @State private var searchQuery = ""
    @State private var selectedCategory: RoleCategory?
    @State private var selectedRole: Role?
    @State private var selectedLevel: ExperienceLevel = .intermediate
    @State private var customName: String = ""
    @State private var currentTier: PlanTier = .free // TODO: Get from user settings
    
    @FocusState private var isSearchFocused: Bool
    
    var filteredRoles: [Role] {
        var results = roleManager.roles
        
        // Apply search
        if !searchQuery.isEmpty {
            results = roleManager.searchRoles(query: searchQuery)
        }
        
        // Apply category filter
        if let category = selectedCategory {
            results = results.filter { $0.category == category }
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
                    print("[TeamMemberModal] Close button tapped")
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
            .frame(height: 40) // Fixed height for the filter bar
            .padding(.bottom, 12)
            .onAppear {
                print("[TeamMemberModal] Category filter ScrollView appeared")
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
                                print("[TeamMemberModal] Role selected: \(role.name)")
                                selectedRole = role 
                            }
                        )
                    }
                }
                .padding()
            }
            .frame(height: selectedRole == nil ? 350 : 200) // Smaller when config section is visible
            .clipped() // Clip content to bounds
            .onAppear {
                print("[TeamMemberModal] Role list ScrollView appeared")
            }
            
            if selectedRole != nil {
                Divider()
                
                // Configuration section
                VStack(alignment: .leading, spacing: 16) {
                    // Custom name field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name (Optional)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        TextField("e.g., Sarah", text: $customName)
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
                    
                    // Plan tier notice for locked levels
                    if let role = selectedRole,
                       !role.isLevelAvailable(selectedLevel, for: currentTier) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12))
                            Text("This experience level requires a higher plan tier")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.orange)
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
                        .background(selectedRole != nil ? Color.accentColor : Color.gray)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(selectedRole == nil)
            }
            .padding()
        }
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true) // Size to fit content vertically
        .frame(maxHeight: 650) // Cap at reasonable max
        .allowsHitTesting(true) // Ensure modal captures all events
        .onAppear {
            print("[TeamMemberModal] Modal appeared")
            
            // Load existing member if editing
            if let member = existingMember {
                customName = member.name ?? ""
                selectedLevel = member.experienceLevel
                selectedRole = roleManager.role(withId: member.roleId)
                print("[TeamMemberModal] Loaded existing member: \(member.roleId)")
            }
            
            // Focus search on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
        .onDisappear {
            print("[TeamMemberModal] Modal disappeared")
        }
    }
    
    private func saveTeamMember() {
        guard let role = selectedRole else { return }
        
        let member = TeamMember(
            roleId: role.id,
            name: customName.isEmpty ? nil : customName,
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
