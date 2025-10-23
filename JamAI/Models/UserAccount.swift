//
//  UserAccount.swift
//  JamAI
//
//  Firebase user account model with credit tracking and plan management
//

import Foundation

/// User subscription plan tiers
enum UserPlan: String, Codable, CaseIterable {
    case free = "free"
    case pro = "pro"
    case teams = "teams"
    case enterprise = "enterprise"
    
    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .teams: return "Teams"
        case .enterprise: return "Enterprise"
        }
    }
    
    var monthlyPrice: String {
        switch self {
        case .free: return "$0"
        case .pro: return "$15"
        case .teams: return "$30"
        case .enterprise: return "Custom"
        }
    }
    
    var monthlyCredits: Int {
        switch self {
        case .free: return 100 // ~100K tokens ≈ $0.06 cost
        case .pro: return 1000 // ~1M tokens ≈ $0.60 cost
        case .teams: return 1500 // ~1.5M tokens ≈ $0.90 cost
        case .enterprise: return 5000 // ~5M tokens ≈ $3 cost
        }
    }
    
    var maxTeamMembersPerJam: Int {
        switch self {
        case .free: return 3
        case .pro: return 12
        case .teams: return -1 // Unlimited
        case .enterprise: return -1 // Unlimited
        }
    }
    
    var maxSavedJams: Int {
        switch self {
        case .free: return 3
        case .pro: return -1 // Unlimited
        case .teams: return -1 // Unlimited
        case .enterprise: return -1 // Unlimited
        }
    }
    
    var hasUnlimitedTeamMembers: Bool {
        return maxTeamMembersPerJam == -1
    }
    
    
    var experienceLevelAccess: String {
        switch self {
        case .free: return "Junior & Intermediate"
        case .pro: return "All experience levels"
        case .teams: return "All experience levels"
        case .enterprise: return "All experience levels"
        }
    }
    
    
    var features: [String] {
        switch self {
        case .free:
            return [
                "100 prompt credits/month (~100K tokens)",
                "3 AI Team Members (Junior & Intermediate)",
                "Local model + Gemini 2.0 Flash-Lite",
                "Basic web search (Serper/Tavily)",
                "Up to 3 saved Jams",
                "Community support"
            ]
        case .pro:
            return [
                "Everything in Free, plus:",
                "1,000 prompt credits/month (~1M tokens)",
                "Gemini 2.5 Flash-Lite + Claude Instant",
                "12 AI Team Members per Jam (All levels)",
                "Advanced web search (Perplexity-style)",
                "Image generation (low res)",
                "Priority support"
            ]
        case .teams:
            return [
                "Everything in Pro, plus:",
                "1,500 prompt credits per user/month (~1.5M tokens)",
                "Shared credit pool & add-on purchasing",
                "Unlimited AI Team Members",
                "Create Teams from multiple AI Team Members"
            ]
        case .enterprise:
            return [
                "Everything in Teams, plus:",
                "5,000 prompt credits per user/month (~5M tokens)",
                "Private Gemini Vertex",
                "Dedicated account manager",
                "Custom integrations",
                "Priority support"
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
    let id: String // Firebase UID
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
    var nextBillingDate: Date?
    
    /// User metadata for analytics
    var metadata: UserMetadata
    
    init(
        id: String,
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
        nextBillingDate: Date? = nil
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
        self.plan = plan
        self.credits = credits ?? plan.monthlyCredits
        self.creditsUsedThisMonth = 0
        self.createdAt = createdAt
        self.lastLoginAt = lastLoginAt
        self.planExpiresAt = plan == .free ? Calendar.current.date(byAdding: .day, value: 14, to: createdAt) : nil
        self.isActive = true
        self.stripeCustomerId = stripeCustomerId
        self.stripeSubscriptionId = stripeSubscriptionId
        self.subscriptionStatus = subscriptionStatus
        self.nextBillingDate = nextBillingDate
        self.metadata = UserMetadata()
    }
    
    var hasCredits: Bool {
        return credits > 0
    }
    
    var isTrialExpired: Bool {
        guard plan == .free, let expiresAt = planExpiresAt else { return false }
        return Date() > expiresAt
    }

    var canAccessAdvancedFeatures: Bool {
        switch self.plan {
        case .pro, .teams, .enterprise: return true
        case .free:
            return !isTrialExpired
        }
    }

    var allowsSeniorAndExpert: Bool {
        switch self.plan {
        case .pro, .teams, .enterprise: return true
        case .free:
            return !isTrialExpired
        }
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
    var featuresEnabled: [String: Bool]
    var announcementMessage: String?
    var lastUpdated: Date?  // Optional to handle Firestore timestamp serialization
    
    init() {
        self.isMaintenanceMode = false
        self.maintenanceMessage = nil
        self.minimumVersion = "1.0.0"
        self.forceUpdate = false
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
    var id: String
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
    
    init(
        id: String = UUID().uuidString,
        userId: String,
        amount: Int,
        type: TransactionType,
        description: String,
        timestamp: Date = Date(),
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.userId = userId
        self.amount = amount
        self.type = type
        self.description = description
        self.timestamp = timestamp
        self.metadata = metadata
    }
}
