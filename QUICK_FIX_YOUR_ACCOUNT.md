# Quick Fix: Update Your Teams Subscription

Since you've already subscribed to Teams via Stripe but the webhook isn't set up yet, here's how to manually sync your account:

## Option 1: Firebase Console (Easiest - 2 minutes)

1. **Go to Firebase Console**: https://console.firebase.google.com
2. **Select your JamAI project**
3. **Click "Firestore Database"** in left sidebar
4. **Navigate to `users` collection**
5. **Find your user** (email: jasononguk@gmail.com)
6. **Click to edit the document**
7. **Update these fields**:
   ```
   plan: "teams"
   credits: 1500
   creditsUsedThisMonth: 0
   subscriptionStatus: "active"
   ```
8. **Click "Update"**
9. **Restart JamAI app** - Changes sync immediately!

## Option 2: Firebase CLI (If you prefer command line)

```bash
# Login
firebase login

# List your projects to get project ID
firebase projects:list

# Update via Firestore CLI
# Replace YOUR_USER_ID with your actual user document ID
firebase firestore:update users/YOUR_USER_ID \
  plan=teams \
  credits=1500 \
  creditsUsedThisMonth=0 \
  subscriptionStatus=active
```

## After Webhook Setup

Once you complete the webhook setup in `STRIPE_WEBHOOK_SETUP.md`, future subscription changes will sync automatically. No more manual updates needed!

## Verify It Works

After updating:
1. Restart JamAI app
2. Go to Account Settings (menu bar → Account)
3. You should see:
   - Badge: "Teams" (purple)
   - Credits: "1500 / 1500 available"
   - Plan card: Teams marked as "Current"

## Need Help?

If you don't see the changes:
1. Make sure you restarted the app completely
2. Check Firebase Console to verify the update saved
3. Check app logs for any Firebase sync errors

---

**Your Teams subscription is active in Stripe** - this just syncs it to your app account!
