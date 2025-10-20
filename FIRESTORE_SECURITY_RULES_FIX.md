# Firestore Security Rules Fix

## The Problem

You're seeing these errors:
```
Permission denied: Missing or insufficient permissions.
Write at credit_transactions/... failed
```

This happens because your Firestore security rules don't allow writing to the `credit_transactions` collection.

## The Solution

### Step 1: Open Firebase Console
1. Go to https://console.firebase.google.com
2. Select your project
3. Click **Firestore Database** in the left menu
4. Click the **Rules** tab

### Step 2: Replace Your Rules

**Copy and paste these rules exactly:**

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Users collection - users can read/write their own data
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Credit transactions - authenticated users can create transactions for themselves
    match /credit_transactions/{transactionId} {
      // Users can read their own transactions
      allow read: if request.auth != null && 
                     resource.data.userId == request.auth.uid;
      
      // Users can create transactions where userId matches their auth.uid
      allow create: if request.auth != null && 
                       request.resource.data.userId == request.auth.uid;
      
      // No updates or deletes (audit trail should be immutable)
      allow update, delete: if false;
    }
    
    // App config - everyone can read, only console can write
    match /config/{document} {
      allow read: if true;
      allow write: if false; // Update via Firebase Console only
    }
  }
}
```

### Step 3: Publish
Click the **Publish** button at the top right of the rules editor.

### Step 4: Verify
Wait 10-20 seconds for the rules to propagate, then try using your app again.

## What These Rules Do

### ✅ Users Collection
- Users can **read and write** only their own user document
- Document ID must match their authenticated user ID

### ✅ Credit Transactions Collection  
- Users can **read** their own transactions
- Users can **create** new transactions (required for credit tracking)
- The `userId` field in the transaction must match their auth UID
- **No updates or deletes** - transactions are immutable audit logs

### ✅ Config Collection
- Everyone can **read** app configuration
- Only Firebase Console can write (not from app)

## Why This Fixes It

The previous rules had issues:
1. ❌ `resource.data.userId` doesn't exist during `create` operations
2. ❌ Rules didn't validate the `userId` field matches the authenticated user
3. ✅ New rules use `request.resource.data.userId` which checks the incoming data
4. ✅ Ensures users can only create transactions for themselves

## Still Having Issues?

### Check Authentication
Make sure you're signed in:
```swift
// In your app, check:
print("Current user: \(FirebaseAuthService.shared.currentUser?.uid ?? "none")")
```

### Check the Console
After making a credit transaction, check the Firebase Console logs:
- Firebase Console → Firestore → Data tab
- Look for new documents in `credit_transactions`
- Verify the `userId` field matches your authenticated user

### Test in Rules Playground
1. Firebase Console → Firestore → Rules tab
2. Click **Rules Playground** button
3. Test these operations:
   - **Location:** `/credit_transactions/test-id`
   - **Operation:** Create
   - **Authenticated:** Yes (use your test user UID)
   - **Data:**
   ```json
   {
     "userId": "your-test-uid",
     "amount": -10,
     "type": "ai_generation"
   }
   ```

This should show ✅ **Allowed** if your rules are correct.
