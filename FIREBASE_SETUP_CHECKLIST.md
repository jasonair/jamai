# Firebase Setup Checklist

Quick reference checklist for setting up Firebase in JamAI.

## ☐ Prerequisites

- [ ] Active Google account
- [ ] Xcode 15+ installed
- [ ] JamAI project building successfully
- [ ] Apple Developer account (for Apple Sign-In)

---

## ☐ Firebase Project Setup

### 1. Create Project
- [ ] Go to https://console.firebase.google.com/
- [ ] Click "Add project"
- [ ] Name: `JamAI` (or your preferred name)
- [ ] Enable Google Analytics: **Yes** (recommended)
- [ ] Choose Analytics location
- [ ] Click "Create project"

### 2. Add iOS App
- [ ] In Project Overview, click iOS icon
- [ ] Bundle ID: Copy from Xcode → Target → General → Bundle Identifier
  - Should match: `com.yourcompany.JamAI` or similar
- [ ] App nickname: `JamAI macOS`
- [ ] App Store ID: (leave blank for now)
- [ ] Click "Register app"

### 3. Download Config File
- [ ] Download `GoogleService-Info.plist`
- [ ] **Important**: Replace the placeholder file in project root
- [ ] Add to Xcode: Drag into project, ensure "Copy items" is checked
- [ ] Verify it's in target membership

---

## ☐ Authentication Setup

### 4. Enable Email/Password
- [ ] Firebase Console → Build → Authentication
- [ ] Click "Get started" (if first time)
- [ ] Go to "Sign-in method" tab
- [ ] Click "Email/Password"
- [ ] Enable the first toggle (Email/Password)
- [ ] Click "Save"

### 5. Enable Google Sign-In
- [ ] In "Sign-in method" tab, click "Google"
- [ ] Enable toggle
- [ ] Select project support email
- [ ] Click "Save"
- [ ] Copy the "Web client ID" (needed for next step)

### 6. Configure Google Sign-In in Xcode
- [ ] Open `Info.plist` in Xcode
- [ ] Add URL Types array:
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>YOUR_REVERSED_CLIENT_ID_HERE</string>
        </array>
    </dict>
</array>
```
- [ ] Replace with actual `REVERSED_CLIENT_ID` from `GoogleService-Info.plist`

### 7. Enable Apple Sign-In
- [ ] Firebase Console → Authentication → Sign-in method
- [ ] Click "Apple"
- [ ] Enable toggle
- [ ] Click "Save"

### 8. Configure Apple Sign-In in Xcode
- [ ] Select project → Target → Signing & Capabilities
- [ ] Click "+ Capability"
- [ ] Search and add "Sign in with Apple"
- [ ] Ensure capability appears in list

---

## ☐ Firestore Database Setup

### 9. Create Firestore Database
- [ ] Firebase Console → Build → Firestore Database
- [ ] Click "Create database"
- [ ] **Start in production mode** (we'll add custom rules)
- [ ] Choose location (recommend same region as users)
  - US: `us-central1` or `us-east1`
  - Europe: `europe-west1`
  - Asia: `asia-northeast1`
- [ ] Click "Enable"

### 10. Create Collections Structure
- [ ] Click "Start collection"
- [ ] Collection ID: `users`
- [ ] Add first document manually:
  - Document ID: `example-user-id`
  - Fields:
    - `email` (string): `"example@test.com"`
    - `plan` (string): `"trial"`
    - `credits` (number): `1000`
    - `isActive` (boolean): `true`
- [ ] Click "Save"

- [ ] Click "Start collection" again
- [ ] Collection ID: `credit_transactions`
- [ ] Add placeholder document (can delete later)

- [ ] Click "Start collection" again
- [ ] Collection ID: `config`
- [ ] Document ID: `app`
- [ ] Fields:
  - `isMaintenanceMode` (boolean): `false`
  - `minimumVersion` (string): `"1.0.0"`
  - `forceUpdate` (boolean): `false`
  - `featuresEnabled` (map): `{}` (empty map)
- [ ] Click "Save"

### 11. Set Up Security Rules
- [ ] Go to Firestore → Rules tab
- [ ] Replace content with:
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
- [ ] Click "Publish"
- [ ] Verify: "Your rules have been successfully published"

---

## ☐ Xcode Package Dependencies

### 12. Add Firebase iOS SDK
- [ ] Open Xcode project
- [ ] File → Add Package Dependencies...
- [ ] Enter URL: `https://github.com/firebase/firebase-ios-sdk`
- [ ] Dependency Rule: "Up to Next Major Version" (recommended)
- [ ] Click "Add Package"
- [ ] Select these products (check boxes):
  - **FirebaseAuth**
  - **FirebaseFirestore**
  - **FirebaseCore**
- [ ] Click "Add Package"
- [ ] Wait for package resolution (may take 1-2 minutes)

### 13. Add Google Sign-In SDK
- [ ] File → Add Package Dependencies...
- [ ] Enter URL: `https://github.com/google/GoogleSignIn-iOS`
- [ ] Dependency Rule: "Up to Next Major Version"
- [ ] Click "Add Package"
- [ ] Select product:
  - **GoogleSignIn**
- [ ] Click "Add Package"

---

## ☐ Build & Test

### 14. Build Project
- [ ] Clean build folder: Product → Clean Build Folder (⌘⇧K)
- [ ] Build project: Product → Build (⌘B)
- [ ] Verify no errors
- [ ] If errors, check:
  - All packages properly linked
  - `GoogleService-Info.plist` in project
  - Bundle ID matches Firebase config

### 15. Test Authentication
- [ ] Run app (⌘R)
- [ ] Verify AuthenticationView appears
- [ ] **Test Email/Password:**
  - [ ] Click "Sign Up"
  - [ ] Enter email: `test@example.com`
  - [ ] Enter password: `testpass123`
  - [ ] Click "Create Account"
  - [ ] Verify account created
  - [ ] Check Firebase Console → Authentication → Users
  - [ ] Verify user appears in list

- [ ] **Test Google Sign-In:**
  - [ ] Sign out from test account
  - [ ] Click "Continue with Google"
  - [ ] Select Google account
  - [ ] Grant permissions
  - [ ] Verify signed in
  - [ ] Check Firebase Console → Authentication → Users

- [ ] **Test Apple Sign-In:**
  - [ ] Sign out
  - [ ] Click "Sign in with Apple" button
  - [ ] Complete Apple ID flow
  - [ ] Verify signed in

### 16. Test User Account
- [ ] Sign in with any method
- [ ] Menu → Account... (or toolbar button)
- [ ] Verify UserSettingsView shows:
  - [ ] User profile (email, name)
  - [ ] Plan badge (Trial)
  - [ ] Credits count (1000)
  - [ ] Plan cards
- [ ] Close settings

### 17. Test Credit Tracking
- [ ] Create a new node (⌘N or double-click canvas)
- [ ] Add prompt: "Explain quantum computing"
- [ ] Click send/generate
- [ ] Wait for AI response
- [ ] **Check Firestore Console:**
  - [ ] Go to `users/{your-uid}` document
  - [ ] Verify `credits` decreased (e.g., 999 or 998)
  - [ ] Verify `creditsUsedThisMonth` increased
  - [ ] Go to `credit_transactions` collection
  - [ ] Verify new transaction logged with:
    - `type`: `"ai_generation"`
    - `amount`: negative number (e.g., -1)
    - `userId`: your user ID
    - `timestamp`: recent time

### 18. Test Maintenance Mode
- [ ] **In Firestore Console:**
  - [ ] Go to `config/app` document
  - [ ] Edit `isMaintenanceMode` → `true`
  - [ ] Edit `maintenanceMessage` → `"Testing maintenance mode"`
  - [ ] Click "Update"
- [ ] **In app:**
  - [ ] Quit app (⌘Q)
  - [ ] Relaunch app
  - [ ] Verify MaintenanceView appears with message
  - [ ] Click "Quit" button
- [ ] **Disable maintenance:**
  - [ ] Back in Firestore, set `isMaintenanceMode` → `false`
  - [ ] Relaunch app
  - [ ] Verify normal operation

### 19. Test Plan Upgrade
- [ ] Open Account settings
- [ ] Click "Select" on Premium plan
- [ ] **Check Firestore Console:**
  - [ ] User document `plan` should be `"premium"`
  - [ ] `credits` should be `5000`
  - [ ] `creditsUsedThisMonth` should be `0`
  - [ ] New transaction in `credit_transactions` with type `"plan_upgrade"`
- [ ] **In app:**
  - [ ] Verify settings shows "Premium" badge
  - [ ] Verify "5000 credits" displayed

---

## ☐ Security Verification

### 20. Verify Security Rules
- [ ] Firebase Console → Firestore → Rules
- [ ] Click "Rules Playground"
- [ ] Test rule:
  - [ ] Location: `/users/test-user-id`
  - [ ] Simulate read as: Authenticated user `test-user-id`
  - [ ] Click "Run"
  - [ ] Verify: ✅ "Simulated read allowed"
- [ ] Test unauthorized access:
  - [ ] Same location
  - [ ] Simulate read as: Authenticated user `different-user-id`
  - [ ] Click "Run"
  - [ ] Verify: ❌ "Simulated read denied"

---

## ☐ Production Preparation

### 21. Update GoogleService-Info.plist
- [ ] If using staging/production environments
- [ ] Create separate Firebase projects
- [ ] Download separate plist files
- [ ] Use build configurations or schemes to swap

### 22. Configure App Version
- [ ] Xcode → Target → General
- [ ] Set Version: `1.0.0`
- [ ] Set Build: `1`
- [ ] This matches `minimumVersion` in app config

### 23. Enable Analytics (Optional)
- [ ] Firebase Console → Analytics
- [ ] Review default events
- [ ] Enable BigQuery export (optional)
- [ ] Set data retention period

### 24. Set Up Backups
- [ ] Firestore → Settings
- [ ] Consider enabling daily backups
- [ ] Or set up Cloud Scheduler for regular exports

---

## ☐ Documentation

### 25. Document Your Setup
- [ ] Note Firebase Project ID: `________________`
- [ ] Note Bundle ID: `________________`
- [ ] Save admin credentials securely
- [ ] Document any custom configuration

### 26. Team Access
- [ ] Firebase Console → Project Settings → Users and permissions
- [ ] Add team members with appropriate roles:
  - **Owner**: Full access (you)
  - **Editor**: Deploy, database write
  - **Viewer**: Read-only access

---

## ✅ Setup Complete!

If all checkboxes are marked, your Firebase integration is fully configured and tested.

### Next Steps:
1. ✅ All authentication methods working
2. ✅ Credits tracking correctly
3. ✅ Remote config responding
4. ✅ Security rules enforced
5. 🚀 Ready for production use

### Need Help?
- Review `FIREBASE_IMPLEMENTATION.md` for detailed docs
- Check Firebase Console logs for errors
- Test with multiple user accounts
- Monitor Firestore usage in Console

**Questions or Issues?**
- Firebase Support: https://firebase.google.com/support
- Firestore Docs: https://firebase.google.com/docs/firestore
- Auth Docs: https://firebase.google.com/docs/auth
