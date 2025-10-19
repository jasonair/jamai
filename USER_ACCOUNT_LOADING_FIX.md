# User Account Loading Fix

## Problem

Users were getting stuck in loading loops when:

### Issue 1: Missing Firestore Document
1. Firebase Authentication succeeded (user logged in)
2. But the Firestore user document didn't exist
3. App tried to update last login and failed with: "No document to update"
4. App showed as authenticated but had no user account data

**Error Message:**
```
Failed to update last login: Error Domain=FIRFirestoreErrorDomain Code=5 
"No document to update: projects/jamai-dev/databases/(default)/documents/users/..."
```

### Issue 2: Corrupted Firestore Document
1. User deleted and recreated Firebase Auth account
2. Old Firestore document remained with invalid structure
3. Document decoding failed with: "No value associated with key 'id'"
4. App kept retrying forever without ability to logout

**Error Message:**
```
Failed to load user account: keyNotFound(CodingKeys(stringValue: "id", intValue: nil), 
Swift.DecodingError.Context(..., debugDescription: "No value associated with key ... 'id'"))
```

## Root Cause

The app had a critical gap in user account initialization:
- `FirebaseAuthService` handled authentication successfully
- But `FirebaseDataService.loadUserAccount()` only loaded existing documents
- If document didn't exist, it silently failed without creating one
- `updateLastLogin()` used `updateData()` which requires an existing document

## Solution

### 1. Handle Corrupted Documents
Added nested try-catch in `loadUserAccount()` to detect and fix corrupted documents:

```swift
if document.exists {
    do {
        let account = try document.data(as: UserAccount.self)
        self.userAccount = account
        setupUserListener(userId: userId)
    } catch {
        // Document exists but is corrupted - delete and recreate
        print("⚠️ User document corrupted, deleting and recreating")
        try? await usersCollection.document(userId).delete()
        
        let email = FirebaseAuthService.shared.currentUser?.email ?? ""
        let displayName = FirebaseAuthService.shared.currentUser?.displayName
        await createUserAccount(userId: userId, email: email, displayName: displayName)
    }
}
```

### 2. Auto-Create Missing User Accounts
Updated `FirebaseDataService.loadUserAccount()` to automatically create user accounts if they don't exist:

```swift
if document.exists {
    // Load existing account
    let account = try document.data(as: UserAccount.self)
    self.userAccount = account
    setupUserListener(userId: userId)
} else {
    // Document doesn't exist - create it
    print("User document not found, creating new account for userId: \(userId)")
    
    let email = FirebaseAuthService.shared.currentUser?.email ?? ""
    let displayName = FirebaseAuthService.shared.currentUser?.displayName
    
    await createUserAccount(userId: userId, email: email, displayName: displayName)
}
```

### 2. Made updateLastLogin() Resilient
Changed from `updateData()` to `setData(..., merge: true)` to handle missing documents gracefully:

```swift
// Use setData with merge to create document if it doesn't exist
try await usersCollection.document(userId).setData([
    "lastLoginAt": Timestamp(date: Date())
], merge: true)
```

### 3. Added Loading State
Added loading indicator in `JamAIApp.swift` to prevent showing UI before user account loads:

```swift
@State private var isLoadingUserAccount = false

// Show loading screen
} else if isLoadingUserAccount {
    VStack(spacing: 20) {
        ProgressView()
            .scaleEffect(1.5)
        Text("Loading account...")
            .foregroundColor(.secondary)
    }
```

### 4. Set Up Listener for New Accounts
Ensured `createUserAccount()` sets up real-time listener after creating account:

```swift
self.userAccount = account

// Setup real-time listener for the new account
setupUserListener(userId: userId)
```

### 5. Emergency Logout Button
Added "Sign Out" link to loading screen so users can escape if stuck:

```swift
} else if isLoadingUserAccount {
    VStack(spacing: 20) {
        ProgressView()
        Text("Loading account...")
        
        // Emergency logout button
        Button("Sign Out") {
            try authService.signOut()
            dataService.userAccount = nil
            isLoadingUserAccount = false
        }
    }
}
```

### 6. Loading Timeout
Added 10-second timeout to prevent infinite loading loops:

```swift
await withTaskGroup(of: Void.self) { group in
    group.addTask {
        await dataService.loadUserAccount(userId: userId)
    }
    group.addTask {
        try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
    }
    
    await group.next() // Wait for first to complete
    group.cancelAll()
}
```

### 7. Handle Auth State Changes
Added `onChange` listener to reload user account when authentication state changes:

```swift
.onChange(of: authService.isAuthenticated) { _, isAuthenticated in
    if isAuthenticated, let userId = authService.currentUser?.uid {
        Task {
            isLoadingUserAccount = true
            await dataService.loadUserAccount(userId: userId)
            isLoadingUserAccount = false
        }
    } else {
        dataService.userAccount = nil
        isLoadingUserAccount = false
    }
}
```

## Files Modified

1. **FirebaseDataService.swift**
   - `loadUserAccount()`: Auto-creates account if missing
   - `updateLastLogin()`: Uses merge mode to handle missing docs
   - `createUserAccount()`: Sets up listener after creation

2. **JamAIApp.swift**
   - Added `isLoadingUserAccount` state
   - Added loading screen between auth and main UI
   - Added auth state change handler
   - Clears user account on logout

## Testing

Test these scenarios:
1. ✅ New user signup (creates account automatically)
2. ✅ Existing user login (loads existing account)
3. ✅ Authenticated user with missing Firestore doc (creates account)
4. ✅ **Authenticated user with corrupted Firestore doc (deletes & recreates)**
5. ✅ Sign out and sign in again (clears and reloads account)
6. ✅ Network errors during account loading (shows loading state)
7. ✅ **Loading timeout (stops after 10 seconds, shows logout button)**
8. ✅ **Emergency logout from loading screen (works even if account fails)**

## Benefits

- **No more stuck states**: Users can always logout, even when loading fails
- **Self-healing**: Automatically fixes corrupted documents by deleting and recreating
- **Resilient**: Handles missing and corrupted documents gracefully
- **Better UX**: Shows loading indicator with emergency logout option
- **Timeout protection**: Loading automatically stops after 10 seconds
- **Backward compatible**: Works with existing users

## Database Impact

- New user documents are created with default values:
  - Plan: Trial (1000 credits, 14 days)
  - Email: From Firebase Auth
  - Display name: From Firebase Auth (if available)
  - Timestamps: Created at, last login
- No schema changes required

## Recommendations

1. **Firestore Rules**: Ensure users can create their own documents:
   ```javascript
   match /users/{userId} {
     allow read, write: if request.auth.uid == userId;
   }
   ```

2. **Monitor**: Watch for users without email addresses (edge case)

3. **Admin Dashboard**: Add tool to identify and fix orphaned auth accounts

4. **Future**: Consider Cloud Functions to ensure every auth account has a Firestore doc
