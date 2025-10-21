# JamAI Firebase Cloud Functions

Handles Stripe webhook integration and scheduled tasks for the JamAI application.

## Features

- ✅ Stripe subscription webhook handling
- ✅ Automatic plan updates when subscriptions change
- ✅ Credit grants on successful payments
- ✅ Automatic downgrades on cancellation
- ✅ Monthly credit reset (scheduled)
- ✅ Transaction logging for audit trail

## Quick Start

### Prerequisites

- Node.js 18+
- Firebase CLI: `npm install -g firebase-tools`
- Stripe account with products configured

### Setup

1. **Install dependencies**
   ```bash
   npm install
   ```

2. **Login to Firebase**
   ```bash
   firebase login
   ```

3. **Configure Stripe keys**
   ```bash
   # Use the setup script (recommended)
   chmod +x setup-webhook.sh
   ./setup-webhook.sh
   
   # OR manually:
   firebase functions:config:set stripe.secret_key="sk_test_..."
   firebase functions:config:set stripe.webhook_secret="whsec_..."
   ```

4. **Update Price IDs in src/index.ts**
   ```typescript
   const STRIPE_PRICE_TO_PLAN = {
     'price_YOUR_PRO_ID': 'pro',
     'price_YOUR_TEAMS_ID': 'teams',
     'price_YOUR_ENTERPRISE_ID': 'enterprise',
   };
   ```

5. **Deploy**
   ```bash
   npm run build
   firebase deploy --only functions
   ```

## Functions

### stripeWebhook (HTTP)

Endpoint: `https://REGION-PROJECT_ID.cloudfunctions.net/stripeWebhook`

Handles Stripe webhook events:
- `customer.subscription.created` - Creates/updates subscription
- `customer.subscription.updated` - Updates plan and credits
- `customer.subscription.deleted` - Downgrades to Free
- `invoice.payment_succeeded` - Resets monthly credits
- `invoice.payment_failed` - Marks subscription as past_due
- `customer.created` - Links Stripe customer to Firebase user

### dailyMaintenance (Scheduled)

Runs: Daily at 00:00 UTC

Checks for expired trials and downgrades to Free plan. 

**Note**: Credit resets happen via `invoice.payment_succeeded` webhook when Stripe charges subscription renewals, respecting each user's individual billing cycle.

## Testing

### Test with Stripe CLI

```bash
# Install Stripe CLI
brew install stripe/stripe-cli/stripe

# Login
stripe login

# Forward webhooks to local function
stripe listen --forward-to http://localhost:5001/YOUR_PROJECT/us-central1/stripeWebhook

# Trigger test events
stripe trigger customer.subscription.created
```

### Test with Stripe Dashboard

1. Switch to Test mode
2. Create test customer with Firebase user email
3. Create subscription with one of your products
4. Check Firestore for updated user document
5. Check function logs: `firebase functions:log`

## Development

### Local Development

```bash
# Start local emulators
npm run serve

# View logs in real-time
firebase functions:log --only stripeWebhook
```

### Build

```bash
npm run build
```

### Lint

```bash
npm run lint
```

## Deployment

### Deploy All Functions

```bash
firebase deploy --only functions
```

### Deploy Specific Function

```bash
firebase deploy --only functions:stripeWebhook
firebase deploy --only functions:dailyMaintenance
```

## Monitoring

### View Logs

```bash
# All functions
firebase functions:log

# Specific function
firebase functions:log --only stripeWebhook

# Last 50 entries
firebase functions:log --limit 50
```

### Stripe Dashboard

Monitor webhook deliveries:
1. Go to https://dashboard.stripe.com/webhooks
2. Click your endpoint
3. View "Recent events" tab

## Troubleshooting

### Webhook Not Receiving Events

- Verify webhook URL in Stripe Dashboard
- Check function is deployed: `firebase functions:list`
- Check webhook signature secret is correct
- View delivery attempts in Stripe Dashboard

### Credits Not Updating

- Check Price ID mapping in `src/index.ts`
- Verify user has `stripeCustomerId` in Firestore
- Check function logs for errors

### Common Errors

**"Stripe not configured"**
- Run: `firebase functions:config:get`
- Verify `stripe.secret_key` is set
- Redeploy if needed

**"No user found for Stripe customer"**
- User's `stripeCustomerId` not set
- Create customer with matching email
- Or manually set in Firestore

## Cost

Firebase Functions (Blaze plan):
- First 2M invocations/month: Free
- First 400K GB-seconds/month: Free
- Typical usage: < $1/month for 1000 users

## Support

- Firebase Functions docs: https://firebase.google.com/docs/functions
- Stripe Webhooks docs: https://stripe.com/docs/webhooks
- Setup guide: ../STRIPE_WEBHOOK_SETUP.md

## License

Private - JamAI Application
