# Firebase Integration Examples

Practical code examples for extending the Firebase implementation in JamAI.

---

## Credit System Integration

### Show Credits in UI

**Add to any SwiftUI view:**
```swift
import SwiftUI

struct MyView: View {
    @StateObject private var dataService = FirebaseDataService.shared
    
    var body: some View {
        VStack {
            if let account = dataService.userAccount {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("\(account.credits) credits")
                        .font(.caption)
                }
                .padding(6)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
}
```

### Add Credit Warning Badge

**Show low credit warning:**
```swift
@ViewBuilder
var creditBadge: some View {
    if let account = dataService.userAccount {
        if account.credits == 0 {
            Label("Out of credits", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.red)
        } else if account.credits < 50 {
            Label("\(account.credits) credits left", systemImage: "info.circle")
                .font(.caption)
                .foregroundColor(.orange)
        }
    }
}
```

### Check Credits Before Action

**Guard against insufficient credits:**
```swift
func performExpensiveOperation() {
    // Check credits first
    guard CreditTracker.shared.canGenerateResponse() else {
        showAlert("Insufficient Credits", 
                  message: CreditTracker.shared.getRemainingCreditsMessage() ?? "No credits")
        return
    }
    
    // Proceed with operation
    // ...
}
```

---

## Feature Gating by Plan

### Check Plan Access

**Gate features by user plan:**
```swift
struct AdvancedFeatureView: View {
    @StateObject private var dataService = FirebaseDataService.shared
    
    var body: some View {
        if dataService.userAccount?.plan.canAccessAdvancedFeatures == true {
            // Show advanced feature
            AdvancedTools()
        } else {
            // Show upgrade prompt
            UpgradePrompt()
        }
    }
}
```

### Limit by Plan

**Enforce team member limits:**
```swift
func canAddTeamMember() -> Bool {
    guard let account = dataService.userAccount else { return false }
    
    let currentTeamMemberCount = node.teamMember != nil ? 1 : 0
    return currentTeamMemberCount < account.plan.maxTeamMembers
}

// Usage in UI
Button("Add Team Member") {
    if canAddTeamMember() {
        showTeamMemberModal()
    } else {
        showUpgradeAlert()
    }
}
.disabled(!canAddTeamMember())
```

### Custom Plan Check

**Add new plan restrictions:**
```swift
extension UserPlan {
    var maxProjectsCount: Int {
        switch self {
        case .trial: return 3
        case .free: return 5
        case .premium: return 20
        case .pro: return -1 // Unlimited
        }
    }
    
    var canExportPDF: Bool {
        switch self {
        case .trial, .premium, .pro: return true
        case .free: return false
        }
    }
}
```

---

## Remote Feature Flags

### Check Feature Availability

**Use remote config to enable/disable features:**
```swift
func isFeatureEnabled(_ featureName: String) -> Bool {
    return FirebaseDataService.shared.appConfig?.isFeatureEnabled(featureName) ?? true
}

// Usage
if isFeatureEnabled("image_generation") {
    ImageGenerationButton()
}

if isFeatureEnabled("team_collaboration") {
    ShareProjectButton()
}
```

### Feature Flag Examples

**Set in Firestore `config/app` document:**
```json
{
  "featuresEnabled": {
    "image_generation": true,
    "team_members": true,
    "advanced_rag": false,
    "collaboration": false,
    "pdf_export": true,
    "custom_system_prompts": true,
    "beta_features": false
  }
}
```

**Use in code:**
```swift
// Gradual rollout of new feature
if isFeatureEnabled("beta_features") {
    NewExperimentalFeature()
}

// Kill switch for problematic feature
if isFeatureEnabled("advanced_rag") {
    RAGSearchView()
} else {
    BasicSearchView()
}
```

---

## User Analytics Tracking

### Track User Actions

**Update metadata after key events:**
```swift
func trackNodeCreation() async {
    guard let userId = FirebaseAuthService.shared.currentUser?.uid,
          var metadata = dataService.userAccount?.metadata else { return }
    
    metadata.totalNodesCreated += 1
    await dataService.updateUserMetadata(userId: userId, metadata: metadata)
}

func trackEdgeCreation() async {
    guard let userId = FirebaseAuthService.shared.currentUser?.uid,
          var metadata = dataService.userAccount?.metadata else { return }
    
    metadata.totalEdgesCreated += 1
    await dataService.updateUserMetadata(userId: userId, metadata: metadata)
}
```

### Usage in CanvasViewModel

**Add to existing methods:**
```swift
func createNode(...) {
    // Existing node creation code
    // ...
    
    // Track analytics
    Task {
        await trackNodeCreation()
    }
}
```

### Custom Metadata Fields

**Extend UserMetadata:**
```swift
struct UserMetadata: Codable {
    // Existing fields
    var totalNodesCreated: Int = 0
    var totalMessagesGenerated: Int = 0
    var totalEdgesCreated: Int = 0
    
    // Add new tracking
    var lastActiveDate: Date = Date()
    var favoriteFeature: String?
    var projectsCreated: Int = 0
    var notesCreated: Int = 0
    var imagesUploaded: Int = 0
    var averageResponseTime: Double = 0.0
    var preferredSystemPrompt: String?
}
```

---

## Error Handling & Feedback

### Auth Error Display

**Show friendly auth errors:**
```swift
func handleAuthError(_ error: Error) {
    let message: String
    
    if let authError = error as? AuthError {
        message = authError.errorDescription ?? "Authentication failed"
    } else {
        message = error.localizedDescription
    }
    
    // Show alert or toast
    showAlert("Sign In Failed", message: message)
}
```

### Credit Deduction Feedback

**Notify user of credit usage:**
```swift
func showCreditUsageToast(amount: Int) {
    let message = "Used \(amount) credit\(amount == 1 ? "" : "s")"
    
    // Show toast notification
    Toast.show(message, icon: "star.fill", duration: 2.0)
}

// In CanvasViewModel after successful generation
await CreditTracker.shared.trackGeneration(...)
showCreditUsageToast(amount: creditsUsed)
```

---

## Admin Helpers

### Admin Check Extension

**Add admin role checking:**
```swift
extension UserAccount {
    var isAdmin: Bool {
        // Check against list of admin emails
        let adminEmails = ["admin@jamai.app", "support@jamai.app"]
        return adminEmails.contains(email)
    }
}
```

### Admin-Only UI

**Show admin controls:**
```swift
if dataService.userAccount?.isAdmin == true {
    Menu("Admin") {
        Button("View All Users") { showAllUsers() }
        Button("Grant Credits") { showCreditGrantModal() }
        Button("Force Update") { triggerForceUpdate() }
        Button("Enable Maintenance") { enableMaintenanceMode() }
    }
}
```

### Bulk Operations

**Admin credit grant:**
```swift
func grantCreditsToAllUsers(amount: Int) async {
    let db = Firestore.firestore()
    
    do {
        let snapshot = try await db.collection("users").getDocuments()
        
        for document in snapshot.documents {
            await dataService.grantCredits(
                userId: document.documentID,
                amount: amount,
                type: .adminAdjustment,
                description: "Holiday bonus credits"
            )
        }
    } catch {
        print("Failed to grant credits: \(error)")
    }
}
```

---

## Offline Support

### Cache User Data

**Store locally for offline use:**
```swift
class UserCache {
    @AppStorage("cachedCredits") private var cachedCredits: Int = 0
    @AppStorage("cachedPlan") private var cachedPlan: String = "free"
    
    func updateCache(from account: UserAccount) {
        cachedCredits = account.credits
        cachedPlan = account.plan.rawValue
    }
    
    func getCachedCredits() -> Int {
        return cachedCredits
    }
}
```

### Optimistic Updates

**Update UI immediately, sync later:**
```swift
func deductCreditsOptimistically(amount: Int) {
    // Update local state immediately
    if var account = dataService.userAccount {
        account.credits -= amount
        dataService.userAccount = account
    }
    
    // Sync with server in background
    Task {
        await dataService.deductCredits(
            userId: currentUserId,
            amount: amount,
            description: "AI generation"
        )
    }
}
```

---

## Testing Utilities

### Mock User Account

**For SwiftUI previews:**
```swift
extension UserAccount {
    static var preview: UserAccount {
        UserAccount(
            id: "preview-user",
            email: "test@example.com",
            displayName: "Test User",
            plan: .premium,
            credits: 5000
        )
    }
    
    static var lowCredits: UserAccount {
        var account = preview
        account.credits = 5
        return account
    }
    
    static var expired: UserAccount {
        var account = preview
        account.plan = .trial
        account.planExpiresAt = Date().addingTimeInterval(-86400) // Yesterday
        return account
    }
}
```

### Preview with Auth

**Test authenticated views:**
```swift
#Preview {
    UserSettingsView()
        .environmentObject(FirebaseAuthService.shared)
        .environmentObject(FirebaseDataService.shared)
        .onAppear {
            // Mock data for preview
            FirebaseDataService.shared.userAccount = .preview
        }
}
```

### Test Credit Scenarios

**Unit test helpers:**
```swift
func testCreditDeduction() async {
    let tracker = CreditTracker.shared
    
    // Setup
    let initialCredits = 100
    let promptText = "Test prompt"
    let responseText = String(repeating: "a", count: 4000) // ~1000 tokens
    
    // Execute
    await tracker.trackGeneration(
        promptText: promptText,
        responseText: responseText,
        nodeId: UUID()
    )
    
    // Verify
    XCTAssertEqual(dataService.userAccount?.credits, initialCredits - 1)
}
```

---

## Notifications & Alerts

### Low Credit Warning

**Proactive notification:**
```swift
func checkAndWarnLowCredits() {
    guard let account = dataService.userAccount else { return }
    
    if account.credits < 10 && account.credits > 0 {
        showNotification(
            title: "Low on Credits",
            message: "You have \(account.credits) credits remaining. Upgrade your plan to continue."
        )
    }
}
```

### Plan Expiration Warning

**Trial expiration reminder:**
```swift
func checkTrialExpiration() {
    guard let account = dataService.userAccount,
          account.plan == .trial,
          let expiresAt = account.planExpiresAt else { return }
    
    let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0
    
    if daysRemaining <= 3 && daysRemaining > 0 {
        showNotification(
            title: "Trial Ending Soon",
            message: "Your trial expires in \(daysRemaining) day\(daysRemaining == 1 ? "" : "s"). Upgrade to keep your credits!"
        )
    }
}
```

---

## Dashboard Queries

### Firestore Query Examples

**Get active users (last 7 days):**
```swift
func getActiveUsers() async -> [UserAccount] {
    let db = Firestore.firestore()
    let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    
    do {
        let snapshot = try await db.collection("users")
            .whereField("lastLoginAt", isGreaterThan: Timestamp(date: sevenDaysAgo))
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: UserAccount.self)
        }
    } catch {
        print("Error fetching active users: \(error)")
        return []
    }
}
```

**Get credit usage stats:**
```swift
func getCreditUsageStats() async -> (total: Int, average: Double) {
    let db = Firestore.firestore()
    
    do {
        let snapshot = try await db.collection("users").getDocuments()
        
        let totalUsed = snapshot.documents.reduce(0) { sum, doc in
            let used = doc.data()["creditsUsedThisMonth"] as? Int ?? 0
            return sum + used
        }
        
        let average = Double(totalUsed) / Double(max(1, snapshot.documents.count))
        
        return (total: totalUsed, average: average)
    } catch {
        return (total: 0, average: 0.0)
    }
}
```

**Get plan distribution:**
```swift
func getPlanDistribution() async -> [UserPlan: Int] {
    let db = Firestore.firestore()
    var distribution: [UserPlan: Int] = [:]
    
    do {
        let snapshot = try await db.collection("users").getDocuments()
        
        for doc in snapshot.documents {
            if let planString = doc.data()["plan"] as? String,
               let plan = UserPlan(rawValue: planString) {
                distribution[plan, default: 0] += 1
            }
        }
    } catch {
        print("Error getting plan distribution: \(error)")
    }
    
    return distribution
}
```

---

## Best Practices

### ✅ Always Check Auth State
```swift
guard FirebaseAuthService.shared.isAuthenticated else {
    showAuthRequired()
    return
}
```

### ✅ Handle Errors Gracefully
```swift
do {
    try await dataService.updateUserPlan(userId: userId, plan: .premium)
} catch {
    showError("Failed to upgrade plan: \(error.localizedDescription)")
    // Rollback UI changes if needed
}
```

### ✅ Update UI on Main Thread
```swift
Task { @MainActor in
    dataService.userAccount = updatedAccount
}
```

### ✅ Use Debouncing for Real-time Updates
```swift
private var updateWorkItem: DispatchWorkItem?

func updateUserPreference(_ key: String, value: Any) {
    updateWorkItem?.cancel()
    
    let workItem = DispatchWorkItem {
        Task {
            await dataService.updatePreference(key, value)
        }
    }
    
    updateWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
}
```

### ✅ Cache for Performance
```swift
// Don't fetch every time
private var cachedAppConfig: AppConfig?
private var lastConfigFetch: Date?

func getAppConfig() async -> AppConfig? {
    if let cached = cachedAppConfig,
       let lastFetch = lastConfigFetch,
       Date().timeIntervalSince(lastFetch) < 300 { // 5 min cache
        return cached
    }
    
    // Fetch fresh config
    if let config = dataService.appConfig {
        cachedAppConfig = config
        lastConfigFetch = Date()
        return config
    }
    
    return nil
}
```

---

## Common Patterns

### Combine Credit Check + Action
```swift
func performAIActionWithCreditCheck(_ action: @escaping () async -> Void) {
    guard CreditTracker.shared.canGenerateResponse() else {
        showUpgradePrompt()
        return
    }
    
    Task {
        await action()
    }
}

// Usage
performAIActionWithCreditCheck {
    await generateResponse()
}
```

### Plan-gated Button
```swift
struct PlanGatedButton: View {
    let requiredPlan: UserPlan
    let title: String
    let action: () -> Void
    
    @StateObject private var dataService = FirebaseDataService.shared
    
    var body: some View {
        Button(title) {
            if canAccess {
                action()
            } else {
                showUpgradeAlert()
            }
        }
        .disabled(!canAccess)
        .opacity(canAccess ? 1.0 : 0.6)
    }
    
    private var canAccess: Bool {
        guard let userPlan = dataService.userAccount?.plan else { return false }
        return userPlan.rawValue >= requiredPlan.rawValue
    }
}
```

---

**More examples and patterns available in the full documentation.**
