//
//  AnalyticsService.swift
//  JamAI
//
//  Handles analytics tracking and aggregation for admin dashboard
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Service for tracking and querying analytics data
@MainActor
class AnalyticsService {
    
    static let shared = AnalyticsService()
    
    private let db = Firestore.firestore()
    
    // Collection references
    private var tokenUsageCollection: CollectionReference {
        db.collection("analytics_token_usage")
    }
    
    private var teamMemberUsageCollection: CollectionReference {
        db.collection("analytics_team_member_usage")
    }
    
    private var projectActivityCollection: CollectionReference {
        db.collection("analytics_project_activity")
    }
    
    private var nodeCreationCollection: CollectionReference {
        db.collection("analytics_node_creation")
    }
    
    private var dailyAnalyticsCollection: CollectionReference {
        db.collection("analytics_daily")
    }
    
    private var planAnalyticsCollection: CollectionReference {
        db.collection("analytics_plans")
    }
    
    private init() {}
    
    // MARK: - Token Usage Tracking
    
    /// Track AI token usage with cost calculation
    func trackTokenUsage(
        userId: String,
        projectId: UUID,
        nodeId: UUID,
        teamMemberRoleId: String?,
        teamMemberExperienceLevel: String?,
        inputTokens: Int,
        outputTokens: Int,
        modelUsed: String,
        generationType: TokenUsageEvent.GenerationType
    ) async {
        let event = TokenUsageEvent(
            userId: userId,
            projectId: projectId,
            nodeId: nodeId,
            teamMemberRoleId: teamMemberRoleId,
            teamMemberExperienceLevel: teamMemberExperienceLevel,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            modelUsed: modelUsed,
            generationType: generationType
        )
        
        await logEvent(event, to: tokenUsageCollection)
        await updateDailyAnalytics(userId: userId, tokenEvent: event)

        // Also increment the user-facing metadata stat
        switch generationType {
        case .chat:
            await FirebaseDataService.shared.incrementUserMetadata(userId: userId, field: "totalMessagesGenerated")
        case .expand:
            await FirebaseDataService.shared.incrementUserMetadata(userId: userId, field: "totalExpandActions")
        default:
            break // Other types don't have a user-facing counter yet
        }
    }
    
    // MARK: - Team Member Usage Tracking
    
    /// Track team member attachment and usage
    func trackTeamMemberUsage(
        userId: String,
        projectId: UUID,
        nodeId: UUID,
        roleId: String,
        roleName: String,
        roleCategory: String,
        experienceLevel: String,
        actionType: TeamMemberUsageEvent.ActionType
    ) async {
        let event = TeamMemberUsageEvent(
            userId: userId,
            projectId: projectId,
            nodeId: nodeId,
            roleId: roleId,
            roleName: roleName,
            roleCategory: roleCategory,
            experienceLevel: experienceLevel,
            actionType: actionType
        )
        
        await logEvent(event, to: teamMemberUsageCollection)
        
        // Also increment the user-facing metadata stat when a member is added
        if actionType == .attached {
            await FirebaseDataService.shared.incrementUserMetadata(userId: userId, field: "totalTeamMembersUsed")
        }

        // Update daily analytics if team member was used in generation
        if actionType == .used {
            await updateDailyAnalytics(userId: userId, teamMemberRoleId: roleId)
        }
    }
    
    // MARK: - Project Activity Tracking
    
    /// Track project creation and activity
    func trackProjectActivity(
        userId: String,
        projectId: UUID,
        projectName: String,
        activityType: ProjectActivityEvent.ActivityType,
        metadata: [String: String]? = nil
    ) async {
        let event = ProjectActivityEvent(
            userId: userId,
            projectId: projectId,
            projectName: projectName,
            activityType: activityType,
            metadata: metadata
        )
        
        await logEvent(event, to: projectActivityCollection)
        await updateDailyAnalytics(userId: userId, projectActivity: event)
    }
    
    // MARK: - Node Creation Tracking
    
    /// Track node, note, and edge creation
    func trackNodeCreation(
        userId: String,
        projectId: UUID,
        nodeId: UUID,
        nodeType: String,
        creationMethod: NodeCreationEvent.CreationMethod,
        parentNodeId: UUID? = nil,
        teamMemberRoleId: String? = nil
    ) async {
        let event = NodeCreationEvent(
            userId: userId,
            projectId: projectId,
            nodeId: nodeId,
            nodeType: nodeType,
            creationMethod: creationMethod,
            parentNodeId: parentNodeId,
            teamMemberRoleId: teamMemberRoleId
        )
        
        await logEvent(event, to: nodeCreationCollection)
        await updateDailyAnalytics(userId: userId, nodeCreation: event)

        // Also increment the user-facing metadata stat
        switch creationMethod {
        case .manual:
            await FirebaseDataService.shared.incrementUserMetadata(userId: userId, field: "totalNodesCreated")
        case .note:
            await FirebaseDataService.shared.incrementUserMetadata(userId: userId, field: "totalNotesCreated")
        case .childNode, .expand:
            await FirebaseDataService.shared.incrementUserMetadata(userId: userId, field: "totalChildNodesCreated")
        }

    }
    
    // MARK: - Daily Analytics Aggregation
    
    /// Update daily aggregated analytics (incremental)
    private func updateDailyAnalytics(
        userId: String,
        tokenEvent: TokenUsageEvent? = nil,
        teamMemberRoleId: String? = nil,
        projectActivity: ProjectActivityEvent? = nil,
        nodeCreation: NodeCreationEvent? = nil
    ) async {
        let today = Calendar.current.startOfDay(for: Date())
        let dateString = ISO8601DateFormatter().string(from: today).prefix(10)
        let docId = "\(userId)_\(dateString)"
        
        do {
            let docRef = dailyAnalyticsCollection.document(docId)
            let doc = try await docRef.getDocument()
            
            var analytics: DailyAnalytics
            if doc.exists {
                analytics = try doc.data(as: DailyAnalytics.self)
            } else {
                analytics = DailyAnalytics(userId: userId, date: today)
            }
            
            // Update based on event type
            if let event = tokenEvent {
                analytics.totalTokensInput += event.inputTokens
                analytics.totalTokensOutput += event.outputTokens
                analytics.totalTokens += event.totalTokens
                analytics.totalCostUSD += event.estimatedCostUSD
                analytics.totalGenerations += 1
                
                let typeKey = event.generationType.rawValue
                analytics.generationsByType[typeKey, default: 0] += 1
                
                if let roleId = event.teamMemberRoleId {
                    analytics.uniqueTeamMembersUsed.insert(roleId)
                    analytics.teamMemberUsageCount[roleId, default: 0] += 1
                }
            }
            
            if let roleId = teamMemberRoleId {
                analytics.uniqueTeamMembersUsed.insert(roleId)
                analytics.teamMemberUsageCount[roleId, default: 0] += 1
            }
            
            if let activity = projectActivity {
                switch activity.activityType {
                case .created:
                    analytics.totalProjectsCreated += 1
                case .opened:
                    analytics.totalProjectsOpened += 1
                default:
                    break
                }
            }
            
            if let creation = nodeCreation {
                switch creation.nodeType {
                case "standard":
                    analytics.totalNodesCreated += 1
                case "note":
                    analytics.totalNotesCreated += 1
                case "edge":
                    analytics.totalEdgesCreated += 1
                default:
                    break
                }
            }
            
            analytics.lastUpdated = Date()
            
            let data = try Firestore.Encoder().encode(analytics)
            try await docRef.setData(data, merge: false)
            
        } catch {
            print("❌ Failed to update daily analytics: \(error)")
        }
    }
    
    // MARK: - Plan Analytics Aggregation
    
    /// Generate plan analytics snapshot (call this daily via Cloud Function)
    func generatePlanAnalytics() async {
        let today = Calendar.current.startOfDay(for: Date())
        let dateString = ISO8601DateFormatter().string(from: today).prefix(10)
        
        do {
            let usersSnapshot = try await db.collection("users").getDocuments()
            
            var analytics = PlanAnalytics(date: today)
            
            for doc in usersSnapshot.documents {
                guard let account = try? doc.data(as: UserAccount.self) else { continue }
                
                analytics.totalUsers += 1
                analytics.planCounts[account.plan.rawValue, default: 0] += 1
                analytics.totalCreditsUsed += account.creditsUsedThisMonth
                
                switch account.plan {
                case .free:
                    analytics.totalFreeUsers += 1
                case .pro:
                    analytics.totalPaidUsers += 1
                    analytics.estimatedRevenue += 15.00 // Pro monthly price
                case .teams:
                    analytics.totalPaidUsers += 1
                    analytics.estimatedRevenue += 30.00 // Teams monthly price
                case .enterprise:
                    analytics.totalPaidUsers += 1
                    analytics.estimatedRevenue += 99.00 // Enterprise estimated monthly price (custom pricing)
                }
            }
            
            let data = try Firestore.Encoder().encode(analytics)
            try await planAnalyticsCollection.document(String(dateString)).setData(data)
            
            print("✅ Generated plan analytics for \(dateString)")
        } catch {
            print("❌ Failed to generate plan analytics: \(error)")
        }
    }
    
    // MARK: - Query Methods for Admin Dashboard
    
    /// Get token usage for a specific user in a date range
    func getTokenUsage(
        userId: String,
        startDate: Date,
        endDate: Date
    ) async throws -> [TokenUsageEvent] {
        let snapshot = try await tokenUsageCollection
            .whereField("userId", isEqualTo: userId)
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: startDate))
            .whereField("timestamp", isLessThanOrEqualTo: Timestamp(date: endDate))
            .order(by: "timestamp", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { try? $0.data(as: TokenUsageEvent.self) }
    }
    
    /// Get aggregated token usage across all users
    func getAggregatedTokenUsage(
        startDate: Date,
        endDate: Date
    ) async throws -> (totalInputTokens: Int, totalOutputTokens: Int, totalCost: Double) {
        let snapshot = try await tokenUsageCollection
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: startDate))
            .whereField("timestamp", isLessThanOrEqualTo: Timestamp(date: endDate))
            .getDocuments()
        
        var totalInput = 0
        var totalOutput = 0
        var totalCost = 0.0
        
        for doc in snapshot.documents {
            if let event = try? doc.data(as: TokenUsageEvent.self) {
                totalInput += event.inputTokens
                totalOutput += event.outputTokens
                totalCost += event.estimatedCostUSD
            }
        }
        
        return (totalInput, totalOutput, totalCost)
    }
    
    /// Get most used team members across all users
    func getMostUsedTeamMembers(limit: Int = 10) async throws -> [(roleId: String, roleName: String, count: Int)] {
        let snapshot = try await teamMemberUsageCollection
            .whereField("actionType", isEqualTo: "used")
            .getDocuments()
        
        var roleCounts: [String: (name: String, count: Int)] = [:]
        
        for doc in snapshot.documents {
            if let event = try? doc.data(as: TeamMemberUsageEvent.self) {
                let current = roleCounts[event.roleId] ?? (event.roleName, 0)
                roleCounts[event.roleId] = (current.name, current.count + 1)
            }
        }
        
        return roleCounts.map { (roleId: $0.key, roleName: $0.value.name, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Get daily analytics for a user
    func getDailyAnalytics(
        userId: String,
        startDate: Date,
        endDate: Date
    ) async throws -> [DailyAnalytics] {
        let dateFormatter = ISO8601DateFormatter()
        let startDateString = String(dateFormatter.string(from: startDate).prefix(10))
        let endDateString = String(dateFormatter.string(from: endDate).prefix(10))
        
        let snapshot = try await dailyAnalyticsCollection
            .whereField("userId", isEqualTo: userId)
            .whereField("id", isGreaterThanOrEqualTo: "\(userId)_\(startDateString)")
            .whereField("id", isLessThanOrEqualTo: "\(userId)_\(endDateString)")
            .order(by: "id", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { try? $0.data(as: DailyAnalytics.self) }
    }
    
    /// Get plan analytics for date range
    func getPlanAnalytics(
        startDate: Date,
        endDate: Date
    ) async throws -> [PlanAnalytics] {
        let dateFormatter = ISO8601DateFormatter()
        let startDateString = String(dateFormatter.string(from: startDate).prefix(10))
        let endDateString = String(dateFormatter.string(from: endDate).prefix(10))
        
        let snapshot = try await planAnalyticsCollection
            .whereField("id", isGreaterThanOrEqualTo: startDateString)
            .whereField("id", isLessThanOrEqualTo: endDateString)
            .order(by: "id", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { try? $0.data(as: PlanAnalytics.self) }
    }
    
    /// Get user count by plan
    func getUserCountByPlan() async throws -> [String: Int] {
        let usersSnapshot = try await db.collection("users").getDocuments()
        var counts: [String: Int] = [:]
        
        for doc in usersSnapshot.documents {
            if let account = try? doc.data(as: UserAccount.self) {
                counts[account.plan.displayName, default: 0] += 1
            }
        }
        
        return counts
    }
    
    /// Get total credits used across all users
    func getTotalCreditsUsed() async throws -> Int {
        let usersSnapshot = try await db.collection("users").getDocuments()
        var total = 0
        
        for doc in usersSnapshot.documents {
            if let account = try? doc.data(as: UserAccount.self) {
                total += account.creditsUsedThisMonth
            }
        }
        
        return total
    }
    
    // MARK: - Helper Methods
    
    /// Generic method to log an event to Firestore
    private func logEvent<T: Codable & Identifiable>(_ event: T, to collection: CollectionReference) async where T.ID == String {
        do {
            let data = try Firestore.Encoder().encode(event)
            try await collection.document(event.id).setData(data)
        } catch {
            print("❌ Failed to log analytics event: \(error)")
        }
    }
}
