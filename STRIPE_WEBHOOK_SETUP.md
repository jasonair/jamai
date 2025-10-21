# Stripe Webhook Integration Setup Guide

This guide walks you through setting up Stripe webhooks to automatically sync subscriptions with your Firebase user accounts.

## Overview

The webhook system automatically:
- Creates/updates user plans when subscriptions change
- Grants credits when payments succeed
- Downgrades users to Free when subscriptions cancel
- Resets monthly credits on the 1st of each month
- Tracks all transactions in Firestore

## Prerequisites

- Firebase CLI installed: `npm install -g firebase-tools`
- Stripe account with products configured
- Node.js 18+ installed

## Part 1: Stripe Dashboard Setup

### 1. Create Products & Prices

Go to https://dashboard.stripe.com/products and create:

**Pro Plan**
- Name: `JamAI Pro`
- Price: `$15.00 USD / month`
- Billing: Recurring monthly
- Copy the **Price ID** (e.g., `price_1A2B3C4D5E6F7G8H`)

**Teams Plan**
- Name: `JamAI Teams`
- Price: `$30.00 USD / month`
- Billing: Recurring monthly
- Copy the **Price ID**

**Enterprise Plan** (Optional)
- Name: `JamAI Enterprise`
- Price: `$99.00 USD / month` (or custom)
- Billing: Recurring monthly
- Copy the **Price ID**

### 2. Update Price ID Mapping

Edit `functions/src/index.ts` and update the `STRIPE_PRICE_TO_PLAN` object with your actual Price IDs:

```typescript
const STRIPE_PRICE_TO_PLAN: {[key: string]: string} = {
  'price_YOUR_PRO_PRICE_ID': 'pro',
  'price_YOUR_TEAMS_PRICE_ID': 'teams',
  'price_YOUR_ENTERPRISE_PRICE_ID': 'enterprise',
};
```

## Part 2: Firebase Functions Deployment

### 1. Install Dependencies

```bash
cd functions
npm install
```

### 2. Set Stripe Environment Variables

```bash
# Login to Firebase
firebase login

# Set Stripe secret key (from https://dashboard.stripe.com/apikeys)
firebase functions:config:set stripe.secret_key="sk_live_YOUR_SECRET_KEY"

# Set webhook signing secret (you'll get this in Step 4)
firebase functions:config:set stripe.webhook_secret="whsec_YOUR_WEBHOOK_SECRET"
```

**Important**: Use `sk_test_...` for testing and `sk_live_...` for production.

### 3. Deploy Functions

```bash
# Build and deploy
cd ..
firebase deploy --only functions
```

This will deploy:
- `stripeWebhook` - HTTP endpoint for Stripe webhooks
- `dailyMaintenance` - Scheduled function for trial expiration checks

### 4. Get Webhook URL

After deployment, you'll see output like:

```
✔  functions[stripeWebhook(us-central1)] https://us-central1-YOUR-PROJECT.cloudfunctions.net/stripeWebhook
```

Copy this URL - you'll need it for Stripe.

## Part 3: Stripe Webhook Configuration

### 1. Create Webhook Endpoint

Go to https://dashboard.stripe.com/webhooks

Click **Add endpoint** and configure:

- **Endpoint URL**: Paste your Cloud Function URL from above
- **Description**: `JamAI Subscription Sync`
- **Events to send**:
  - `customer.subscription.created`
  - `customer.subscription.updated`
  - `customer.subscription.deleted`
  - `invoice.payment_succeeded`
  - `invoice.payment_failed`
  - `customer.created`

Click **Add endpoint**

### 2. Get Webhook Signing Secret

After creating the endpoint:
1. Click on the webhook endpoint
2. Click **Reveal** under "Signing secret"
3. Copy the secret (starts with `whsec_...`)

### 3. Update Firebase Config

```bash
firebase functions:config:set stripe.webhook_secret="whsec_YOUR_ACTUAL_SECRET"

# Redeploy to apply the new config
firebase deploy --only functions
```

## Part 4: Testing the Integration

### 1. Test Customer Creation

Create a test customer in Stripe Dashboard:
1. Go to https://dashboard.stripe.com/test/customers
2. Click **Add customer**
3. Use your Firebase user email: `jasononguk@gmail.com`

### 2. Test Subscription Creation

1. Go to the customer page
2. Click **Add subscription**
3. Select your **Teams** product
4. Click **Start subscription**

### 3. Verify Firebase Update

Check Firestore:
```bash
# In Firebase Console > Firestore Database > users collection
# Your user document should now have:
{
  "plan": "teams",
  "credits": 1500,
  "creditsUsedThisMonth": 0,
  "stripeCustomerId": "cus_...",
  "stripeSubscriptionId": "sub_...",
  "subscriptionStatus": "active",
  "nextBillingDate": "2025-11-21T08:37:00.000Z"
}
```

### 4. Check Webhook Logs

```bash
# View function logs
firebase functions:log --only stripeWebhook

# You should see:
✅ Received Stripe webhook: customer.subscription.created
📝 Processing subscription update: sub_...
✅ Updated user abc123 to teams plan with 1500 credits
```

## Part 5: Integration with Your App

Currently, users need to **restart the app** after subscribing to see the changes. To enable real-time updates:

### Option A: Add Stripe Checkout to the App (Recommended)

Add Stripe checkout flow directly in `UserSettingsView.swift`:

```swift
// In PlanCard, update the "Select" button
Button {
    Task {
        await checkoutWithStripe(plan: plan)
    }
} label: {
    Text("Subscribe")
}

func checkoutWithStripe(plan: UserPlan) async {
    // TODO: Implement Stripe Checkout Session
    // 1. Create checkout session via your backend
    // 2. Open checkout URL in browser
    // 3. Redirect back to app after success
    // 4. Webhook will update Firebase automatically
}
```

### Option B: External Website Checkout (Current)

Users subscribe via your website, then:
1. Webhook updates Firebase automatically
2. App's real-time listener picks up changes
3. Credits and plan update instantly (no restart needed!)

The real-time listener is already set up in `FirebaseDataService.swift`:

```swift
private func setupUserListener(userId: String) {
    userListener = usersCollection.document(userId).addSnapshotListener { [weak self] snapshot, error in
        // This automatically updates the app when Firebase changes
        let account = try snapshot.data(as: UserAccount.self)
        self?.userAccount = account
    }
}
```

## Part 6: Go Live

### 1. Switch to Live Mode

In Stripe Dashboard, toggle from **Test mode** to **Live mode** (top-right corner)

### 2. Update Firebase Config with Live Keys

```bash
# Get live secret key from https://dashboard.stripe.com/apikeys
firebase functions:config:set stripe.secret_key="sk_live_YOUR_LIVE_SECRET_KEY"

# Create live webhook endpoint (repeat Part 3 in Live mode)
firebase functions:config:set stripe.webhook_secret="whsec_YOUR_LIVE_WEBHOOK_SECRET"

# Deploy
firebase deploy --only functions
```

### 3. Update Webhook URL

In Stripe Live mode:
1. Create new webhook endpoint with your Cloud Function URL
2. Select same events
3. Update webhook secret in Firebase config

## Troubleshooting

### Webhook Not Receiving Events

**Check Stripe Dashboard > Webhooks**
- Click on your endpoint
- Check "Recent events" tab
- Look for failed requests

**Common issues:**
- Wrong URL (missing HTTPS or wrong domain)
- Function not deployed
- Wrong region (should match Firebase project region)

### Credits Not Updating

**Check function logs:**
```bash
firebase functions:log --only stripeWebhook --limit 50
```

**Common issues:**
- Price ID not in `STRIPE_PRICE_TO_PLAN` mapping
- User not found (no matching `stripeCustomerId`)
- Webhook signature verification failed

### Subscription Shows Wrong Plan

**Verify mapping:**
1. Check the Price ID in Stripe Dashboard
2. Confirm it's in `STRIPE_PRICE_TO_PLAN` mapping
3. Check webhook logs for the plan assigned

## Security Best Practices

1. **Always verify webhook signatures** ✅ (already implemented)
2. **Use environment variables for secrets** ✅ (using Firebase config)
3. **Never expose secret keys in code** ✅ (not in repo)
4. **Test in Test mode first** before going live
5. **Monitor webhook failures** in Stripe Dashboard

## Credit Reset Logic

**Credits reset when subscriptions renew** via the `invoice.payment_succeeded` webhook. This respects each user's individual billing cycle:
- User subscribes Jan 15 → Credits reset Feb 15, Mar 15, etc.
- User subscribes Jan 20 → Credits reset Feb 20, Mar 20, etc.

**Trial expirations** are handled by the `dailyMaintenance` function (runs daily at midnight UTC):
- Checks for expired trials
- Downgrades to Free plan
- Resets to 100 credits

Check logs:
```bash
# Credit resets (happens on renewal)
firebase functions:log --only stripeWebhook | grep "payment_succeeded"

# Trial expirations (daily check)
firebase functions:log --only dailyMaintenance
```

## Cost Estimation

Firebase Functions pricing (Blaze plan):
- **Invocations**: First 2M/month free, then $0.40 per million
- **Compute time**: First 400K GB-seconds/month free
- **Networking**: First 5GB/month free

Typical monthly cost for 1000 users:
- ~3000 webhook calls (subscriptions + payments) = **Free**
- 1 scheduled credit reset = **Free**
- **Total**: $0/month (within free tier)

## Support

If you encounter issues:
1. Check Firebase Functions logs
2. Check Stripe webhook delivery attempts
3. Verify Price IDs match in code
4. Ensure webhook signing secret is correct

Need help? Check:
- Firebase Functions docs: https://firebase.google.com/docs/functions
- Stripe webhooks docs: https://stripe.com/docs/webhooks
- Stripe testing: https://stripe.com/docs/testing

## Next Steps

- [ ] Set up Stripe products and prices
- [ ] Deploy Firebase Functions
- [ ] Configure webhook endpoint
- [ ] Test with test mode subscription
- [ ] Verify Firebase updates correctly
- [ ] Go live with production keys
- [ ] Monitor webhook deliveries
- [ ] Optionally: Add checkout flow to app

---

**Your Teams subscription should now sync automatically!** 🎉
