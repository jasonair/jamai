# Stripe Sync Quick Reference Guide

## TL;DR - What You Need to Do

### 1. **Verify Price IDs** (Most Critical!)

Edit `functions/src/index.ts` line 27-31:

```typescript
const STRIPE_PRICE_TO_PLAN: {[key: string]: string} = {
  'price_1SKfaPEVeQAdCfriBk3YNvSp': 'pro',        // ← Replace with YOUR Pro Price ID
  'price_1SKfb9EVeQAdCfriqgQ8z0Kl': 'teams',      // ← Replace with YOUR Teams Price ID
  'price_1SKlghEVeQAdCfriOsC3xS1b': 'enterprise', // ← Replace with YOUR Enterprise Price ID
};
```

**How to get Price IDs:**
1. Stripe Dashboard → Products
2. Click on Pro product → Copy Price ID (starts with `price_`)
3. Repeat for Teams and Enterprise

---

### 2. **Deploy Cloud Functions**

```bash
cd /Users/jasonong/Development/jamai/functions
npm install
firebase deploy --only functions
```

**Copy the webhook URL from output:**
```
✔  functions[stripeWebhook] https://us-central1-YOUR-PROJECT.cloudfunctions.net/stripeWebhook
```

---

### 3. **Configure Stripe Webhook**

1. **Stripe Dashboard → Developers → Webhooks → Add endpoint**
2. Paste the webhook URL from step 2
3. Select these events:
   - ✅ customer.subscription.created
   - ✅ customer.subscription.updated
   - ✅ customer.subscription.deleted
   - ✅ invoice.payment_succeeded
   - ✅ invoice.payment_failed
   - ✅ customer.created
4. Click "Add endpoint"
5. Click "Reveal" under Signing secret → Copy it (starts with `whsec_`)

---

### 4. **Set Firebase Config**

```bash
firebase functions:config:set stripe.webhook_secret="whsec_YOUR_SECRET_FROM_STEP_3"
firebase deploy --only functions
```

---

### 5. **Link Your Account**

**Option A - If you already have a Stripe subscription:**

1. Stripe Dashboard → Customers → Find your email
2. Copy Customer ID (`cus_...`)
3. Firebase Console → Firestore → `users` collection → Find your user
4. Click "Add field":
   - Field: `stripeCustomerId`
   - Type: string
   - Value: `cus_...` (paste from step 2)
5. Save

**Option B - Create a new subscription:**

1. Stripe Dashboard → Customers → Create customer with your Firebase email
2. Add subscription (Teams or Pro)
3. Webhook will automatically link it to your Firebase account

---

### 6. **Verify It Works**

1. Open JamAI app → Account (toolbar)
2. You should see:
   - ✅ Stripe Account: cus_...
   - ✅ Status: Active
   - ✅ Next Billing Date
   - ✅ Your plan (Pro/Teams/Enterprise)
   - ✅ Correct credits (1000/1500/5000)

---

## How Sync Works

### Real-Time Updates (Automatic)

```
Stripe → Webhook → Cloud Function → Firestore → App UI
         (instant)  (verifies &      (updates)   (listens,
                     updates)                     no refresh!)
```

**When you subscribe/cancel/update in Stripe:**
1. Stripe sends event to webhook (< 1 second)
2. Cloud Function verifies signature & updates Firestore (< 2 seconds)
3. App's real-time listener picks up change (< 1 second)
4. **Total time: ~3 seconds from Stripe → App**

### What Gets Synced

| Stripe Event | App Updates |
|-------------|-------------|
| New subscription | Plan, credits, customer ID, status |
| Subscription updated | Plan, credits, status |
| Subscription canceled | Downgrade to Free, 100 credits |
| Payment succeeded | Reset monthly credits |
| Payment failed | Mark as past_due |

---

## Troubleshooting

### "Not Connected to Stripe" in app

**Cause:** No `stripeCustomerId` in Firestore

**Fix:** Follow step 5 above to link your account

---

### Subscription not syncing

**Check 1:** Emails match exactly
```bash
# Stripe customer email MUST match Firebase user email
```

**Check 2:** Webhook receiving events
```
Stripe Dashboard → Webhooks → Your endpoint → Recent events
# Should show green checkmarks ✅
```

**Check 3:** Logs
```bash
firebase functions:log --only stripeWebhook
# Look for: "✅ Updated user..."
```

---

### Wrong credits/plan

**Check Price IDs:**
```typescript
// functions/src/index.ts
const STRIPE_PRICE_TO_PLAN = {
  'price_ACTUAL_ID': 'pro',  // ← Must match your Stripe Price ID exactly
  ...
};
```

**Fix:** Update Price IDs, redeploy:
```bash
firebase deploy --only functions
```

**Trigger resync:**
```
Stripe Dashboard → Subscriptions → Select subscription → 
Actions → Update subscription → Save (no changes needed)
```

This triggers `customer.subscription.updated` webhook.

---

## Quick Commands Reference

```bash
# Check Firebase config
firebase functions:config:get

# Deploy functions
firebase deploy --only functions

# View logs
firebase functions:log --only stripeWebhook

# Set config
firebase functions:config:set stripe.secret_key="sk_..."
firebase functions:config:set stripe.webhook_secret="whsec_..."
```

---

## Status Check

Run this in your browser console (Firebase Console → Firestore → Users):

```javascript
// Check all users with subscriptions
db.collection('users')
  .where('stripeCustomerId', '!=', null)
  .get()
  .then(snapshot => {
    snapshot.forEach(doc => {
      const data = doc.data();
      console.log({
        email: data.email,
        plan: data.plan,
        credits: data.credits,
        status: data.subscriptionStatus,
        customerId: data.stripeCustomerId
      });
    });
  });
```

---

## Emergency Reset

If something is completely wrong with a user's account:

```javascript
// Firebase Console → Firestore → users → [user_id]
// Update document:
{
  "plan": "teams",
  "credits": 1500,
  "creditsUsedThisMonth": 0,
  "stripeCustomerId": "cus_YOUR_ACTUAL_ID",
  "stripeSubscriptionId": "sub_YOUR_ACTUAL_ID",
  "subscriptionStatus": "active",
  "nextBillingDate": "2025-02-21T00:00:00.000Z"
}
```

Then redeploy webhook to prevent overwrite.

---

## Files Modified

✅ **UserAccount.swift** - Has all Stripe fields
✅ **FirebaseDataService.swift** - Has sync functions + real-time listener
✅ **UserSettingsView.swift** - Shows subscription info
✅ **functions/src/index.ts** - Webhook handlers

**No app code changes needed** - just configure Stripe & Firebase!

---

**Next Steps:**
1. Update Price IDs in `functions/src/index.ts`
2. Deploy Cloud Functions
3. Configure Stripe webhook
4. Link your account
5. Test with a subscription

Full details: `STRIPE_SYNC_CHECKLIST.md`
