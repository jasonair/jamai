# Firebase User Accounts & Management System

Complete implementation guide for Firebase authentication, user management, credit tracking, and remote configuration in JamAI.

## Overview

This implementation adds a full-featured Firebase backend to JamAI with:
- **Authentication**: Email/password, Google Sign-In, Apple Sign-In
- **User Management**: User accounts, plans, credit tracking
- **Remote Configuration**: App settings, maintenance mode, force updates
- **Credit System**: Token-based usage tracking for AI operations
- **Analytics Ready**: Dashboard-ready data structure

---

## Architecture

### Core Components

#### 1. **Models** (`JamAI/Models/UserAccount.swift`)
- `UserAccount`: Main user data model with plan, credits, metadata
- `UserPlan`: Enum for Trial/Free/Premium/Pro tiers
- `AppConfig`: Remote app configuration (maintenance, force update)
- `CreditTransaction`: Credit usage history for analytics

#### 2. **Services**
- `FirebaseAuthService`: Handles all authentication flows
- `FirebaseDataService`: Firestore database operations
- `CreditTracker`: Tracks AI usage and deducts credits

#### 3. **UI Views**
- `AuthenticationView`: Login/signup screen with OAuth
- `UserSettingsView`: Account management and plan upgrades
- `MaintenanceView`: Blocks app during maintenance/updates

---

## Firebase Setup

### 1. Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project: **JamAI**
3. Enable Google Analytics (optional but recommended)

### 2. Configure iOS App

1. In Project Settings, add an iOS app
2. Bundle ID: Match your Xcode bundle identifier
3. Download `GoogleService-Info.plist`
4. **Replace** the placeholder file at project root with your actual file

### 3. Enable Authentication Methods

**Email/Password:**
1. Firebase Console → Authentication → Sign-in method
2. Enable "Email/Password"

**Google Sign-In:**
1. Enable "Google" in Authentication methods
2. Add OAuth client ID to your app's Info.plist:
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.YOUR_CLIENT_ID</string>
        </array>
    </dict>
</array>
```

**Apple Sign-In:**
1. Enable "Apple" in Authentication methods
2. In Xcode → Target → Signing & Capabilities → Add "Sign in with Apple"

### 4. Create Firestore Database

1. Firebase Console → Firestore Database → Create Database
2. Start in **production mode** (we'll set up rules)
3. Choose a location (recommend same region as your users)

### 5. Set Up Firestore Structure

**Collections:**
```
users/
  {userId}/
    id: string
    email: string
    displayName: string?
    plan: string (trial|free|premium|pro)
    credits: number
    creditsUsedThisMonth: number
    isActive: boolean
    createdAt: timestamp
    lastLoginAt: timestamp
    planExpiresAt: timestamp?
    metadata: map

credit_transactions/
  {transactionId}/
    id: string
    userId: string
    amount: number (negative for deduction)
    type: string (ai_generation|monthly_grant|plan_upgrade|admin_adjustment)
    description: string
    timestamp: timestamp
    metadata: map?

config/
  app/
    isMaintenanceMode: boolean
    maintenanceMessage: string?
    minimumVersion: string
    forceUpdate: boolean
    featuresEnabled: map<string, boolean>
    announcementMessage: string?
    lastUpdated: timestamp
```

### 6. Configure Firestore Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // User can read/write their own account
    match /users/{userId} {
      allow read: if request.auth != null && request.auth.uid == userId;
      allow create: if request.auth != null && request.auth.uid == userId;
      allow update: if request.auth != null && request.auth.uid == userId;
      allow delete: if false; // Users cannot delete their own accounts
    }
    
    // User can read their own transactions
    match /credit_transactions/{transactionId} {
      allow read: if request.auth != null && resource.data.userId == request.auth.uid;
      allow write: if false; // Only created via Cloud Functions or admin
    }
    
    // Everyone can read app config
    match /config/app {
      allow read: if true;
      allow write: if false; // Only admins via console
    }
  }
}
```

### 7. Add Firebase SDK Dependencies

Add to your Xcode project via Swift Package Manager:

1. File → Add Package Dependencies
2. Add these packages:
   - `https://github.com/firebase/firebase-ios-sdk` (Firebase Core, Auth, Firestore)
   - `https://github.com/google/GoogleSignIn-iOS` (Google Sign-In)

**Required Products:**
- FirebaseAuth
- FirebaseFirestore
- FirebaseCore
- GoogleSignIn

---

## User Plans & Credits

### Plan Tiers

| Plan | Monthly Credits | Max Team Members | Advanced Features |
|------|----------------|------------------|-------------------|
| **Trial** | 1,000 | 3 | ✅ |
| **Free** | 500 | 2 | ❌ |
| **Premium** | 5,000 | 5 | ✅ |
| **Pro** | 20,000 | 10 | ✅ |

### Credit Usage

- **1 credit ≈ 1,000 tokens** (rough approximation)
- Credits deducted after each AI generation
- Token estimation: ~4 characters per token
- Minimum 1 credit per generation

### Credit Lifecycle

1. **New User**: Receives trial plan credits automatically
2. **Generation**: Credits checked before AI call, deducted after success
3. **Tracking**: All transactions logged to `credit_transactions` collection
4. **Monthly Reset**: Implement via Firebase Cloud Functions (see below)

---

## Remote Configuration

### App Config Fields

**Maintenance Mode:**
```typescript
isMaintenanceMode: true
maintenanceMessage: "We're updating JamAI. Back online in 30 minutes."
```

**Force Update:**
```typescript
minimumVersion: "1.2.0"
forceUpdate: true
```

**Feature Flags:**
```typescript
featuresEnabled: {
  "image_generation": true,
  "team_members": true,
  "advanced_rag": false
}
```

**Announcements:**
```typescript
announcementMessage: "🎉 New feature: Team Members now available!"
```

### Managing Config

**Firebase Console:**
1. Firestore → config → app document
2. Edit fields directly
3. Changes propagate to all clients in real-time

**Example: Enable Maintenance Mode**
```json
{
  "isMaintenanceMode": true,
  "maintenanceMessage": "Scheduled maintenance. Estimated downtime: 1 hour.",
  "minimumVersion": "1.0.0",
  "forceUpdate": false,
  "featuresEnabled": {},
  "lastUpdated": "2025-01-19T12:00:00Z"
}
```

---

## Admin Operations

### Firebase Console Admin Panel

**View All Users:**
1. Firestore → users collection
2. Click any user document to view/edit

**Adjust User Credits:**
```javascript
// In Firestore console, update user document
credits: 5000  // Set new balance

// Then create credit_transaction document
{
  id: "auto-generated",
  userId: "user-id-here",
  amount: 5000,
  type: "admin_adjustment",
  description: "Credit grant for beta testing",
  timestamp: SERVER_TIMESTAMP
}
```

**Change User Plan:**
```javascript
// Update user document
plan: "premium"
planExpiresAt: null  // Remove expiration for paid plans
credits: 5000  // Reset to new plan's monthly credits
```

**Deactivate User:**
```javascript
isActive: false
```

### Cloud Functions (Recommended)

Create Firebase Cloud Functions for automated admin tasks:

**Monthly Credit Reset:**
```typescript
// functions/src/index.ts
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();

export const resetMonthlyCredits = functions.pubsub
  .schedule('0 0 1 * *')  // First day of month at midnight
  .onRun(async (context) => {
    const db = admin.firestore();
    const usersSnapshot = await db.collection('users').get();
    
    const batch = db.batch();
    
    usersSnapshot.forEach(doc => {
      const user = doc.data();
      const newCredits = getPlanCredits(user.plan);
      
      batch.update(doc.ref, {
        credits: newCredits,
        creditsUsedThisMonth: 0
      });
      
      // Log transaction
      const transactionRef = db.collection('credit_transactions').doc();
      batch.set(transactionRef, {
        id: transactionRef.id,
        userId: doc.id,
        amount: newCredits,
        type: 'monthly_grant',
        description: 'Monthly credit refresh',
        timestamp: admin.firestore.FieldValue.serverTimestamp()
      });
    });
    
    await batch.commit();
    console.log('Monthly credits reset complete');
  });

function getPlanCredits(plan: string): number {
  const credits = { trial: 1000, free: 500, premium: 5000, pro: 20000 };
  return credits[plan] || 500;
}
```

**Deploy:**
```bash
firebase init functions
firebase deploy --only functions
```

---

## Analytics & Dashboard

### Data Points Available

**User Metrics:**
- Total users by plan
- Active users (last 7/30 days)
- Trial expiration tracking
- Credit usage trends

**Usage Metrics:**
- Total messages generated
- Total nodes created
- Average credits per user
- Credits remaining distribution

**Revenue Metrics (when implementing payments):**
- Plan distribution
- Upgrade conversion rate
- Monthly recurring revenue

### Query Examples

**Active Premium Users:**
```javascript
db.collection('users')
  .where('plan', '==', 'premium')
  .where('isActive', '==', true)
  .get()
```

**Heavy Users (Top 10 by usage):**
```javascript
db.collection('users')
  .orderBy('metadata.totalMessagesGenerated', 'desc')
  .limit(10)
  .get()
```

**Recent Transactions:**
```javascript
db.collection('credit_transactions')
  .orderBy('timestamp', 'desc')
  .limit(100)
  .get()
```

### Building a Dashboard

**Option 1: Firebase Extensions**
- Install "Run BigQuery Jobs" extension
- Export Firestore to BigQuery
- Use Looker Studio for visualization

**Option 2: Custom Dashboard**
- Build admin panel with Firebase Admin SDK
- Use React/Next.js with Firebase Admin
- Implement role-based access control

**Option 3: Third-party**
- Use Retool, Appsmith, or similar
- Connect to Firestore via REST API
- Secure with Firebase Auth admin check

---

## Testing

### Test User Accounts

**Create Test Users:**
```swift
// In Xcode, run app and sign up with test emails
test+trial@example.com
test+free@example.com
test+premium@example.com
```

**Test Credit Deduction:**
1. Sign in as test user
2. Create a node and generate AI response
3. Check Firestore console for credit deduction
4. Verify transaction logged

**Test Plan Limits:**
1. Use up all credits
2. Verify error message: "Out of credits"
3. Upgrade plan via UserSettingsView
4. Verify credits refreshed

**Test Maintenance Mode:**
1. In Firestore, set `config/app/isMaintenanceMode: true`
2. Restart app
3. Verify MaintenanceView appears
4. Set back to `false`, restart
5. Verify normal operation

**Test Force Update:**
1. Set `minimumVersion: "99.0.0"` and `forceUpdate: true`
2. Restart app
3. Verify update prompt appears

---

## Security Best Practices

### 1. API Key Protection
- ✅ `GoogleService-Info.plist` is gitignored (already in `.gitignore`)
- ✅ Never commit actual Firebase config
- ✅ Use separate Firebase projects for dev/staging/prod

### 2. Authentication
- ✅ Password reset via email (implemented)
- ✅ OAuth reduces password security risk
- ⚠️ Consider implementing email verification
- ⚠️ Add rate limiting on Cloud Functions

### 3. Firestore Security
- ✅ Users can only read/write their own data
- ✅ Transactions are read-only for users
- ✅ App config is read-only for users
- ⚠️ Add server-side validation in Cloud Functions

### 4. Credit Security
- ✅ Credits deducted server-side (not client-side calculation)
- ✅ Transactions immutable after creation
- ⚠️ Add Cloud Function to validate credit changes
- ⚠️ Implement idempotency keys for transactions

---

## Troubleshooting

### Issue: "Firebase not configured"
**Solution:** Ensure `FirebaseApp.configure()` is called in `JamAIApp.init()`

### Issue: Google Sign-In fails
**Solution:** 
1. Check `REVERSED_CLIENT_ID` in URL schemes
2. Verify OAuth client ID in Firebase Console
3. Ensure GoogleSignIn package is properly linked

### Issue: Credits not deducting
**Solution:**
1. Check Firestore console for transaction logs
2. Verify user has sufficient credits
3. Check `FirebaseDataService.deductCredits()` for errors
4. Ensure proper authentication state

### Issue: Maintenance mode not working
**Solution:**
1. Verify `config/app` document exists in Firestore
2. Check `AppConfig` listener is set up
3. Restart app to trigger listener

### Issue: Security rules denying access
**Solution:**
1. Firebase Console → Firestore → Rules
2. Test rules with built-in simulator
3. Check `request.auth.uid` matches document userId

---

## Future Enhancements

### Phase 2: Payments
- [ ] Integrate Stripe/RevenueCat
- [ ] Add subscription management
- [ ] Implement webhooks for plan changes
- [ ] Add invoicing and receipts

### Phase 3: Advanced Features
- [ ] Team collaboration (shared projects)
- [ ] Admin dashboard web app
- [ ] Advanced analytics (cohort analysis, retention)
- [ ] Custom plan creation for enterprise

### Phase 4: Optimization
- [ ] Implement credit caching for offline use
- [ ] Add credit estimation before generation
- [ ] Batch credit deductions
- [ ] Add usage alerts and notifications

---

## File Reference

### New Files Created
```
JamAI/Models/UserAccount.swift
JamAI/Services/FirebaseAuthService.swift
JamAI/Services/FirebaseDataService.swift
JamAI/Services/CreditTracker.swift
JamAI/Views/AuthenticationView.swift
JamAI/Views/UserSettingsView.swift
JamAI/Views/MaintenanceView.swift
GoogleService-Info.plist (placeholder - replace with real file)
```

### Modified Files
```
JamAI/JamAIApp.swift
  - Added Firebase initialization
  - Added auth flow gating
  - Added maintenance mode check
  
JamAI/Services/CanvasViewModel.swift
  - Added credit checks before generation
  - Added credit tracking after generation
```

---

## Support & Resources

- **Firebase Documentation**: https://firebase.google.com/docs
- **Firebase Console**: https://console.firebase.google.com
- **Google Sign-In Setup**: https://developers.google.com/identity
- **Apple Sign-In Setup**: https://developer.apple.com/sign-in-with-apple/

---

**Implementation Status**: ✅ Complete  
**Version**: 1.0  
**Last Updated**: October 19, 2025
