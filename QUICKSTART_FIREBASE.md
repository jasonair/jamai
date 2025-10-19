# Firebase Quick Start Guide

Get Firebase authentication running in 15 minutes.

---

## Prerequisites
- [ ] Google account
- [ ] Xcode project building successfully

---

## Step 1: Create Firebase Project (5 min)

1. Go to https://console.firebase.google.com/
2. Click "Add project"
3. Name: `JamAI-Dev` (or your choice)
4. Click through wizard, accept defaults
5. Wait for project creation

---

## Step 2: Add Apple App (macOS) (3 min)

1. In Project Overview, click **iOS icon** (⊕) - *Note: Firebase uses "iOS" for all Apple platforms*
2. **Bundle ID**: Open Xcode → Target → General → Copy "Bundle Identifier"
   - Example: `com.yourname.JamAI`
   - This works for macOS apps too
3. Paste into Firebase, click "Register app"
4. **Download** `GoogleService-Info.plist`
5. **IMPORTANT**: Replace the placeholder file:
   - Delete existing `GoogleService-Info.plist` in project root
   - Drag downloaded file into Xcode
   - ✅ Check "Copy items if needed"
   - ✅ Check target membership for **JamAI (macOS)**
6. Click "Next" through remaining steps

*Firebase treats macOS apps the same as iOS apps - the same SDK and configuration works for both platforms.*

---

## Step 3: Enable Authentication (2 min)

1. In Firebase Console sidebar: **Authentication**
2. Click "Get started"
3. Go to **"Sign-in method"** tab
4. Enable **"Email/Password"** → Toggle ON → Save
5. Enable **"Google"** → Toggle ON → Select support email → Save
6. Enable **"Apple"** → Toggle ON → Save

---

## Step 4: Create Firestore Database (2 min)

1. In Firebase Console sidebar: **Firestore Database**
2. Click "Create database"
3. Select **"Start in production mode"**
4. Choose location closest to your users (e.g., `us-central1`)
5. Click "Enable"
6. Wait for database creation (30 seconds)

---

## Step 5: Set Up Collections (2 min)

### Create `config/app` document:
1. Click "Start collection"
2. Collection ID: `config`
3. Document ID: `app` (type it manually)
4. Add these fields:

| Field | Type | Value |
|-------|------|-------|
| `isMaintenanceMode` | boolean | `false` |
| `minimumVersion` | string | `"1.0.0"` |
| `forceUpdate` | boolean | `false` |

5. Click "Save"

### Create empty collections:
1. Click "Start collection" → ID: `users` → Add temporary document → Save → Delete document
2. Click "Start collection" → ID: `credit_transactions` → Add temporary document → Save → Delete document

---

## Step 6: Configure Security Rules (1 min)

1. Go to **Firestore** → **Rules** tab
2. Replace all content with:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, create, update: if request.auth != null && request.auth.uid == userId;
    }
    match /credit_transactions/{transactionId} {
      allow read: if request.auth != null && resource.data.userId == request.auth.uid;
    }
    match /config/app {
      allow read: if true;
    }
  }
}
```

3. Click **"Publish"**

---

## Step 7: Add Firebase SDK to Xcode (3 min)

1. Open your Xcode project
2. **File** → **Add Package Dependencies...**
3. Paste URL: `https://github.com/firebase/firebase-ios-sdk`
4. Version: "Up to Next Major Version" (keep default)
5. Click "Add Package"
6. **Select these products** (check boxes):
   - ✅ **FirebaseAuth**
   - ✅ **FirebaseFirestore**
   - ✅ **FirebaseCore**
7. Click "Add Package"
8. Wait for package resolution (~1 min)

9. **Repeat for Google Sign-In:**
   - **File** → **Add Package Dependencies...**
   - URL: `https://github.com/google/GoogleSignIn-iOS`
   - Click "Add Package"
   - Select ✅ **GoogleSignIn**
   - Click "Add Package"

---

## Step 8: Configure OAuth (2 min)

### For Google Sign-In:
1. Open `GoogleService-Info.plist` in Xcode
2. Find the `REVERSED_CLIENT_ID` value (looks like `com.googleusercontent.apps.123456789`)
3. Copy it
4. Open `Info.plist` in Xcode
5. Add new row:
   - Key: `URL types` (if not exists)
   - Type: Array
   - Expand → Add item
   - Type: Dictionary
   - Add under it:
     - Key: `URL Schemes`, Type: Array
     - Add item with your `REVERSED_CLIENT_ID` value

### For Apple Sign-In:
1. Select project in Xcode
2. Select target
3. Go to **"Signing & Capabilities"** tab
4. Click **"+ Capability"**
5. Search and add **"Sign in with Apple"**

---

## Step 9: Build & Test (5 min)

1. **Clean Build Folder**: Product → Clean Build Folder (⌘⇧K)
2. **Build**: Product → Build (⌘B)
3. If build succeeds ✅, **Run**: Product → Run (⌘R)

### Test Authentication:
1. App should show **AuthenticationView**
2. **Test Sign Up:**
   - Enter email: `test@example.com`
   - Enter password: `test123`
   - Click "Create Account"
   - ✅ You should be signed in
3. **Verify in Firebase:**
   - Go to Firebase Console → Authentication → Users
   - Your test user should appear!

### Test Credits:
1. Once signed in, create a node
2. Type a prompt: "Hello world"
3. Generate response
4. **Check Firestore Console:**
   - Firestore → `users` → (your user ID)
   - Verify `credits` decreased from 1000
   - Check `credit_transactions` collection
   - New transaction should appear

---

## ✅ Success Checklist

- [ ] Firebase project created
- [ ] Real `GoogleService-Info.plist` in project
- [ ] Email/Password, Google, and Apple auth enabled
- [ ] Firestore database created with collections
- [ ] Security rules published
- [ ] Firebase SDK packages added
- [ ] OAuth configured (URL schemes + Apple capability)
- [ ] App builds without errors
- [ ] Can sign up with email/password
- [ ] User appears in Firebase Console
- [ ] Credits deduct after AI generation

---

## 🎉 You're Done!

Your Firebase integration is now live. Users can:
- ✅ Sign up and sign in
- ✅ Use trial credits (1000)
- ✅ Generate AI responses
- ✅ View account settings

---

## Next Steps

### Optional Enhancements:
1. **Add more test users** with different plans
2. **Test maintenance mode** (set `isMaintenanceMode: true` in Firestore)
3. **Test Google Sign-In** (click "Continue with Google")
4. **Test Apple Sign-In** (click Apple button)
5. **Review documentation** in `FIREBASE_IMPLEMENTATION.md`

### Production Ready:
1. Create separate Firebase project for production
2. Set up Cloud Functions for monthly credit reset
3. Enable Firebase Analytics
4. Add payment integration (Stripe/RevenueCat)
5. Build admin dashboard

---

## Troubleshooting

### "Firebase app not configured"
→ Make sure `FirebaseApp.configure()` is in `JamAIApp.init()`

### "Invalid GoogleService-Info.plist"
→ Download again from Firebase Console, replace file

### "Google Sign-In fails"
→ Check `REVERSED_CLIENT_ID` in Info.plist URL schemes

### "Permission denied" in Firestore
→ Verify security rules published correctly

### Build errors with Firebase
→ Clean build folder, restart Xcode, rebuild

---

## Resources

- **Full Documentation**: `FIREBASE_IMPLEMENTATION.md`
- **Detailed Checklist**: `FIREBASE_SETUP_CHECKLIST.md`
- **Code Examples**: `FIREBASE_INTEGRATION_EXAMPLES.md`
- **Summary**: `FIREBASE_SUMMARY.md`

---

**Setup Time**: 15 minutes  
**Difficulty**: Easy  
**Result**: Full authentication system with credit tracking! 🚀
