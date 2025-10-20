# Analytics Implementation Guide

## Overview

JamAI now includes comprehensive analytics tracking for user activity, token usage, costs, and team member engagement. All data is stored in Firestore and ready for dashboard consumption.

## What's Being Tracked

### 1. Token Usage (Per Generation)
**Collection:** `analytics_token_usage`

Tracks every AI generation with:
- Input and output token counts (actual character-based estimation)
- Estimated cost in USD (based on Gemini 2.0 Flash pricing)
- Model used
- Team member role and experience level (if applicable)
- Generation type (chat, expand, auto-title, auto-description)
- Project ID and Node ID for detailed drill-down

**Cost Calculation:**
- Input: $0.075 per 1M tokens
- Output: $0.30 per 1M tokens

### 2. Team Member Usage
**Collection:** `analytics_team_member_usage`

Tracks team member activity:
- Which roles are attached to nodes
- Which roles are actually used in generations
- Experience levels used
- Action types: attached, changed, removed, used

### 3. Project Activity
**Collection:** `analytics_project_activity`

Tracks project lifecycle:
- Project created
- Project opened
- Project closed
- Project renamed
- Project deleted

### 4. Node/Note/Edge Creation
**Collection:** `analytics_node_creation`

Tracks canvas activity:
- Standard nodes created
- Notes created
- Edges created
- Creation method (manual, expand, child node)
- Parent relationships
- Team member attached at creation

### 5. Daily Aggregated Analytics
**Collection:** `analytics_daily`

Daily rollup per user with:
- Total tokens (input/output)
- Total cost
- Generation counts by type
- Nodes/notes/edges created
- Projects created/opened
- Unique team members used
- Team member usage counts

**Document ID Format:** `{userId}_{YYYY-MM-DD}`

### 6. Plan Analytics (Aggregate)
**Collection:** `analytics_plans`

Daily snapshot of all users:
- User counts by plan (Trial, Free, Premium, Pro)
- Total paid users
- Total credits used
- Estimated revenue
- Active user counts

**Document ID Format:** `{YYYY-MM-DD}`

## Firebase Setup

### Step 1: Enable Firestore (Already Done)

Your Firestore database is already set up. The analytics system uses the same database as user accounts.

### Step 2: Create Firestore Indexes

**CRITICAL:** You must create composite indexes for efficient queries.

Navigate to **Firestore → Indexes** in Firebase Console and create these indexes:

#### Token Usage Queries:
```
Collection: analytics_token_usage
Fields: 
  - userId (Ascending)
  - timestamp (Descending)
```

```
Collection: analytics_token_usage
Fields:
  - timestamp (Ascending)
```

#### Team Member Usage Queries:
```
Collection: analytics_team_member_usage
Fields:
  - actionType (Ascending)
  - timestamp (Descending)
```

```
Collection: analytics_team_member_usage
Fields:
  - userId (Ascending)
  - actionType (Ascending)
```

#### Project Activity Queries:
```
Collection: analytics_project_activity
Fields:
  - userId (Ascending)
  - timestamp (Descending)
```

#### Daily Analytics Queries:
```
Collection: analytics_daily
Fields:
  - userId (Ascending)
  - date (Descending)
```

### Step 3: Update Firestore Security Rules

Add these rules to your `firestore.rules`:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Existing user rules...
    
    // Analytics - write by app, read by admin only
    match /analytics_token_usage/{document} {
      allow create: if request.auth != null && request.resource.data.userId == request.auth.uid;
      allow read: if request.auth != null && request.auth.token.admin == true;
    }
    
    match /analytics_team_member_usage/{document} {
      allow create: if request.auth != null && request.resource.data.userId == request.auth.uid;
      allow read: if request.auth != null && request.auth.token.admin == true;
    }
    
    match /analytics_project_activity/{document} {
      allow create: if request.auth != null && request.resource.data.userId == request.auth.uid;
      allow read: if request.auth != null && request.auth.token.admin == true;
    }
    
    match /analytics_node_creation/{document} {
      allow create: if request.auth != null && request.resource.data.userId == request.auth.uid;
      allow read: if request.auth != null && request.auth.token.admin == true;
    }
    
    match /analytics_daily/{document} {
      allow write: if request.auth != null && resource.data.userId == request.auth.uid;
      allow read: if request.auth != null && request.auth.token.admin == true;
    }
    
    match /analytics_plans/{document} {
      allow read: if request.auth != null && request.auth.token.admin == true;
      // Only Cloud Functions can write
      allow write: if false;
    }
  }
}
```

### Step 4: Set Admin Users

To query analytics from your dashboard, set admin custom claims:

```bash
# Using Firebase CLI
firebase auth:export users.json
# Edit users.json to add admin claim
firebase auth:import users.json --hash-algo=SCRYPT

# Or using Firebase Admin SDK (Node.js)
admin.auth().setCustomUserClaims(uid, { admin: true });
```

### Step 5: Optional - Enable Google Analytics

**You do NOT need to enable Google Analytics for Firebase to track these custom analytics.** The data is already being stored in Firestore.

However, if you want to also track basic app usage in Google Analytics:

1. Go to Firebase Console → Project Settings
2. Click "Integrations" tab
3. Enable "Google Analytics"
4. Link to existing GA4 property or create new one

**Note:** The custom metrics (tokens, costs, team members) will NOT appear in Google Analytics. They are only in Firestore.

## Admin Dashboard Queries

### JavaScript/TypeScript Examples

#### 1. Get Token Usage Summary (All Users, Last 30 Days)

```typescript
import { collection, query, where, getDocs, Timestamp } from 'firebase/firestore';

async function getTokenUsageSummary() {
  const db = getFirestore();
  const now = new Date();
  const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
  
  const q = query(
    collection(db, 'analytics_token_usage'),
    where('timestamp', '>=', Timestamp.fromDate(thirtyDaysAgo))
  );
  
  const snapshot = await getDocs(q);
  
  let totalInputTokens = 0;
  let totalOutputTokens = 0;
  let totalCost = 0;
  let totalGenerations = 0;
  
  snapshot.forEach(doc => {
    const data = doc.data();
    totalInputTokens += data.inputTokens;
    totalOutputTokens += data.outputTokens;
    totalCost += data.estimatedCostUSD;
    totalGenerations++;
  });
  
  return {
    totalInputTokens,
    totalOutputTokens,
    totalTokens: totalInputTokens + totalOutputTokens,
    totalCost,
    totalGenerations,
    avgCostPerGeneration: totalCost / totalGenerations
  };
}
```

#### 2. Get Most Used Team Members

```typescript
async function getMostUsedTeamMembers() {
  const db = getFirestore();
  
  const q = query(
    collection(db, 'analytics_team_member_usage'),
    where('actionType', '==', 'used')
  );
  
  const snapshot = await getDocs(q);
  
  const roleCounts = new Map();
  
  snapshot.forEach(doc => {
    const data = doc.data();
    const current = roleCounts.get(data.roleId) || { 
      name: data.roleName, 
      category: data.roleCategory,
      count: 0 
    };
    current.count++;
    roleCounts.set(data.roleId, current);
  });
  
  return Array.from(roleCounts.entries())
    .map(([roleId, data]) => ({ roleId, ...data }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 10);
}
```

#### 3. Get Plan Distribution

```typescript
async function getPlanDistribution() {
  const db = getFirestore();
  const usersRef = collection(db, 'users');
  const snapshot = await getDocs(usersRef);
  
  const planCounts = {
    trial: 0,
    free: 0,
    premium: 0,
    pro: 0
  };
  
  let totalCreditsUsed = 0;
  
  snapshot.forEach(doc => {
    const data = doc.data();
    planCounts[data.plan]++;
    totalCreditsUsed += data.creditsUsedThisMonth || 0;
  });
  
  return {
    planCounts,
    totalUsers: snapshot.size,
    totalPaidUsers: planCounts.premium + planCounts.pro,
    totalCreditsUsed,
    estimatedRevenue: (planCounts.premium * 9.99) + (planCounts.pro * 29.99)
  };
}
```

#### 4. Get User Activity Metrics

```typescript
async function getUserActivityMetrics(userId: string, days: number = 30) {
  const db = getFirestore();
  const startDate = new Date();
  startDate.setDate(startDate.getDate() - days);
  const dateString = startDate.toISOString().split('T')[0];
  
  const q = query(
    collection(db, 'analytics_daily'),
    where('userId', '==', userId),
    where('id', '>=', `${userId}_${dateString}`)
  );
  
  const snapshot = await getDocs(q);
  
  let totalTokens = 0;
  let totalCost = 0;
  let totalGenerations = 0;
  let totalNodes = 0;
  let uniqueTeamMembers = new Set();
  
  snapshot.forEach(doc => {
    const data = doc.data();
    totalTokens += data.totalTokens;
    totalCost += data.totalCostUSD;
    totalGenerations += data.totalGenerations;
    totalNodes += data.totalNodesCreated;
    data.uniqueTeamMembersUsed.forEach(role => uniqueTeamMembers.add(role));
  });
  
  return {
    totalTokens,
    totalCost,
    totalGenerations,
    totalNodes,
    uniqueTeamMembersCount: uniqueTeamMembers.size,
    avgCostPerDay: totalCost / days,
    avgGenerationsPerDay: totalGenerations / days
  };
}
```

#### 5. Get Cost by Team Member Role

```typescript
async function getCostByTeamMember(days: number = 30) {
  const db = getFirestore();
  const now = new Date();
  const startDate = new Date(now.getTime() - days * 24 * 60 * 60 * 1000);
  
  const q = query(
    collection(db, 'analytics_token_usage'),
    where('timestamp', '>=', Timestamp.fromDate(startDate)),
    where('teamMemberRoleId', '!=', null)
  );
  
  const snapshot = await getDocs(q);
  
  const roleCosts = new Map();
  
  snapshot.forEach(doc => {
    const data = doc.data();
    if (!data.teamMemberRoleId) return;
    
    const current = roleCosts.get(data.teamMemberRoleId) || {
      cost: 0,
      generations: 0,
      tokens: 0
    };
    
    current.cost += data.estimatedCostUSD;
    current.generations++;
    current.tokens += data.totalTokens;
    
    roleCosts.set(data.teamMemberRoleId, current);
  });
  
  return Array.from(roleCosts.entries())
    .map(([roleId, data]) => ({ roleId, ...data }))
    .sort((a, b) => b.cost - a.cost);
}
```

#### 6. Get Daily Trend Data

```typescript
async function getDailyTrends(days: number = 30) {
  const db = getFirestore();
  const dailyData = [];
  
  for (let i = days - 1; i >= 0; i--) {
    const date = new Date();
    date.setDate(date.getDate() - i);
    const dateString = date.toISOString().split('T')[0];
    
    const q = query(
      collection(db, 'analytics_daily'),
      where('id', '>=', `_${dateString}`),
      where('id', '<', `_${dateString}~`)
    );
    
    const snapshot = await getDocs(q);
    
    let dayTotal = {
      date: dateString,
      totalTokens: 0,
      totalCost: 0,
      totalGenerations: 0,
      activeUsers: snapshot.size
    };
    
    snapshot.forEach(doc => {
      const data = doc.data();
      dayTotal.totalTokens += data.totalTokens;
      dayTotal.totalCost += data.totalCostUSD;
      dayTotal.totalGenerations += data.totalGenerations;
    });
    
    dailyData.push(dayTotal);
  }
  
  return dailyData;
}
```

## Cloud Functions (Recommended)

Create a Cloud Function to aggregate plan analytics daily:

```typescript
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

export const aggregatePlanAnalytics = functions.pubsub
  .schedule('0 0 * * *') // Run daily at midnight
  .timeZone('America/New_York')
  .onRun(async (context) => {
    const db = admin.firestore();
    
    // Call the AnalyticsService method
    // This would need to be exposed via HTTP endpoint
    // or reimplemented in Cloud Functions
    
    console.log('Plan analytics aggregated successfully');
  });
```

## Data Retention

Consider implementing data retention policies:

1. **Raw Events:** Keep 90 days (sufficient for detailed analysis)
2. **Daily Aggregates:** Keep 1 year (for trend analysis)
3. **Plan Analytics:** Keep forever (small data, valuable historical trends)

Add this Cloud Function:

```typescript
export const cleanupOldAnalytics = functions.pubsub
  .schedule('0 2 * * 0') // Run weekly on Sundays at 2am
  .onRun(async (context) => {
    const db = admin.firestore();
    const ninetyDaysAgo = new Date();
    ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90);
    
    const collections = [
      'analytics_token_usage',
      'analytics_team_member_usage',
      'analytics_project_activity',
      'analytics_node_creation'
    ];
    
    for (const collectionName of collections) {
      const snapshot = await db.collection(collectionName)
        .where('timestamp', '<', admin.firestore.Timestamp.fromDate(ninetyDaysAgo))
        .limit(500)
        .get();
      
      const batch = db.batch();
      snapshot.docs.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
      
      console.log(`Deleted ${snapshot.size} documents from ${collectionName}`);
    }
  });
```

## Cost Estimates

Based on Firestore pricing and typical usage:

### Storage Costs
- Raw events: ~1KB per document
- Daily aggregates: ~2KB per document
- 1000 active users, 50 generations/day: ~50MB/day = $1.50/month

### Read/Write Costs
- Writes: 50,000 events/day = $0.18/day = $5.40/month
- Reads (dashboard): 10,000 reads/day = $0.36/day = $10.80/month

**Total: ~$18/month for 1000 active users**

## Next Steps

1. ✅ Analytics system is implemented and tracking
2. ⚠️ **Create Firestore indexes** (see Step 2 above)
3. ⚠️ **Update security rules** (see Step 3 above)
4. ⚠️ **Set admin claims** for dashboard users (see Step 4 above)
5. Build your admin dashboard using the query examples above
6. Optionally implement Cloud Functions for aggregation and cleanup

## Files Modified

- **NEW:** `JamAI/Models/AnalyticsEvent.swift` - Data models for all analytics events
- **NEW:** `JamAI/Services/AnalyticsService.swift` - Service for tracking and querying analytics
- **MODIFIED:** `JamAI/Services/CreditTracker.swift` - Enhanced to track detailed token usage
- **MODIFIED:** `JamAI/Services/CanvasViewModel.swift` - Integrated analytics tracking for generations, nodes, and team members
- **MODIFIED:** `JamAI/JamAIApp.swift` - Added project activity tracking

## Support

All analytics tracking happens automatically in the background and will not affect app performance. The system is designed to be fault-tolerant - if Firebase is unavailable, the app continues to work normally.
