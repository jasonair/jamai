//
//  UserSettingsView.swift
//  JamAI
//
//  User account settings, plan management, and credit tracking
//

import SwiftUI
import FirebaseAuth

struct UserSettingsView: View {
    
    @StateObject private var authService = FirebaseAuthService.shared
    @StateObject private var dataService = FirebaseDataService.shared
    
    @State private var showingSignOutAlert = false
    @State private var creditHistory: [CreditTransaction] = []
    @State private var isLoadingHistory = false
    
    let onDismiss: (() -> Void)?
    
    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // User profile section
                if let user = authService.currentUser,
                   let account = dataService.userAccount {
                    // Content (existing code below)
                    
                    // Profile header
                    HStack(spacing: 16) {
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.2))
                                .frame(width: 80, height: 80)
                            
                            if let photoURL = account.photoURL, let url = URL(string: photoURL) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.accentColor)
                                }
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.displayName ?? "User")
                                .font(.system(size: 24, weight: .bold))
                            
                            Text(account.email)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            
                            // Plan badge
                            HStack(spacing: 6) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10))
                                Text(account.plan.displayName)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(planColor(for: account.plan))
                            .cornerRadius(12)
                            .padding(.top, 4)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(16)
                    
                    // Credits section with progress bar
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Credits")
                            .font(.system(size: 18, weight: .semibold))
                        
                        VStack(alignment: .leading, spacing: 8) {
                            // Usage summary
                            HStack {
                                Text("\(account.credits) / \(account.plan.monthlyCredits)")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("available")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(account.creditsUsedThisMonth) used")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            
                            // Progress bar
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background (total capacity)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.15))
                                        .frame(height: 8)
                                    
                                    // Used portion
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(progressBarColor(for: account))
                                        .frame(
                                            width: geometry.size.width * CGFloat(account.creditsUsedThisMonth) / CGFloat(account.plan.monthlyCredits),
                                            height: 8
                                        )
                                }
                            }
                            .frame(height: 8)
                            
                            // Additional info with renewal date
                            HStack {
                                Text("Usage since \(formattedMonthStart())")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text(renewalDateText(for: account))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(12)
                        
                        if !account.hasCredits {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("You've run out of credits. Upgrade your plan to continue.")
                                    .font(.system(size: 13))
                            }
                            .padding(12)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        if account.isTrialExpired {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.fill")
                                    .foregroundColor(.red)
                                Text("Your trial has expired. Upgrade to continue using JamAI.")
                                    .font(.system(size: 13))
                            }
                            .padding(12)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    
                    // Plan comparison
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Plans")
                            .font(.system(size: 18, weight: .semibold))
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(UserPlan.allCases, id: \.self) { plan in
                                PlanCard(
                                    plan: plan,
                                    isCurrentPlan: plan == account.plan,
                                    onSelect: {
                                        upgradePlan(to: plan)
                                    }
                                )
                            }
                        }
                    }
                    
                    // Account Activity
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Account Activity")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Your JamAI usage this month")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        
                        // Grid of stat cards
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            StatCard(
                                label: "Nodes Created",
                                value: "\(account.metadata.totalNodesCreated)",
                                icon: "square.on.square"
                            )
                            
                            StatCard(
                                label: "AI Messages",
                                value: "\(account.metadata.totalMessagesGenerated)",
                                icon: "wand.and.stars"
                            )
                            
                            StatCard(
                                label: "Notes Created",
                                value: "\(account.metadata.totalNotesCreated)",
                                icon: "note.text"
                            )
                            
                            StatCard(
                                label: "Child Nodes",
                                value: "\(account.metadata.totalChildNodesCreated)",
                                icon: "arrow.triangle.branch"
                            )
                            
                            StatCard(
                                label: "Expand Actions",
                                value: "\(account.metadata.totalExpandActions)",
                                icon: "arrow.up.right.square"
                            )
                            
                            StatCard(
                                label: "AI Team Members",
                                value: "\(account.metadata.totalTeamMembersUsed)",
                                icon: "person.2.fill"
                            )
                        }
                    }
                    
                    // Sign out button
                    Button {
                        showingSignOutAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out")
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                } else if authService.currentUser != nil {
                    // Loading state - user is authenticated but account data hasn't loaded
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading account...")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                        
                        Button("Retry") {
                            if let userId = authService.currentUser?.uid {
                                Task {
                                    await dataService.loadUserAccount(userId: userId)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Not authenticated (shouldn't happen but handle it)
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Not signed in")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Please sign in to view your account")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(24)
        }
        .frame(width: 600, height: 700)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture().onChanged { _ in }
        )
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                signOut()
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .onAppear {
            if let userId = authService.currentUser?.uid {
                // Load user account if not already loaded
                if dataService.userAccount == nil {
                    Task {
                        await dataService.loadUserAccount(userId: userId)
                    }
                }
                loadCreditHistory(userId: userId)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func planColor(for plan: UserPlan) -> Color {
        switch plan {
        case .trial: return .orange
        case .free: return .gray
        case .pro: return .blue
        case .teams: return .purple
        case .enterprise: return .green
        }
    }
    
    private func progressBarColor(for account: UserAccount) -> Color {
        let usagePercentage = Double(account.creditsUsedThisMonth) / Double(account.plan.monthlyCredits)
        
        if usagePercentage >= 0.9 {
            return .red
        } else if usagePercentage >= 0.7 {
            return .orange
        } else {
            return .green
        }
    }
    
    private func formattedMonthStart() -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        
        if let monthStart = calendar.date(from: components) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: monthStart)
        }
        
        return "this month"
    }
    
    private func renewalDateText(for account: UserAccount) -> String {
        let calendar = Calendar.current
        
        if account.plan == .trial, let expiresAt = account.planExpiresAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            let daysRemaining = calendar.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0
            return "Trial ends in \(max(0, daysRemaining)) days (\(formatter.string(from: expiresAt)))"
        } else {
            // Calculate next month start
            let now = Date()
            var components = calendar.dateComponents([.year, .month], from: now)
            components.month! += 1
            
            if let nextMonth = calendar.date(from: components) {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                let daysRemaining = calendar.dateComponents([.day], from: Date(), to: nextMonth).day ?? 0
                return "Credits renew in \(daysRemaining) days (\(formatter.string(from: nextMonth)))"
            }
            
            return "Renews next month"
        }
    }
    
    private func upgradePlan(to plan: UserPlan) {
        guard let userId = authService.currentUser?.uid else { return }
        
        Task {
            await dataService.updateUserPlan(userId: userId, plan: plan)
        }
    }
    
    private func loadCreditHistory(userId: String) {
        isLoadingHistory = true
        
        Task {
            do {
                let history = await dataService.getCreditHistory(userId: userId)
                await MainActor.run {
                    creditHistory = history
                    isLoadingHistory = false
                }
            } catch {
                print("Error loading credit history: \(error)")
                await MainActor.run {
                    creditHistory = []
                    isLoadingHistory = false
                }
            }
        }
    }
    
    private func signOut() {
        do {
            try authService.signOut()
            // Close the modal after signing out
            onDismiss?()
        } catch {
            print("Sign out failed: \(error)")
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Plan Card

struct PlanCard: View {
    let plan: UserPlan
    let isCurrentPlan: Bool
    let onSelect: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.displayName)
                        .font(.system(size: 16, weight: .bold))
                    
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(plan.monthlyPrice)
                            .font(.system(size: 24, weight: .bold))
                        if plan.monthlyPrice != "Custom" && plan.monthlyPrice != "$0" {
                            Text("/ month")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        } else if plan.monthlyPrice == "$0" {
                            Text("per user/month")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                if isCurrentPlan {
                    Text("Current")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(8)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                Text("\(plan.monthlyCredits) prompt credits/month")
                    .font(.system(size: 12, weight: .medium))
                
                Text("• \(plan.hasUnlimitedTeamMembers ? "Unlimited" : "\(plan.maxTeamMembersPerJam)") AI team members\(plan.hasUnlimitedTeamMembers ? "" : " per Jam")")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Text("• \(plan.experienceLevelAccess)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                if plan.maxSavedJams != -1 {
                    Text("• Up to \(plan.maxSavedJams) saved Jams")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            if !isCurrentPlan {
                Button {
                    onSelect()
                } label: {
                    Text("Select")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(minHeight: 140)
        .background(isCurrentPlan ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrentPlan ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Credit Transaction Row

struct CreditTransactionRow: View {
    let transaction: CreditTransaction
    
    var body: some View {
        HStack {
            // Icon
            Image(systemName: iconForType(transaction.type))
                .font(.system(size: 14))
                .foregroundColor(transaction.amount >= 0 ? .green : .red)
                .frame(width: 24)
            
            // Description
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description)
                    .font(.system(size: 13, weight: .medium))
                
                Text(formatTimestamp(transaction.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Amount
            Text("\(transaction.amount >= 0 ? "+" : "")\(transaction.amount)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(transaction.amount >= 0 ? .green : .red)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func iconForType(_ type: CreditTransaction.TransactionType) -> String {
        switch type {
        case .aiGeneration: return "wand.and.stars"
        case .monthlyGrant: return "calendar.badge.plus"
        case .planUpgrade: return "arrow.up.circle"
        case .adminAdjustment: return "wrench"
        case .refund: return "arrow.counterclockwise"
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short  // Shows hours and minutes only, no seconds
        return formatter.string(from: date)
    }
}

#Preview {
    UserSettingsView()
}
