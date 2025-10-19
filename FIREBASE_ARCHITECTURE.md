# Firebase Architecture Overview

Visual guide to the Firebase integration architecture in JamAI.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         JamAI App                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────┐         ┌──────────────────┐        │
│  │  Authentication  │         │  User Interface  │        │
│  │      Views       │         │     Components   │        │
│  │                  │         │                  │        │
│  │ • LoginView      │         │ • UserSettings   │        │
│  │ • SignUpView     │         │ • CreditDisplay  │        │
│  │ • OAuthButtons   │         │ • PlanCards      │        │
│  └────────┬─────────┘         └────────┬─────────┘        │
│           │                            │                   │
│           └────────────┬───────────────┘                   │
│                        │                                   │
│           ┌────────────▼────────────┐                      │
│           │   FirebaseAuthService   │                      │
│           │  (Authentication Logic) │                      │
│           └────────────┬────────────┘                      │
│                        │                                   │
│                        │                                   │
│  ┌─────────────────────▼──────────────────────┐           │
│  │         FirebaseDataService                │           │
│  │      (Firestore Operations)                │           │
│  │                                             │           │
│  │  • loadUserAccount()                       │           │
│  │  • deductCredits()                         │           │
│  │  • updateUserPlan()                        │           │
│  │  • getCreditHistory()                      │           │
│  │  • shouldBlockApp()                        │           │
│  └─────────────────────┬──────────────────────┘           │
│                        │                                   │
│  ┌─────────────────────▼──────────────────────┐           │
│  │          CreditTracker                     │           │
│  │      (AI Usage Tracking)                   │           │
│  │                                             │           │
│  │  • canGenerateResponse()                   │           │
│  │  • trackGeneration()                       │           │
│  │  • calculateCredits()                      │           │
│  └─────────────────────┬──────────────────────┘           │
│                        │                                   │
│           ┌────────────▼────────────┐                      │
│           │   CanvasViewModel       │                      │
│           │  (AI Generation)        │                      │
│           │                         │                      │
│           │  • generateResponse()   │                      │
│           │  • Credit checks ✓      │                      │
│           │  • Track usage ✓        │                      │
│           └─────────────────────────┘                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                         │
                         │ Firebase SDK
                         │
┌────────────────────────▼─────────────────────────────────────┐
│                    Firebase Backend                          │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │ Firebase Auth   │  │   Firestore DB  │  │  Analytics  │ │
│  │                 │  │                 │  │             │ │
│  │ • Email/Pass    │  │ Collections:    │  │ • Events    │ │
│  │ • Google OAuth  │  │  - users/       │  │ • Users     │ │
│  │ • Apple Sign-In │  │  - transactions │  │ • Sessions  │ │
│  │                 │  │  - config/      │  │             │ │
│  └─────────────────┘  └─────────────────┘  └─────────────┘ │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## Data Flow Diagrams

### 1. Authentication Flow

```
User Action                 App                    Firebase
    │                       │                         │
    ├─ Click "Sign Up" ────►│                         │
    │                       │                         │
    │                       ├─ Create Account ───────►│
    │                       │   (Email + Password)    │
    │                       │                         │
    │                       │◄── User UID ────────────┤
    │                       │                         │
    │                       ├─ Create User Doc ──────►│
    │                       │   in Firestore          │
    │                       │                         │
    │                       │◄── Success ─────────────┤
    │                       │                         │
    │◄─ Show Main App ──────┤                         │
    │   (Authenticated)     │                         │
```

### 2. Credit Deduction Flow

```
AI Request              CanvasViewModel         CreditTracker       Firestore
    │                         │                      │                 │
    ├─ Generate Response ────►│                      │                 │
    │                         │                      │                 │
    │                         ├─ Check Credits ─────►│                 │
    │                         │                      │                 │
    │                         │                      ├─ Query User ───►│
    │                         │                      │                 │
    │                         │                      │◄── Credits ─────┤
    │                         │                      │                 │
    │                         │◄── Can Generate ─────┤                 │
    │                         │    (Yes/No)          │                 │
    │                         │                      │                 │
    │                         ├─ Call Gemini API    │                 │
    │                         │   (Generate text)    │                 │
    │                         │                      │                 │
    │                         ├─ Track Usage ───────►│                 │
    │                         │   (prompt + response)│                 │
    │                         │                      │                 │
    │                         │                      ├─ Deduct ───────►│
    │                         │                      │   Credits       │
    │                         │                      │                 │
    │                         │                      ├─ Log ──────────►│
    │                         │                      │   Transaction   │
    │                         │                      │                 │
    │◄─ Show Response ────────┤                      │                 │
```

### 3. Plan Upgrade Flow

```
User                  UserSettingsView      FirebaseData        Firestore
 │                           │                Service              │
 ├─ Click "Upgrade" ────────►│                  │                 │
 │                           │                  │                 │
 │                           ├─ updatePlan() ──►│                 │
 │                           │                  │                 │
 │                           │                  ├─ Update ───────►│
 │                           │                  │   User Doc      │
 │                           │                  │   - plan        │
 │                           │                  │   - credits     │
 │                           │                  │                 │
 │                           │                  ├─ Create ───────►│
 │                           │                  │   Transaction   │
 │                           │                  │                 │
 │                           │                  │◄── Success ─────┤
 │                           │                  │                 │
 │                           │◄── Updated ──────┤                 │
 │                           │    Account       │                 │
 │                           │                  │                 │
 │◄─ Show New Plan ──────────┤                  │                 │
 │   & Credits               │                  │                 │
```

### 4. Maintenance Mode Flow

```
App Launch            JamAIApp           FirebaseData          Firestore
    │                    │                 Service                │
    ├─ Initialize ──────►│                   │                   │
    │                    │                   │                   │
    │                    ├─ Configure       │                   │
    │                    │   Firebase        │                   │
    │                    │                   │                   │
    │                    ├─ Load Config ────►│                   │
    │                    │                   │                   │
    │                    │                   ├─ Listen to ──────►│
    │                    │                   │   config/app      │
    │                    │                   │                   │
    │                    │                   │◄── AppConfig ─────┤
    │                    │                   │   isMaintenanceMode│
    │                    │                   │                   │
    │                    │◄── Config ────────┤                   │
    │                    │                   │                   │
    │                    ├─ Check Block      │                   │
    │                    │   shouldBlockApp()│                   │
    │                    │                   │                   │
    │◄─ Show View ───────┤                   │                   │
    │   (Auth/Maintenance│                   │                   │
    │    /Main)          │                   │                   │
```

---

## Database Schema

### Firestore Collections Structure

```
firestore/
│
├── users/
│   └── {userId}/
│       ├── id: string
│       ├── email: string
│       ├── displayName?: string
│       ├── photoURL?: string
│       ├── plan: "trial"|"free"|"premium"|"pro"
│       ├── credits: number
│       ├── creditsUsedThisMonth: number
│       ├── isActive: boolean
│       ├── createdAt: timestamp
│       ├── lastLoginAt: timestamp
│       ├── planExpiresAt?: timestamp
│       └── metadata: {
│           totalNodesCreated: number
│           totalMessagesGenerated: number
│           totalEdgesCreated: number
│           lastAppVersion: string
│           deviceInfo: string
│       }
│
├── credit_transactions/
│   └── {transactionId}/
│       ├── id: string
│       ├── userId: string
│       ├── amount: number (positive or negative)
│       ├── type: "ai_generation"|"monthly_grant"|"plan_upgrade"|"admin_adjustment"
│       ├── description: string
│       ├── timestamp: timestamp
│       └── metadata?: map
│
└── config/
    └── app/
        ├── isMaintenanceMode: boolean
        ├── maintenanceMessage?: string
        ├── minimumVersion: string
        ├── forceUpdate: boolean
        ├── featuresEnabled: map<string, boolean>
        ├── announcementMessage?: string
        └── lastUpdated: timestamp
```

---

## Component Dependencies

```
┌────────────────────────────────────────────────┐
│               View Layer                       │
│  (AuthenticationView, UserSettingsView, etc)   │
└───────────────┬────────────────────────────────┘
                │
                │ ObservableObject
                │ @StateObject
                │
┌───────────────▼────────────────────────────────┐
│            Service Layer                       │
│  • FirebaseAuthService                         │
│  • FirebaseDataService                         │
│  • CreditTracker                               │
└───────────────┬────────────────────────────────┘
                │
                │ Firebase SDK
                │ (Auth, Firestore, Core)
                │
┌───────────────▼────────────────────────────────┐
│            Model Layer                         │
│  • UserAccount                                 │
│  • UserPlan                                    │
│  • CreditTransaction                           │
│  • AppConfig                                   │
└───────────────┬────────────────────────────────┘
                │
                │ Codable
                │ Firestore.Encoder/Decoder
                │
┌───────────────▼────────────────────────────────┐
│           Firebase Backend                     │
│  • Authentication                              │
│  • Firestore Database                          │
│  • Analytics (optional)                        │
└────────────────────────────────────────────────┘
```

---

## Security Architecture

```
┌──────────────────────────────────────────────────┐
│                 Client App                       │
│  • Stores Firebase Auth token                   │
│  • No sensitive keys in code                     │
│  • API calls authenticated automatically         │
└────────────────┬─────────────────────────────────┘
                 │
                 │ HTTPS + Auth Token
                 │
┌────────────────▼─────────────────────────────────┐
│            Firebase Auth                         │
│  • Validates user credentials                    │
│  • Issues secure tokens (JWT)                    │
│  • Manages sessions                              │
└────────────────┬─────────────────────────────────┘
                 │
                 │ Authenticated Requests
                 │
┌────────────────▼─────────────────────────────────┐
│         Firestore Security Rules                 │
│  • Validate request.auth.uid                     │
│  • User can only access own data                 │
│  • Read-only access to config                    │
│  • Server-side enforcement                       │
└────────────────┬─────────────────────────────────┘
                 │
                 │ Authorized Operations
                 │
┌────────────────▼─────────────────────────────────┐
│          Firestore Database                      │
│  • Encrypted at rest                             │
│  • Encrypted in transit                          │
│  • Automatic backups                             │
└──────────────────────────────────────────────────┘
```

---

## State Management Flow

```
                    ┌─────────────────┐
                    │   Firebase      │
                    │   Backend       │
                    └────────┬────────┘
                             │
                             │ Real-time Updates
                             │ (Snapshots)
                             │
            ┌────────────────▼────────────────┐
            │   FirebaseDataService           │
            │   @Published userAccount        │
            │   @Published appConfig          │
            └────────────────┬────────────────┘
                             │
                             │ SwiftUI Bindings
                             │ @StateObject
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
┌───────▼────────┐  ┌────────▼────────┐  ┌───────▼────────┐
│  Auth Views    │  │  Settings View  │  │  Canvas View   │
│                │  │                 │  │                │
│  • Login       │  │  • Profile      │  │  • AI Gen      │
│  • Signup      │  │  • Credits      │  │  • Credit      │
│  • OAuth       │  │  • Plans        │  │    Check       │
└────────────────┘  └─────────────────┘  └────────────────┘

All views automatically update when Firebase data changes
```

---

## Performance Optimization

### 1. Credit Caching Strategy

```
┌──────────────────────────────────────────┐
│          CreditTracker                   │
│                                          │
│  Check Credits:                          │
│  ├─ Read from dataService.userAccount   │
│  │  (already in memory, instant)        │
│  │                                       │
│  Deduct Credits:                         │
│  ├─ Optimistic UI update (instant)      │
│  ├─ Background Firestore sync (300ms)   │
│  └─ Rollback on failure                 │
└──────────────────────────────────────────┘
```

### 2. Real-time Listener Strategy

```
App Launch:
├─ Setup listener for config/app (once)
│  └─ Auto-updates on changes
│
User Login:
├─ Setup listener for users/{userId} (once)
│  └─ Auto-updates credits, plan, etc.
│
On Logout:
└─ Remove all listeners
```

### 3. Query Optimization

```
✅ Good: Query with user ID filter
   db.collection("credit_transactions")
     .where("userId", "==", currentUserId)
     .orderBy("timestamp", "desc")
     .limit(50)

❌ Bad: Fetch all and filter client-side
   db.collection("credit_transactions")
     .get()
     .filter { $0.userId == currentUserId }
```

---

## Error Handling Strategy

```
┌────────────────────────────────────────┐
│         Error Handling Layers          │
├────────────────────────────────────────┤
│                                        │
│  1. Service Layer (FirebaseAuth/Data) │
│     • Catch Firebase errors            │
│     • Map to app-specific errors       │
│     • Log for debugging                │
│                                        │
│  2. ViewModel/Tracker Layer            │
│     • Validate inputs                  │
│     • Set @Published errorMessage      │
│     • Trigger UI alerts                │
│                                        │
│  3. View Layer                         │
│     • Display user-friendly messages   │
│     • Offer retry actions              │
│     • Graceful degradation             │
│                                        │
└────────────────────────────────────────┘
```

---

## Testing Strategy

```
┌────────────────────────────────────────┐
│            Unit Tests                  │
│  • UserAccount model logic             │
│  • Credit calculation                  │
│  • Plan comparison logic               │
└────────────────┬───────────────────────┘
                 │
┌────────────────▼───────────────────────┐
│        Integration Tests               │
│  • FirebaseDataService methods         │
│  • CreditTracker operations            │
│  • Auth flow validation                │
└────────────────┬───────────────────────┘
                 │
┌────────────────▼───────────────────────┐
│           UI Tests                     │
│  • Login/signup flows                  │
│  • Settings navigation                 │
│  • Credit display                      │
└────────────────┬───────────────────────┘
                 │
┌────────────────▼───────────────────────┐
│       Manual Testing                   │
│  • OAuth flows (Google, Apple)         │
│  • Real Firebase backend               │
│  • Cross-device sync                   │
└────────────────────────────────────────┘
```

---

## Deployment Architecture

```
Development Environment
┌───────────────────────────────────┐
│  • Firebase Project: JamAI-Dev    │
│  • Test users only                │
│  • Firestore: Test mode rules     │
└───────────────────────────────────┘

Staging Environment
┌───────────────────────────────────┐
│  • Firebase Project: JamAI-Stage  │
│  • Internal beta testing          │
│  • Firestore: Production rules    │
└───────────────────────────────────┘

Production Environment
┌───────────────────────────────────┐
│  • Firebase Project: JamAI-Prod   │
│  • Real users                     │
│  • Firestore: Production rules    │
│  • Analytics enabled              │
│  • Backups enabled                │
└───────────────────────────────────┘
```

---

## Scalability Considerations

### Current Limits
- **Firestore**: 1M document reads/day (free tier)
- **Auth**: Unlimited sign-ins
- **Storage**: 1GB Firestore storage (free tier)

### Optimization for Scale
1. **Batch Operations**: Combine multiple writes
2. **Query Indexes**: Create composite indexes for common queries
3. **Caching**: Use local persistence for offline support
4. **CDN**: Use Firebase Hosting for static assets
5. **Functions**: Move heavy operations to Cloud Functions

### Growth Path
```
0-1K users:     Free tier (no cost)
1K-10K users:   Blaze plan (~$50-100/month)
10K-100K users: Optimize + scale (~$500-1000/month)
100K+ users:    Enterprise support
```

---

**This architecture is production-ready and scalable to thousands of users.**
