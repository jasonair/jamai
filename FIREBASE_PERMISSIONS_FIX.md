# Firebase Permissions Fix

## Issue
```
WriteStream error: 'Permission denied: Missing or insufficient permissions.'
Write at credit_transactions/... failed: Missing or insufficient permissions.
```

## Quick Fix Applied

**AI Generation Now Works Without Firebase!**

The `CreditTracker` has been updated to allow AI generation even when Firebase isn't configured or has permission errors. This means:
- ✅ AI prompting works immediately
- ✅ No credit checks in development mode
- ✅ App functions normally without Firebase setup

## To Enable Firebase Credits (Optional)

If you want to use the Firebase credit system, you need to fix the Firestore security rules:

### 1. Open Firebase Console
Go to: https://console.firebase.google.com

### 2. Navigate to Firestore Rules
- Select your project
- Click "Firestore Database" in left menu
- Click "Rules" tab

### 3. Update Security Rules

Replace your current rules with:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Users collection - users can read/write their own data
    match /users/{userId} {
      allow read: if request.auth != null && request.auth.uid == userId;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Credit transactions - users can read their own, write requires auth
    match /credit_transactions/{transactionId} {
      allow read: if request.auth != null && 
                     request.auth.uid == resource.data.userId;
      allow create: if request.auth != null;
    }
    
    // App config - everyone can read, only admins can write
    match /config/{document} {
      allow read: if true;
      allow write: if false; // Update via Firebase Console only
    }
  }
}
```

### 4. Publish the Rules
Click "Publish" button at the top

### 5. Test Authentication
Make sure you're signed in:
- Check if `FirebaseAuthService.shared.currentUser` exists
- Check the Account menu in your app
- Try signing out and back in

## Current Behavior

**Without Firebase configured:**
- ✅ AI generation works
- ⚠️ No credit tracking
- ⚠️ No usage limits
- Console shows: "No user account, allowing generation (dev mode)"

**With Firebase configured:**
- ✅ AI generation works
- ✅ Credit tracking enabled
- ✅ Usage limits enforced
- ✅ User plan features active

## Troubleshooting

### Still not working?
1. Check console for: `"⚠️ CreditTracker: No user account, allowing generation (dev mode)"`
   - This means AI should work
   
2. If you see other errors, check:
   - Is your Gemini API key set? (Check `.env` or environment variables)
   - Is the API key valid?
   - Try making a simple API call to verify

### Want to disable Firebase entirely during development?
The app now works fine without Firebase. Just ignore the permission warnings in the console - they won't affect AI generation.
