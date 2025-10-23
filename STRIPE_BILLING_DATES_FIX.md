# Stripe Billing Dates Fix - October 2025

## Issue

The app was showing **incorrect subscription dates** in the user account settings:
- "Usage since Oct 1, 2025" (always first of current month)
- "Credits renew in X days (Nov 1, 2025)" (always first of next month)

**Problem**: Dates were calculated using calendar months, not actual Stripe billing cycles.

**Example**: If you subscribed on Oct 15th, your actual Stripe billing is Oct 15 → Nov 15, but the app showed Oct 1 → Nov 1.

## Root Cause

The `UserSettingsView` functions were using calendar-based calculations:
- `formattedMonthStart()` - Got first day of current calendar month
- `renewalDateText()` - Got first day of next calendar month

The app **was not using** the `nextBillingDate` field from Stripe, and had **no field** for tracking when the current billing period started.

## Solution

### 1. Data Model Update (`UserAccount.swift`)

Added `currentPeriodStart` field to track actual billing period:

```swift
// Stripe integration fields
var stripeCustomerId: String?
var stripeSubscriptionId: String?
var subscriptionStatus: SubscriptionStatus?
var currentPeriodStart: Date? // ✅ NEW - When current billing period started
var nextBillingDate: Date? // When current billing period ends / next billing
```

### 2. UI Update (`UserSettingsView.swift`)

**Updated `formattedPeriodStart()`** - Now uses actual billing period start:

```swift
private func formattedPeriodStart(for account: UserAccount) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, yyyy"
    
    // ✅ Use actual billing period start from Stripe if available
    if let periodStart = account.currentPeriodStart {
        return formatter.string(from: periodStart)
    }
    
    // Fallback to calendar month start for legacy users
    // ... existing calendar logic
}
```

**Updated `renewalDateText()`** - Now uses actual Stripe billing date:

```swift
private func renewalDateText(for account: UserAccount) -> String {
    let calendar = Calendar.current
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    
    // Free trial users
    if account.plan == .free, let expiresAt = account.planExpiresAt {
        // ... trial expiration logic
    }
    
    // ✅ Use actual Stripe billing date for paid plans
    if let nextBilling = account.nextBillingDate {
        let daysRemaining = calendar.dateComponents([.day], from: Date(), to: nextBilling).day ?? 0
        return "Credits renew in \(daysRemaining) days (\(formatter.string(from: nextBilling)))"
    }
    
    // Fallback to calendar month calculation (legacy)
    // ... existing calendar logic
}
```

### 3. Firebase Functions Update (`functions/src/index.ts`)

**Webhook handler** - Now syncs `currentPeriodStart` on subscription changes:

```typescript
// Calculate billing period dates
const currentPeriodStart = subscription.current_period_start
  ? admin.firestore.Timestamp.fromMillis(subscription.current_period_start * 1000)
  : null;
const nextBillingDate = subscription.current_period_end 
  ? admin.firestore.Timestamp.fromMillis(subscription.current_period_end * 1000)
  : null;

// Update user account
await userDoc.ref.update({
  plan: plan,
  credits: credits,
  stripeSubscriptionId: subscription.id,
  subscriptionStatus: status,
  currentPeriodStart: currentPeriodStart, // ✅ NEW
  nextBillingDate: nextBillingDate,
  // ...
});
```

**Daily maintenance sync** - Also syncs `currentPeriodStart`:

```typescript
update.currentPeriodStart = currentPeriodStart; // ✅ NEW
update.nextBillingDate = nextBilling;
```

**Cancellation handler** - Clears both date fields:

```typescript
await userDoc.ref.update({
  plan: 'free',
  stripeSubscriptionId: null,
  subscriptionStatus: 'canceled',
  currentPeriodStart: null, // ✅ NEW
  nextBillingDate: null,
});
```

## How It Works Now

### Stripe Webhook Flow

1. **User subscribes on Oct 15, 2025**
2. Stripe sends webhook with:
   - `current_period_start`: Oct 15, 2025 00:00:00
   - `current_period_end`: Nov 15, 2025 00:00:00
3. Firebase Function saves both to Firestore
4. App displays:
   - "Usage since Oct 15, 2025" ✅
   - "Credits renew in X days (Nov 15, 2025)" ✅

### Monthly Renewal Flow

1. **Subscription renews on Nov 15, 2025**
2. Stripe sends webhook with new period:
   - `current_period_start`: Nov 15, 2025 00:00:00
   - `current_period_end`: Dec 15, 2025 00:00:00
3. Firebase Function updates Firestore
4. App displays updated dates ✅

### Legacy Support

If `currentPeriodStart` or `nextBillingDate` are null (old users, free plan), the app falls back to calendar month calculations. This ensures backward compatibility.

## Deployment Steps

### 1. Deploy Firebase Functions First

```bash
cd functions
npm install
firebase deploy --only functions
```

This updates the webhook and daily sync to populate the new fields.

### 2. Deploy App Update

Build and release the macOS app with the updated `UserAccount` model and `UserSettingsView`.

### 3. Existing Users

For users with active subscriptions:
- **Automatic**: Next webhook event will populate the fields
- **Manual**: Run the daily maintenance function to sync immediately:
  ```bash
  curl -X POST https://YOUR-PROJECT.cloudfunctions.net/syncStripeForUser \
    -H "Content-Type: application/json" \
    -d '{"userId": "USER_ID_HERE"}'
  ```

## Testing

### Test New Subscription

1. Create new Stripe subscription
2. Check Firestore `users/{userId}`:
   ```json
   {
     "currentPeriodStart": "2025-10-23T00:00:00Z",
     "nextBillingDate": "2025-11-23T00:00:00Z"
   }
   ```
3. Open app → Settings → Credits section
4. Should show: "Usage since Oct 23, 2025" and "Credits renew in X days (Nov 23, 2025)"

### Test Renewal

1. Wait for or trigger Stripe subscription renewal
2. Webhook should update both date fields
3. App should reflect new billing period

### Test Cancellation

1. Cancel subscription in Stripe
2. Both date fields should be cleared in Firestore
3. App should fall back to calendar month display or show trial info

## Files Changed

### Swift (App)
- `JamAI/Models/UserAccount.swift` - Added `currentPeriodStart` field
- `JamAI/Views/UserSettingsView.swift` - Updated date display functions
- `JamAI/Views/NodeView.swift` - Fixed PRO SEARCH button styling (separate fix)

### TypeScript (Functions)
- `functions/src/index.ts` - Updated webhook and sync handlers

### Documentation
- `STRIPE_BILLING_DATES_FIX.md` - This file

## Benefits

1. **Accurate dates**: Shows actual Stripe billing cycle, not calendar months
2. **Correct renewals**: Users see when their subscription actually renews
3. **Proper tracking**: "Usage since" matches when they subscribed
4. **Backward compatible**: Falls back to calendar months for legacy data
5. **Stripe as source of truth**: Always synced with actual billing

## Example Scenarios

### Scenario 1: Mid-Month Subscription
- Subscribed: Oct 15, 2025
- Before fix: "Usage since Oct 1" / "Renews Nov 1"
- After fix: "Usage since Oct 15" / "Renews Nov 15" ✅

### Scenario 2: End-of-Month Subscription
- Subscribed: Oct 30, 2025
- Before fix: "Usage since Oct 1" / "Renews Nov 1" (2 days!)
- After fix: "Usage since Oct 30" / "Renews Nov 30" (30 days) ✅

### Scenario 3: Legacy Free User
- No Stripe subscription
- Both fields null
- Falls back to calendar month (Oct 1 → Nov 1)
- No breaking change ✅

## Important Notes

- The `currentPeriodStart` and `nextBillingDate` are **Stripe timestamps** converted to Firestore timestamps
- Dates are in UTC timezone from Stripe
- Firebase Functions must be deployed **before** the app update for new subscriptions
- Existing subscriptions will sync on next webhook event or manual sync
