//
//  UserAccount.swift
//  JamAI
//
//  Firebase user account model with credit tracking and plan management
//

import Foundation

/// User subscription plan tiers
enum UserPlan: String, Codable, CaseIterable {
    case trial = "trial"
    case free = "free"
    case premium = "premium"
    case pro = "pro"
    
    var displayName: String {
        switch self {
        case .trial: return "Trial"
        case .free: return "Free"
        case .premium: return "Premium"
        case .pro: return "Pro"
        }
    }
    
    var monthlyCredits: Int {
        switch self {
        case .trial: return 1000
        case .free: return 500
        case .premium: return 5000
        case .pro: return 20000
        }
    }
    
    var maxTeamMembers: Int {
        switch self {
        case .trial: return 3
        case .free: return 2
        case .premium: return 5
        case .pro: return 10
        }
    }
    
    var canAccessAdvancedFeatures: Bool {
        switch self {
        case .trial, .premium, .pro: return true
        case .free: return false
        }
    }
    
    var experienceLevelAccess: String {
        switch self {
        case .trial: return "All experience levels"
        case .free: return "Junior & Intermediate"
        case .premium: return "Senior & Expert"
        case .pro: return "All experience levels"
        }
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
    
    /// User metadata for analytics
    var metadata: UserMetadata
    
    init(
        id: String,
        email: String,
        displayName: String? = nil,
        photoURL: String? = nil,
        plan: UserPlan = .trial,
        credits: Int? = nil,
        createdAt: Date = Date(),
        lastLoginAt: Date = Date()
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
        self.planExpiresAt = plan == .trial ? Calendar.current.date(byAdding: .day, value: 14, to: createdAt) : nil
        self.isActive = true
        self.metadata = UserMetadata()
    }
    
    var hasCredits: Bool {
        return credits > 0
    }
    
    var isTrialExpired: Bool {
        guard plan == .trial, let expiresAt = planExpiresAt else { return false }
        return Date() > expiresAt
    }
}

/// User metadata for analytics and tracking
struct UserMetadata: Codable {
    var totalNodesCreated: Int
    var totalMessagesGenerated: Int
    var totalEdgesCreated: Int
    var lastAppVersion: String
    var deviceInfo: String
    
    init() {
        self.totalNodesCreated = 0
        self.totalMessagesGenerated = 0
        self.totalEdgesCreated = 0
        self.lastAppVersion = ""
        self.deviceInfo = ""
    }
    
    // Custom decoding to handle missing fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.totalNodesCreated = try container.decodeIfPresent(Int.self, forKey: .totalNodesCreated) ?? 0
        self.totalMessagesGenerated = try container.decodeIfPresent(Int.self, forKey: .totalMessagesGenerated) ?? 0
        self.totalEdgesCreated = try container.decodeIfPresent(Int.self, forKey: .totalEdgesCreated) ?? 0
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
