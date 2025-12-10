//
//  UserAccount.swift
//  JamAI
//
//  Firebase user account model with credit tracking and plan management
//

import Foundation
import FirebaseFirestore

/// User subscription plan tiers
enum UserPlan: String, Codable, CaseIterable {
    case free = "free"
    case pro = "pro"
    case teams = "teams"
    case enterprise = "enterprise"
    case lifetime = "lifetime" // Early bird lifetime deal - BYOK only
    
    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .teams: return "Teams"
        case .enterprise: return "Enterprise"
        case .lifetime: return "Lifetime"
        }
    }
    
    var monthlyPrice: String {
        switch self {
        case .free: return "$0"
        case .pro: return "$15"
        case .teams: return "$30"
        case .enterprise: return "Let's talk"
        case .lifetime: return "One-time"
        }
    }
    
    var monthlyCredits: Int {
        switch self {
        case .free: return 100 // ~100K tokens ≈ $0.06 cost
        case .pro: return 1000 // ~1M tokens ≈ $0.60 cost
        case .teams: return 1500 // ~1.5M tokens ≈ $0.90 cost
        case .enterprise: return 5000 // ~5M tokens ≈ $3 cost
        case .lifetime: return 0 // BYOK only - no hosted credits
        }
    }
    
    /// Lifetime deal users must use BYOK - no access to hosted Gemini
    var isLifetimeDeal: Bool {
        return self == .lifetime
    }
    
    /// Whether this plan has access to hosted cloud AI (your Gemini API)
    var hasHostedCloudAccess: Bool {
        return self != .lifetime
    }
    
    // All plans now have unlimited team members and all experience levels
    var hasUnlimitedTeamMembers: Bool {
        return true
    }
    
    
    var features: [String] {
        switch self {
        case .free:
            return [
                "2-week Pro trial",
                "100 prompt credits / month",
                "Local model + Gemini 2.0",
                "Access to all Jam AI team members"
            ]
        case .pro:
            return [
                "Everything in Free, plus:",
                "1,000 prompt credits / month"
            ]
        case .teams:
            return [
                "Everything in Pro, plus:",
                "1,500 prompt credits / user / month"
            ]
        case .enterprise:
            return [
                "Everything in Teams, plus:",
                "5,000 prompt credits / user / month",
                "Dedicated account manager"
            ]
        case .lifetime:
            return [
                "One-time purchase",
                "Bring Your Own Keys (BYOK)",
                "OpenAI, Claude, Gemini support",
                "Local model included",
                "All features unlocked forever"
            ]
        }
    }
}

/// Stripe subscription status
enum SubscriptionStatus: String, Codable {
    case active = "active"
    case pastDue = "past_due"
    case canceled = "canceled"
    case unpaid = "unpaid"
    case trialing = "trialing"
    case incomplete = "incomplete"
    case incompleteExpired = "incomplete_expired"
    case paused = "paused"
    
    var displayName: String {
        switch self {
        case .active: return "Active"
        case .pastDue: return "Past Due"
        case .canceled: return "Canceled"
        case .unpaid: return "Unpaid"
        case .trialing: return "Trial"
        case .incomplete: return "Incomplete"
        case .incompleteExpired: return "Expired"
        case .paused: return "Paused"
        }
    }
    
    var isActive: Bool {
        return self == .active || self == .trialing
    }
}

/// User account data stored in Firebase
struct UserAccount: Codable, Identifiable {
    @DocumentID var id: String? // Firebase UID (injected from document path)
    var email: String
    var displayName: String?
    var photoURL: String?
    var plan: UserPlan
    var credits: Int
    var creditsUsedThisMonth: Int
    var createdAt: Date
    var lastLoginAt: Date
    var planExpiresAt: Date?
    var isActive: Bool
    
    // Stripe integration fields
    var stripeCustomerId: String?
    var stripeSubscriptionId: String?
    var subscriptionStatus: SubscriptionStatus?
    var currentPeriodStart: Date? // When current billing period started
    var nextBillingDate: Date? // When current billing period ends / next billing
    
    /// User metadata for analytics
    var metadata: UserMetadata
    
    /// Computed property for non-optional ID access
    var documentId: String {
        return id ?? ""
    }
    
    // CodingKeys for custom decoding
    enum CodingKeys: String, CodingKey {
        case id, email, displayName, photoURL, plan, credits, creditsUsedThisMonth
        case createdAt, lastLoginAt, planExpiresAt, isActive
        case stripeCustomerId, stripeSubscriptionId, subscriptionStatus
        case currentPeriodStart, nextBillingDate, metadata
    }
    
    init(
        id: String? = nil,
        email: String,
        displayName: String? = nil,
        photoURL: String? = nil,
        plan: UserPlan = .free,
        credits: Int? = nil,
        createdAt: Date = Date(),
        lastLoginAt: Date = Date(),
        stripeCustomerId: String? = nil,
        stripeSubscriptionId: String? = nil,
        subscriptionStatus: SubscriptionStatus? = nil,
        currentPeriodStart: Date? = nil,
        nextBillingDate: Date? = nil
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
        self.plan = plan
        if plan == .free, credits == nil { // New user starting a trial
            self.credits = UserPlan.pro.monthlyCredits
        } else {
            self.credits = credits ?? plan.monthlyCredits
        }
        self.creditsUsedThisMonth = 0
        self.createdAt = createdAt
        self.lastLoginAt = lastLoginAt
        self.planExpiresAt = plan == .free ? Calendar.current.date(byAdding: .day, value: 14, to: createdAt) : nil
        self.isActive = true
        self.stripeCustomerId = stripeCustomerId
        self.stripeSubscriptionId = stripeSubscriptionId
        self.subscriptionStatus = subscriptionStatus
        self.currentPeriodStart = currentPeriodStart
        self.nextBillingDate = nextBillingDate
        self.metadata = UserMetadata()
    }
    
    // Custom decoder to handle Firestore timestamps and missing fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // DocumentID is handled by the property wrapper
        id = try container.decodeIfPresent(String.self, forKey: .id)
        
        // Required fields with defaults
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        photoURL = try container.decodeIfPresent(String.self, forKey: .photoURL)
        plan = try container.decodeIfPresent(UserPlan.self, forKey: .plan) ?? .free
        credits = try container.decodeIfPresent(Int.self, forKey: .credits) ?? plan.monthlyCredits
        creditsUsedThisMonth = try container.decodeIfPresent(Int.self, forKey: .creditsUsedThisMonth) ?? 0
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        
        // Stripe fields
        stripeCustomerId = try container.decodeIfPresent(String.self, forKey: .stripeCustomerId)
        stripeSubscriptionId = try container.decodeIfPresent(String.self, forKey: .stripeSubscriptionId)
        subscriptionStatus = try container.decodeIfPresent(SubscriptionStatus.self, forKey: .subscriptionStatus)
        
        // Date fields - Firestore decoder handles Timestamp -> Date automatically
        // But we need to handle missing fields gracefully
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastLoginAt = try container.decodeIfPresent(Date.self, forKey: .lastLoginAt) ?? Date()
        planExpiresAt = try container.decodeIfPresent(Date.self, forKey: .planExpiresAt)
        currentPeriodStart = try container.decodeIfPresent(Date.self, forKey: .currentPeriodStart)
        nextBillingDate = try container.decodeIfPresent(Date.self, forKey: .nextBillingDate)
        
        // Metadata with default
        metadata = try container.decodeIfPresent(UserMetadata.self, forKey: .metadata) ?? UserMetadata()
    }
    
    var hasCredits: Bool {
        return credits > 0
    }
    
    var isTrialExpired: Bool {
        guard plan == .free, let expiresAt = planExpiresAt else { return false }
        return Date() > expiresAt
    }

    // All plans now have access to all features and team members
    var canAccessAdvancedFeatures: Bool {
        return true
    }

    var allowsSeniorAndExpert: Bool {
        return true
    }
}

/// User metadata for analytics and tracking
struct UserMetadata: Codable {
    var totalNodesCreated: Int
    var totalMessagesGenerated: Int
    var totalEdgesCreated: Int
    var totalNotesCreated: Int
    var totalTeamMembersUsed: Int
    var totalExpandActions: Int
    var totalChildNodesCreated: Int
    var totalProjectsCreated: Int
    var lastAppVersion: String
    var deviceInfo: String
    
    init() {
        self.totalNodesCreated = 0
        self.totalMessagesGenerated = 0
        self.totalEdgesCreated = 0
        self.totalNotesCreated = 0
        self.totalTeamMembersUsed = 0
        self.totalExpandActions = 0
        self.totalChildNodesCreated = 0
        self.totalProjectsCreated = 0
        self.lastAppVersion = ""
        self.deviceInfo = ""
    }
    
    // Custom decoding to handle missing fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.totalNodesCreated = try container.decodeIfPresent(Int.self, forKey: .totalNodesCreated) ?? 0
        self.totalMessagesGenerated = try container.decodeIfPresent(Int.self, forKey: .totalMessagesGenerated) ?? 0
        self.totalEdgesCreated = try container.decodeIfPresent(Int.self, forKey: .totalEdgesCreated) ?? 0
        self.totalNotesCreated = try container.decodeIfPresent(Int.self, forKey: .totalNotesCreated) ?? 0
        self.totalTeamMembersUsed = try container.decodeIfPresent(Int.self, forKey: .totalTeamMembersUsed) ?? 0
        self.totalExpandActions = try container.decodeIfPresent(Int.self, forKey: .totalExpandActions) ?? 0
        self.totalChildNodesCreated = try container.decodeIfPresent(Int.self, forKey: .totalChildNodesCreated) ?? 0
        self.totalProjectsCreated = try container.decodeIfPresent(Int.self, forKey: .totalProjectsCreated) ?? 0
        self.lastAppVersion = try container.decodeIfPresent(String.self, forKey: .lastAppVersion) ?? ""
        self.deviceInfo = try container.decodeIfPresent(String.self, forKey: .deviceInfo) ?? ""
    }
}

/// App configuration stored in Firebase for remote control
struct AppConfig: Codable {
    var isMaintenanceMode: Bool
    var maintenanceMessage: String?
    var minimumVersion: String
    var forceUpdate: Bool
    var updateURL: String?
    var featuresEnabled: [String: Bool]
    var announcementMessage: String?
    var lastUpdated: Date?  // Optional to handle Firestore timestamp serialization
    
    init() {
        self.isMaintenanceMode = false
        self.maintenanceMessage = nil
        self.minimumVersion = "1.0.0"
        self.forceUpdate = false
        self.updateURL = nil
        self.featuresEnabled = [:]
        self.announcementMessage = nil
        self.lastUpdated = Date()
    }
    
    func isFeatureEnabled(_ feature: String) -> Bool {
        return featuresEnabled[feature] ?? true
    }
}

/// Credit transaction for tracking usage
struct CreditTransaction: Codable, Identifiable {
    @DocumentID var id: String? // Injected from document path
    var userId: String
    var amount: Int // Negative for usage, positive for grants
    var type: TransactionType
    var description: String
    var timestamp: Date
    var metadata: [String: String]?
    
    enum TransactionType: String, Codable {
        case aiGeneration = "ai_generation"
        case monthlyGrant = "monthly_grant"
        case planUpgrade = "plan_upgrade"
        case adminAdjustment = "admin_adjustment"
        case refund = "refund"
    }
    
    /// Computed property for non-optional ID access
    var documentId: String {
        return id ?? UUID().uuidString
    }
    
    init(
        id: String? = nil,
        userId: String,
        amount: Int,
        type: TransactionType,
        description: String,
        timestamp: Date = Date(),
        metadata: [String: String]? = nil
    ) {
        self.id = id ?? UUID().uuidString
        self.userId = userId
        self.amount = amount
        self.type = type
        self.description = description
        self.timestamp = timestamp
        self.metadata = metadata
    }
}
