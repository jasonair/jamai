# JamAI Pricing Structure Update (2024)

## Updated Plans (Simplified - December 2024)

The JamAI pricing has been simplified to match the website. All plans now have:
- **Access to all Jam AI team members** (no limits)
- **All experience levels** (Junior, Intermediate, Senior, Expert)
- **Unlimited saved Jams**

The only difference between plans is the number of prompt credits.

### Free Plan
- **Price**: $0 per user/month
- **Credits**: 100 prompt credits/month
- **Features**:
  - 2-week Pro trial
  - Local model + Gemini 2.0
  - Access to all Jam AI team members

### Pro Plan (Popular)
- **Price**: $15 per user/month
- **Credits**: 1,000 prompt credits/month
- **Features**:
  - Everything in Free, plus:
  - 1,000 prompt credits/month

### Teams Plan
- **Price**: $30 per user/month
- **Credits**: 1,500 prompt credits per user/month
- **Features**:
  - Everything in Pro, plus:
  - 1,500 prompt credits/user/month

### Enterprise Plan
- **Price**: Let's talk (Custom pricing, starts ~$99/user/month)
- **Credits**: 5,000 prompt credits per user/month
- **Features**:
  - Everything in Teams, plus:
  - 5,000 prompt credits/user/month
  - Dedicated account manager

## Changes Implemented

### 1. UserAccount.swift (Models)
- Updated `UserPlan` enum with 4 tiers: free, pro, teams, enterprise
- Removed deprecated `premium` plan
- Added `monthlyPrice` property for pricing display
- Updated `monthlyCredits`: 100 (free), 1000 (pro), 1500 (teams), 5000 (enterprise)
- Added `maxTeamMembersPerJam`: 3 (free), 12 (pro), unlimited (teams/enterprise)
- Added `maxSavedJams`: 3 (free), unlimited (all paid plans)
- Added `hasUnlimitedTeamMembers` helper for unlimited plans
- Added `allowsSeniorAndExpert` for experience level gating
- Added comprehensive `features` array for each plan

### 2. NodeView.swift
- Updated team member limit check to use `maxTeamMembersPerJam`
- Added support for unlimited team members (Teams/Enterprise plans)
- Skip limit check when `hasUnlimitedTeamMembers` is true

### 3. TeamMemberModal.swift
- Updated plan tier mapping:
  - Free → free tier (with trial access to pro features for 14 days)
  - Pro → pro tier
  - Teams/Enterprise → enterprise tier

### 4. roles.json
- Added `requiredTier: "Pro"` to all Senior and Expert level prompts (274 updates)
- Junior and Intermediate levels remain free tier (default)
- Enforces Free plan restriction to Junior & Intermediate only

### 5. UserSettingsView.swift
- Enhanced PlanCard to display monthly price prominently
- Added pricing display with `$X / month` format
- Shows "Custom" for Enterprise pricing
- Updated plan colors: free (gray), pro (blue), teams (purple), enterprise (green)
- Added saved Jams limit display
- Shows "Unlimited" for unlimited team members

### 6. JamAIApp.swift
- Added saved Jams limit enforcement for Free plan
- Shows alert when Free users try to create 4th project
- Prompts to upgrade to Pro or delete old projects
- Links to UserSettings view for plan upgrade

## Sync Status

### ✅ App (macOS)
**Status**: FULLY UPDATED
- All plan tiers implemented
- Credit amounts match website
- Team member limits enforced
- Experience level gating working
- Saved Jams limit enforced for Free plan

### ⚠️ Stripe
**Status**: NOT YET INTEGRATED
- Stripe integration is planned (Phase 2)
- No Stripe code currently in the app
- Plans marked in documentation: `FIREBASE_IMPLEMENTATION.md`, `FIREBASE_SUMMARY.md`
- **Action Required**:
  1. Create Stripe account and configure products
  2. Set up 4 pricing plans in Stripe Dashboard:
     - Free: $0/month (or no Stripe product needed)
     - Pro: $15/month
     - Teams: $30/month
     - Enterprise: Custom (contact sales)
  3. Implement Stripe checkout flow
  4. Add webhook handlers for subscription changes
  5. Sync Stripe subscription status to Firebase user accounts

### ✅ Website
**Status**: ALREADY UPDATED (per screenshot)
- Displays correct pricing tiers
- Shows all 4 plans with features
- Monthly pricing displayed correctly
- **Note**: Website code is in separate repository

## Integration Checklist

To fully sync Stripe with the app and website:

- [ ] **Stripe Dashboard Setup**
  - [ ] Create Free product (or handle as non-paid tier)
  - [ ] Create Pro product: $15/month recurring
  - [ ] Create Teams product: $30/month recurring
  - [ ] Create Enterprise as custom contact option
  - [ ] Configure trial period: 14 days (Pro features)

- [ ] **App Integration** (Future Phase 2)
  - [ ] Add Stripe SDK to project
  - [ ] Implement checkout flow in UserSettingsView
  - [ ] Add "Upgrade" button for each plan tier
  - [ ] Handle subscription creation/update
  - [ ] Implement webhook receiver (Cloud Functions)
  - [ ] Sync subscription status to Firebase
  - [ ] Add billing history view
  - [ ] Implement subscription cancellation

- [ ] **Firebase Cloud Functions**
  - [ ] Create webhook endpoint for Stripe events
  - [ ] Handle `customer.subscription.created`
  - [ ] Handle `customer.subscription.updated`
  - [ ] Handle `customer.subscription.deleted`
  - [ ] Handle `invoice.payment_succeeded`
  - [ ] Handle `invoice.payment_failed`
  - [ ] Update user plan in Firestore on webhook
  - [ ] Grant/revoke credits based on subscription

- [ ] **Security & Validation**
  - [ ] Verify webhook signatures
  - [ ] Add Stripe customer ID to UserAccount model
  - [ ] Implement subscription status checks
  - [ ] Add grace period for failed payments
  - [ ] Prevent feature access after subscription cancellation

## Testing Checklist

- [x] Free plan: 3 team members max (Junior & Intermediate only)
- [x] Free plan: 3 saved Jams max (enforced with alert)
- [x] Pro plan: 12 team members per Jam (all experience levels)
- [x] Teams plan: Unlimited team members
- [x] Enterprise plan: Unlimited team members
- [x] Team member modal shows locked Senior/Expert for Free users
- [x] Plan cards display pricing correctly
- [x] Credits display correct monthly amounts
- [ ] Stripe checkout flow (pending implementation)
- [ ] Subscription webhook handling (pending implementation)
- [ ] Plan upgrade/downgrade flow (pending implementation)

## Database Migration

No database migration required. The app gracefully handles:
- Users on old "premium" plan (will default to "free" if not recognized)
- Missing `maxSavedJams` field (defaults via computed property)
- Missing `maxTeamMembersPerJam` field (defaults via computed property)

Existing user accounts will continue working. When they next open the app:
- New Free users: Start a 14-day trial of Pro features.
- Free users: New limits apply (3 team members, 3 saved Jams)
- Pro users: New benefits apply (12 team members, unlimited Jams)

## Recommendation

1. **Update Stripe Dashboard** with the 4 pricing plans matching the website
2. **Implement Phase 2 Stripe Integration** to enable actual payments
3. **Add webhook handlers** to sync subscription status with Firebase
4. **Test end-to-end flow**:
   - User signs up → Free plan with a 14-day trial of Pro features
   - Trial expires → Continue on Free plan with standard limitations
   - User upgrades to Pro via Stripe → Subscription active
   - Subscription renews → Credits reset monthly
   - Subscription cancelled → Downgrade to Free

## Files Modified

- `JamAI/Models/UserAccount.swift` - Updated plan structure
- `JamAI/Views/NodeView.swift` - Team member limit checks
- `JamAI/TeamMembers/Views/TeamMemberModal.swift` - Plan tier mapping
- `JamAI/TeamMembers/Resources/roles.json` - Experience level tier requirements
- `JamAI/Views/UserSettingsView.swift` - Pricing display
- `JamAI/JamAIApp.swift` - Saved Jams limit enforcement

## Documentation Created

- `PRICING_UPDATE_2024.md` (this file)
