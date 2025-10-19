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
                    
                    // Credits section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Credits")
                            .font(.system(size: 18, weight: .semibold))
                        
                        HStack(spacing: 16) {
                            // Available credits
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Available")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("\(account.credits)")
                                        .font(.system(size: 32, weight: .bold))
                                        .foregroundColor(account.hasCredits ? .primary : .red)
                                    
                                    Text("credits")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(12)
                            
                            // Used this month
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Used This Month")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("\(account.creditsUsedThisMonth)")
                                        .font(.system(size: 32, weight: .bold))
                                    
                                    Text("credits")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(12)
                        }
                        
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
                    
                    // Credit history
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Credit History")
                                .font(.system(size: 18, weight: .semibold))
                            
                            Spacer()
                            
                            Button {
                                loadCreditHistory(userId: user.uid)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if isLoadingHistory {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else if creditHistory.isEmpty {
                            Text("No transactions yet")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            VStack(spacing: 8) {
                                ForEach(creditHistory) { transaction in
                                    CreditTransactionRow(transaction: transaction)
                                }
                            }
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
        case .premium: return .purple
        case .pro: return .blue
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
            let history = await dataService.getCreditHistory(userId: userId)
            await MainActor.run {
                creditHistory = history
                isLoadingHistory = false
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

// MARK: - Plan Card

struct PlanCard: View {
    let plan: UserPlan
    let isCurrentPlan: Bool
    let onSelect: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(plan.displayName)
                    .font(.system(size: 16, weight: .bold))
                
                Spacer()
                
                if isCurrentPlan {
                    Text("Your Current Plan")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(8)
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("\(plan.monthlyCredits)")
                        .font(.system(size: 20, weight: .bold))
                    Text("credits/month")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Text("• \(plan.maxTeamMembers) AI team members")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Text("• \(plan.experienceLevelAccess)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
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
                
                Text(transaction.timestamp, style: .relative)
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
}

#Preview {
    UserSettingsView()
}
