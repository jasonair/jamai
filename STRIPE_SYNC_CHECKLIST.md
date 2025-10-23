# Stripe Sync Deployment Checklist

Comprehensive guide to ensure JamAI app is fully synced with Stripe subscriptions.

## Current Integration Status

✅ **Complete:**
- UserAccount model has Stripe fields (stripeCustomerId, stripeSubscriptionId, subscriptionStatus, nextBillingDate)
- Firebase Cloud Functions webhook handlers deployed
- Real-time Firestore listener picks up changes automatically
- UI shows subscription info in UserSettingsView
- Sync utility functions in FirebaseDataService

## Pre-Deployment Checklist

### 1. Verify Stripe Products & Pricing

- [ ] **Stripe Dashboard → Products**
  - Pro: $15/month (copy Price ID: `price_...`)
  - Teams: $30/month (copy Price ID: `price_...`)
  - Enterprise: Custom pricing (copy Price ID: `price_...`)

- [ ] **Update functions/src/index.ts**
  ```typescript
  const STRIPE_PRICE_TO_PLAN = {
    'price_ACTUAL_PRO_ID': 'pro',
    'price_ACTUAL_TEAMS_ID': 'teams',
    'price_ACTUAL_ENTERPRISE_ID': 'enterprise',
  };
  ```

### 2. Configure Firebase Environment

- [ ] **Set Stripe Secret Key**
  ```bash
  firebase functions:config:set stripe.secret_key="sk_live_YOUR_ACTUAL_KEY"
  ```

- [ ] **Set Webhook Secret** (get from Stripe after creating webhook)
  ```bash
  firebase functions:config:set stripe.webhook_secret="whsec_YOUR_ACTUAL_SECRET"
  ```

- [ ] **Verify Configuration**
  ```bash
  firebase functions:config:get
  # Should show:
  # {
  #   "stripe": {
  #     "secret_key": "sk_live_...",
  #     "webhook_secret": "whsec_..."
  #   }
  # }
  ```

### 3. Deploy Cloud Functions

- [ ] **Deploy Functions**
  ```bash
  cd functions
  npm install
  npm run build
  cd ..
  firebase deploy --only functions
  ```

- [ ] **Copy Webhook URL** from deployment output
  - Example: `https://us-central1-YOUR_PROJECT.cloudfunctions.net/stripeWebhook`

### 4. Configure Stripe Webhook

- [ ] **Stripe Dashboard → Developers → Webhooks → Add endpoint**
  - Endpoint URL: `https://us-central1-YOUR_PROJECT.cloudfunctions.net/stripeWebhook`
  - Description: `JamAI Subscription Sync - Production`
  - Events to send:
    - [x] `customer.subscription.created`
    - [x] `customer.subscription.updated`
    - [x] `customer.subscription.deleted`
    - [x] `invoice.payment_succeeded`
    - [x] `invoice.payment_failed`
    - [x] `customer.created`

- [ ] **Get Signing Secret**
  - Click the webhook → Reveal signing secret
  - Copy `whsec_...` value

- [ ] **Update Firebase config with signing secret**
  ```bash
  firebase functions:config:set stripe.webhook_secret="whsec_YOUR_ACTUAL_SECRET"
  firebase deploy --only functions
  ```

### 5. Link Existing Users to Stripe

For users who already subscribed via website BEFORE webhook was set up:

#### Option A: Manual Firestore Update

1. Go to Stripe Dashboard → Customers
2. Find customer by email
3. Copy Stripe Customer ID (`cus_...`)
4. Go to Firebase Console → Firestore → `users` collection
5. Find user by email
6. Add fields:
   ```json
   {
     "stripeCustomerId": "cus_...",
     "stripeSubscriptionId": "sub_...",
     "subscriptionStatus": "active",
     "nextBillingDate": "2025-12-21T00:00:00.000Z",
     "plan": "teams",
     "credits": 1500
   }
   ```

#### Option B: Trigger Webhook Manually

1. Stripe Dashboard → Webhooks → Your webhook endpoint
2. Click "Send test webhook"
3. Select `customer.subscription.updated`
4. Choose an existing subscription
5. Send → Check Firestore for updates

### 6. Test Subscription Flow

#### Test 1: New Subscription

- [ ] Create test customer in Stripe with a **new email** (not in Firebase)
- [ ] Add subscription (Teams plan)
- [ ] Verify webhook logs: `firebase functions:log --only stripeWebhook`
- [ ] Check Firestore `users` collection - user should NOT be created (email not in system)
- [ ] Sign up in app with that email
- [ ] User should immediately see Teams plan and 1500 credits

#### Test 2: Existing User Subscription

- [ ] Sign up new user in JamAI app (creates Firebase user on Trial)
- [ ] Go to Stripe Dashboard → Create customer with SAME email
- [ ] Add Teams subscription
- [ ] Webhook should link `stripeCustomerId` to existing Firebase user
- [ ] User's plan should update to Teams with 1500 credits
- [ ] Verify in app: User Settings shows Stripe info

#### Test 3: Subscription Cancellation

- [ ] Cancel a test subscription in Stripe
- [ ] Webhook should trigger `customer.subscription.deleted`
- [ ] User should downgrade to Free plan (100 credits)
- [ ] Verify in app

#### Test 4: Payment Success (Monthly Renewal)

- [ ] Trigger test `invoice.payment_succeeded` event
- [ ] User's credits should reset to plan amount
- [ ] `creditsUsedThisMonth` should reset to 0
- [ ] Check credit_transactions log

### 7. Update App UI Links

- [ ] **UserSettingsView.swift** - Update Stripe billing portal URL
  ```swift
  // Line ~245: Replace test link with production
  if let url = URL(string: "https://billing.stripe.com/p/login/YOUR_PRODUCTION_LINK") {
  ```

- [ ] **UserSettingsView.swift** - Update pricing page URL
  ```swift
  // Line ~288: Verify correct website URL
  if let url = URL(string: "https://jamai.app/pricing") {
  ```

### 8. Monitor Webhook Deliveries

- [ ] **Stripe Dashboard → Webhooks → Your endpoint**
  - Check "Recent events" tab
  - All events should show ✅ (success)
  - Click any event to see request/response details

- [ ] **Firebase Functions Logs**
  ```bash
  firebase functions:log --only stripeWebhook --limit 50
  ```
  - Look for: ✅ Updated user [userId] to [plan] with [credits] credits
  - No ❌ errors

### 9. Test Real-Time Sync in App

- [ ] Open JamAI app, sign in, go to User Settings
- [ ] In Stripe Dashboard, update subscription (change plan or update payment method)
- [ ] Webhook fires → Updates Firestore
- [ ] App's real-time listener picks up change **immediately** (no refresh needed)
- [ ] Credits, plan, and subscription info update in UI

### 10. Handle Edge Cases

#### User subscribes but app doesn't reflect it:

**Diagnosis:**
```bash
# Check webhook logs
firebase functions:log --only stripeWebhook

# Check Firestore
# Firebase Console → Firestore → users → search by email
```

**Common causes:**
- Email mismatch (Stripe customer email ≠ Firebase user email)
- Webhook not firing (check Stripe webhook deliveries)
- Wrong Price ID mapping in Cloud Function
- stripeCustomerId not linked

**Solution:**
- Ensure emails match exactly (case-sensitive)
- Manually trigger webhook resend in Stripe Dashboard
- Check `STRIPE_PRICE_TO_PLAN` mapping
- Manually add `stripeCustomerId` to Firestore user document

#### Multiple subscriptions for same user:

**Diagnosis:**
- Check Stripe customer has only ONE active subscription
- User might have multiple Stripe customer accounts

**Solution:**
- Cancel old subscriptions in Stripe
- Merge duplicate customers (Stripe Dashboard → Customers → Actions → Merge)
- Update `stripeCustomerId` in Firestore to point to active customer

#### Credits not resetting on renewal:

**Diagnosis:**
```bash
# Check for invoice.payment_succeeded events
firebase functions:log | grep "payment_succeeded"
```

**Solution:**
- Verify `invoice.payment_succeeded` event is configured in webhook
- Check webhook is receiving the event (Stripe Dashboard → Webhook → Recent events)
- Manually reset credits via Firestore or Firebase Admin

## Post-Deployment Verification

### For YOUR Account (jasononguk@gmail.com):

- [ ] Check Stripe: Find customer by email → Copy customer ID and subscription ID
- [ ] Check Firestore: `users` collection → Find by email → Verify:
  ```
  stripeCustomerId: "cus_..."
  stripeSubscriptionId: "sub_..."
  subscriptionStatus: "active"
  plan: "teams" (or current plan)
  credits: 1500 (or plan amount)
  nextBillingDate: [date]
  ```
- [ ] Open JamAI app → User Settings → Should show:
  - ✅ Stripe Account: cus_...
  - ✅ Status: Active (green checkmark)
  - ✅ Next Billing Date: [date]
  - ✅ Manage Subscription button

### For All Users:

- [ ] Create Firebase Cloud Function to list all users with/without Stripe IDs:
  ```typescript
  // Admin script to audit users
  const users = await admin.firestore().collection('users').get();
  users.forEach(doc => {
    const data = doc.data();
    console.log({
      email: data.email,
      plan: data.plan,
      hasStripe: !!data.stripeCustomerId,
      credits: data.credits
    });
  });
  ```

## Monitoring & Maintenance

### Daily Checks

- [ ] Monitor webhook delivery rate (should be 100%)
- [ ] Check for failed events in Stripe Dashboard
- [ ] Review Firebase Functions logs for errors

### Weekly Checks

- [ ] Verify trial expirations are processing (dailyMaintenance function)
- [ ] Check credit transaction logs for anomalies
- [ ] Review user plan distribution

### Monthly Checks

- [ ] Audit users without Stripe IDs but on paid plans (data inconsistency)
- [ ] Check for users with credits but canceled subscriptions
- [ ] Review Firestore security rules

## Rollback Plan

If something goes wrong:

1. **Disable webhook in Stripe** (don't delete - just disable)
2. **Check Firebase Functions logs** for errors
3. **Manually update affected users** in Firestore
4. **Re-enable webhook** after fix
5. **Replay failed events** from Stripe Dashboard → Webhooks → Event → Resend

## Emergency Contacts & Links

- **Stripe Dashboard**: https://dashboard.stripe.com
- **Firebase Console**: https://console.firebase.google.com
- **Webhook Endpoint**: https://us-central1-YOUR_PROJECT.cloudfunctions.net/stripeWebhook
- **Documentation**: 
  - STRIPE_WEBHOOK_SETUP.md (detailed setup)
  - functions/README.md (Cloud Functions guide)

## Success Criteria

✅ All paid users have `stripeCustomerId` in Firestore
✅ Subscription status syncs within 30 seconds of Stripe changes
✅ Credits reset automatically on renewal (invoice.payment_succeeded)
✅ Trial expirations handled by dailyMaintenance
✅ No webhook delivery failures in past 7 days
✅ User Settings UI shows correct subscription info
✅ "Manage Subscription" button links to Stripe billing portal

---

**Status**: Ready for production deployment
**Last Updated**: 2025-01-21
**Owner**: Jason Ong
