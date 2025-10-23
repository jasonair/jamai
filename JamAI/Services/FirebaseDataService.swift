//
//  FirebaseDataService.swift
//  JamAI
//
//  Handles Firestore database operations for users, credits, and app config
//

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth
import FirebaseCore

/// Firestore database service
@MainActor
class FirebaseDataService: ObservableObject {
    
    static let shared = FirebaseDataService()
    
    @Published var userAccount: UserAccount?
    @Published var appConfig: AppConfig?
    
    private let db = Firestore.firestore()
    nonisolated(unsafe) private var userListener: ListenerRegistration?
    nonisolated(unsafe) private var configListener: ListenerRegistration?
    
    // Collection references
    private var usersCollection: CollectionReference {
        db.collection("users")
    }
    
    private var creditTransactionsCollection: CollectionReference {
        db.collection("credit_transactions")
    }
    
    private var appConfigDocument: DocumentReference {
        db.collection("config").document("app")
    }
    
    private init() {
        setupAppConfigListener()
    }
    
    deinit {
        cleanup()
    }
    
    /// Cleanup Firestore listeners
    nonisolated func cleanup() {
        userListener?.remove()
        userListener = nil
        configListener?.remove()
        configListener = nil
    }
    
    // MARK: - App Configuration
    
    /// Listen to app configuration changes
    private func setupAppConfigListener() {
        configListener = appConfigDocument.addSnapshotListener { [weak self] snapshot, error in
            guard let snapshot = snapshot, snapshot.exists else { return }
            
            do {
                // Use Firestore decoder directly to handle timestamps properly
                let config = try snapshot.data(as: AppConfig.self)
                Task { @MainActor in
                    self?.appConfig = config
                }
            } catch {
                print("Failed to decode app config: \(error)")
            }
        }
    }
    
    /// Check if app should be blocked (maintenance or force update)
    func shouldBlockApp(currentVersion: String) -> (shouldBlock: Bool, message: String?) {
        guard let config = appConfig else { return (false, nil) }
        
        // Check maintenance mode
        if config.isMaintenanceMode {
            return (true, config.maintenanceMessage ?? "App is under maintenance. Please try again later.")
        }
        
        // Check force update
        if config.forceUpdate && currentVersion < config.minimumVersion {
            return (true, "Please update to the latest version to continue using JamAI.")
        }
        
        return (false, nil)
    }
    
    // MARK: - User Account Management
    
    /// Create new user account in Firestore
    func createUserAccount(userId: String, email: String, displayName: String?) async {
        let account = UserAccount(
            id: userId,
            email: email,
            displayName: displayName
        )
        
        do {
            let data = try Firestore.Encoder().encode(account)
            try await usersCollection.document(userId).setData(data)
            
            // Log initial credit grant
            await logCreditTransaction(
                userId: userId,
                amount: account.credits,
                type: .monthlyGrant,
                description: "Initial trial credits"
            )
            
            self.userAccount = account
            
            // Setup real-time listener for the new account
            setupUserListener(userId: userId)
        } catch {
            print("Failed to create user account: \(error)")
        }
    }
    
    /// Load user account from Firestore
    func loadUserAccount(userId: String) async {
        do {
            let document = try await usersCollection.document(userId).getDocument()
            
            if document.exists {
                do {
                    // Use Firestore decoder directly to handle timestamps
                    let account = try document.data(as: UserAccount.self)
                    self.userAccount = account
                    
                    // Setup real-time listener
                    setupUserListener(userId: userId)
                } catch {
                    // Document exists but is corrupted - delete and recreate
                    print("⚠️ User document corrupted, deleting and recreating for userId: \(userId)")
                    print("Decoding error: \(error)")
                    
                    // Delete corrupted document
                    try? await usersCollection.document(userId).delete()
                    
                    // Create fresh account
                    let email = FirebaseAuthService.shared.currentUser?.email ?? ""
                    let displayName = FirebaseAuthService.shared.currentUser?.displayName
                    
                    await createUserAccount(userId: userId, email: email, displayName: displayName)
                }
            } else {
                // Document doesn't exist - create it
                print("User document not found, creating new account for userId: \(userId)")
                
                // Get email from current user
                let email = FirebaseAuthService.shared.currentUser?.email ?? ""
                let displayName = FirebaseAuthService.shared.currentUser?.displayName
                
                await createUserAccount(userId: userId, email: email, displayName: displayName)
            }
        } catch {
            print("Failed to load user account: \(error)")
            // On error, set userAccount to nil to trigger auth flow
            self.userAccount = nil
        }
    }
    
    /// Listen to user account changes
    private func setupUserListener(userId: String) {
        userListener?.remove()
        
        userListener = usersCollection.document(userId).addSnapshotListener { [weak self] snapshot, error in
            guard let snapshot = snapshot, snapshot.exists else { return }
            
            do {
                // Use Firestore decoder directly to handle timestamps
                let account = try snapshot.data(as: UserAccount.self)
                Task { @MainActor in
                    self?.userAccount = account
                }
            } catch {
                print("Failed to decode user account: \(error)")
            }
        }
    }
    
    /// Update last login timestamp
    func updateLastLogin(userId: String) async {
        do {
            // Use setData with merge to create document if it doesn't exist
            try await usersCollection.document(userId).setData([
                "lastLoginAt": Timestamp(date: Date())
            ], merge: true)
        } catch {
            print("Failed to update last login: \(error)")
            // Non-critical error, don't crash
        }
    }
    
    /// Update user metadata
    func updateUserMetadata(userId: String, metadata: UserMetadata) async {
        do {
            let data = try Firestore.Encoder().encode(metadata)
            try await usersCollection.document(userId).updateData([
                "metadata": data
            ])
        } catch {
            print("Failed to update user metadata: \(error)")
        }
    }
    
    // MARK: - Credit Management
    
    /// Deduct credits for AI generation
    func deductCredits(userId: String, amount: Int, description: String) async -> Bool {
        guard let account = userAccount, account.hasCredits else {
            return false
        }
        
        do {
            let newCredits = max(0, account.credits - amount)
            let newUsed = account.creditsUsedThisMonth + amount
            
            try await usersCollection.document(userId).updateData([
                "credits": newCredits,
                "creditsUsedThisMonth": newUsed
            ])
            
            // Log transaction
            await logCreditTransaction(
                userId: userId,
                amount: -amount,
                type: .aiGeneration,
                description: description
            )
            
            return true
        } catch {
            print("Failed to deduct credits: \(error)")
            return false
        }
    }
    
    /// Grant credits to user
    func grantCredits(userId: String, amount: Int, type: CreditTransaction.TransactionType, description: String) async {
        guard let account = userAccount else { return }
        
        do {
            let newCredits = account.credits + amount
            
            try await usersCollection.document(userId).updateData([
                "credits": newCredits
            ])
            
            // Log transaction
            await logCreditTransaction(
                userId: userId,
                amount: amount,
                type: type,
                description: description
            )
        } catch {
            print("Failed to grant credits: \(error)")
        }
    }
    
    /// Log credit transaction
    private func logCreditTransaction(
        userId: String,
        amount: Int,
        type: CreditTransaction.TransactionType,
        description: String,
        metadata: [String: String]? = nil
    ) async {
        let transaction = CreditTransaction(
            userId: userId,
            amount: amount,
            type: type,
            description: description,
            metadata: metadata
        )
        
        do {
            let data = try Firestore.Encoder().encode(transaction)
            try await creditTransactionsCollection.document(transaction.id).setData(data)
        } catch {
            print("Failed to log credit transaction: \(error)")
        }
    }
    
    /// Get credit transaction history
    func getCreditHistory(userId: String, limit: Int = 50) async -> [CreditTransaction] {
        do {
            let snapshot = try await creditTransactionsCollection
                .whereField("userId", isEqualTo: userId)
                .order(by: "timestamp", descending: true)
                .limit(to: limit)
                .getDocuments()
            
            return snapshot.documents.compactMap { document in
                do {
                    return try document.data(as: CreditTransaction.self)
                } catch {
                    print("Failed to decode transaction \(document.documentID): \(error)")
                    return nil
                }
            }
        } catch {
            print("Failed to get credit history: \(error)")
            return []
        }
    }
    
    // MARK: - Plan Management
    
    /// Update user plan
    func updateUserPlan(userId: String, plan: UserPlan) async {
        do {
            // Calculate new credits based on plan
            let newCredits = plan.monthlyCredits
            let expiresAt: Timestamp? = plan == .trial ? 
                Timestamp(date: Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()) : nil
            
            var updateData: [String: Any] = [
                "plan": plan.rawValue,
                "credits": newCredits,
                "creditsUsedThisMonth": 0
            ]
            
            if let expiresAt = expiresAt {
                updateData["planExpiresAt"] = expiresAt
            }
            
            try await usersCollection.document(userId).updateData(updateData)
            
            // Log credit grant for plan change
            await logCreditTransaction(
                userId: userId,
                amount: newCredits,
                type: .planUpgrade,
                description: "Plan upgraded to \(plan.displayName)"
            )
        } catch {
            print("Failed to update user plan: \(error)")
        }
    }
    
    /// Reset monthly credits (called by scheduled function)
    func resetMonthlyCredits(userId: String) async {
        guard let account = userAccount else { return }
        
        do {
            try await usersCollection.document(userId).updateData([
                "credits": account.plan.monthlyCredits,
                "creditsUsedThisMonth": 0
            ])
            
            await logCreditTransaction(
                userId: userId,
                amount: account.plan.monthlyCredits,
                type: .monthlyGrant,
                description: "Monthly credit refresh"
            )
        } catch {
            print("Failed to reset monthly credits: \(error)")
        }
    }
    
    // MARK: - Admin Functions
    
    /// Update user active status (admin only)
    func setUserActiveStatus(userId: String, isActive: Bool) async {
        do {
            try await usersCollection.document(userId).updateData([
                "isActive": isActive
            ])
        } catch {
            print("Failed to update user status: \(error)")
        }
    }
    
    /// Adjust user credits (admin only)
    func adjustUserCredits(userId: String, amount: Int, reason: String) async {
        guard let account = userAccount else { return }
        
        do {
            let newCredits = max(0, account.credits + amount)
            
            try await usersCollection.document(userId).updateData([
                "credits": newCredits
            ])
            
            await logCreditTransaction(
                userId: userId,
                amount: amount,
                type: .adminAdjustment,
                description: reason
            )
        } catch {
            print("Failed to adjust credits: \(error)")
        }
    }
    
    // MARK: - User Metadata Analytics

    /// Atomically increment a numeric field in the user's metadata.
    /// This is used for tracking summary analytics displayed to the user.
    func incrementUserMetadata(userId: String, field: String, by amount: Int = 1) async {
        guard !userId.isEmpty else {
            print("⚠️ Attempted to increment metadata with empty userId.")
            return
        }
        
        let fieldPath = "metadata.\(field)"
        
        do {
            try await usersCollection.document(userId).updateData([
                fieldPath: FieldValue.increment(Int64(amount))
            ])
        } catch {
            print("❌ Failed to increment metadata field '\(field)' for user \(userId). Error: \(error)")
            // This can happen if the document or metadata field doesn't exist yet.
            // We can add more robust recovery logic here if needed, but for now, we'll just log it.
        }
    }

    // MARK: - Stripe Sync Functions
    
    /// Sync user account with Stripe subscription via HTTPS function
    func syncWithStripe(userId: String, email: String) async throws {
        guard let currentUser = FirebaseAuthService.shared.currentUser else {
            throw NSError(domain: "FirebaseDataService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        let token = try await currentUser.getIDToken()
        guard let url = URL(string: "https://jamai-stripe-gateway-dexvxx91.ew.gateway.dev/sync") else {
            throw NSError(domain: "FirebaseDataService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid API Gateway URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "FirebaseDataService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Sync failed with status \(http.statusCode)"])
        }
        await refreshUserAccount(userId: userId)
    }

    /// Create Stripe customer portal session and return URL
    func createStripePortalSession(returnURL: String? = nil) async throws -> URL {
        guard let currentUser = FirebaseAuthService.shared.currentUser else {
            throw NSError(domain: "FirebaseDataService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        let token = try await currentUser.getIDToken()
        guard let url = URL(string: "https://jamai-stripe-gateway-dexvxx91.ew.gateway.dev/portal") else {
            throw NSError(domain: "FirebaseDataService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid API Gateway URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let body: [String: String] = ["returnUrl": returnURL ?? "http://localhost:3000/account"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "FirebaseDataService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Portal session failed with status \(http.statusCode)"])
        }
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        guard let urlString = json?["url"] as? String, let portalURL = URL(string: urlString) else {
            throw NSError(domain: "FirebaseDataService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Missing portal URL"])
        }
        return portalURL
    }
    
    /// Force refresh user account from Firestore
    /// Useful after webhook events or manual changes
    func refreshUserAccount(userId: String) async {
        print("🔄 Refreshing user account from Firestore...")
        await loadUserAccount(userId: userId)
    }
    
    /// Check if user has an active Stripe subscription
    var hasActiveSubscription: Bool {
        guard let account = userAccount,
              let status = account.subscriptionStatus else {
            return false
        }
        return status.isActive
    }
    
    /// Get user's subscription info for display
    func getSubscriptionInfo() -> (hasSubscription: Bool, status: String, nextBilling: Date?) {
        guard let account = userAccount else {
            return (false, "No account", nil)
        }
        
        if let status = account.subscriptionStatus {
            return (true, status.displayName, account.nextBillingDate)
        }
        
        return (false, "No subscription", nil)
    }
}
