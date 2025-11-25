/**
 * JamAI Firebase Cloud Functions
 * Handles Stripe webhooks and scheduled tasks
 */

import { onRequest } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { setGlobalOptions } from 'firebase-functions/v2';
import { defineSecret } from 'firebase-functions/params';
import * as admin from 'firebase-admin';
import Stripe from 'stripe';

// Set the region for all functions
setGlobalOptions({ region: 'europe-west1' });

// Initialize Firebase Admin
admin.initializeApp();
const db = admin.firestore();

// Get Stripe keys from environment variables or Firebase config
const stripeSecretKey = process.env.STRIPE_SECRET_KEY || '';

// Stripe webhook secret is stored in Firebase Secret Manager
const stripeWebhookSecretParam = defineSecret('STRIPE_WEBHOOK_SECRET');

// Initialize Stripe
const stripe = stripeSecretKey ? new Stripe(stripeSecretKey, {
  apiVersion: '2023-10-16',
}) : null;

// Optional env-driven price IDs (supports test/live without code edits)
const ENV_PRICE_PRO = process.env.STRIPE_PRICE_PRO || '';
const ENV_PRICE_TEAMS = process.env.STRIPE_PRICE_TEAMS || '';
const ENV_PRICE_ENTERPRISE = process.env.STRIPE_PRICE_ENTERPRISE || '';

// Plan mapping from Stripe Price IDs to JamAI plans
const STRIPE_PRICE_TO_PLAN: {[key: string]: string} = {
  'price_1SKfaPEVeQAdCfriBk3YNvSp': 'pro',        // Pro Monthly - $15 (example)
  'price_1SKfb9EVeQAdCfriqgQ8z0Kl': 'teams',      // Teams Monthly - $30 (example)
  'price_1SKlghEVeQAdCfriOsC3xS1b': 'enterprise', // Enterprise Monthly - $99 (example)
};

// Gemini configuration (server-side secret)
const geminiApiKey = process.env.GEMINI_API_KEY || '';
const GEMINI_MODEL_ID = 'gemini-2.0-flash-exp';
const GEMINI_BASE_URL = 'https://generativelanguage.googleapis.com/v1beta';

function getPlanFromPrice(priceId?: string | null): string {
  if (!priceId) return 'free';
  if (STRIPE_PRICE_TO_PLAN[priceId]) return STRIPE_PRICE_TO_PLAN[priceId];
  if (ENV_PRICE_PRO && priceId === ENV_PRICE_PRO) return 'pro';
  if (ENV_PRICE_TEAMS && priceId === ENV_PRICE_TEAMS) return 'teams';
  if (ENV_PRICE_ENTERPRISE && priceId === ENV_PRICE_ENTERPRISE) return 'enterprise';
  return 'free';
}

// Credit amounts per plan
const PLAN_CREDITS: {[key: string]: number} = {
  'trial': 100,
  'free': 100,
  'pro': 1000,
  'teams': 1500,
  'enterprise': 5000,
};

// Helper: allow simple CORS for browser calls (website /account)

// Helper: verify Firebase ID token from Authorization: Bearer <token>
async function verifyFirebaseAuth(req: any): Promise<{ uid: string; email?: string }> {
  const authHeader = (req.headers['authorization'] || req.headers['Authorization']) as string | undefined;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new Error('Missing Authorization Bearer token');
  }
  const idToken = authHeader.substring('Bearer '.length);
  const decoded = await admin.auth().verifyIdToken(idToken);
  return { uid: decoded.uid, email: decoded.email };
}

// Helper: map Stripe subscription status to app values
function mapSubscriptionStatus(status: Stripe.Subscription.Status): string {
  switch (status) {
    case 'active': return 'active';
    case 'trialing': return 'trialing';
    case 'past_due': return 'past_due';
    case 'canceled': return 'canceled';
    case 'unpaid': return 'unpaid';
    case 'incomplete': return 'incomplete';
    case 'incomplete_expired': return 'incomplete_expired';
    case 'paused': return 'paused'; // not standard in all accounts, keep for compatibility
    default: return 'active';
  }
}

/**
 * Stripe Webhook Handler
 * Handles subscription lifecycle events
 */
export const stripeWebhook = onRequest({ secrets: [stripeWebhookSecretParam] }, async (req, res) => {
  const stripeWebhookSecret = stripeWebhookSecretParam.value();

  if (!stripe || !stripeWebhookSecret) {
    console.error('❌ Stripe not configured');
    res.status(500).send('Stripe not configured');
    return;
  }

  const sig = req.headers['stripe-signature'];
  
  if (!sig) {
    console.error('❌ Missing stripe-signature header');
    res.status(400).send('Missing signature');
    return;
  }

  let event: Stripe.Event;

  try {
    console.log('🔍 Stripe webhook diagnostics', {
      hasRawBody: !!req.rawBody,
      rawBodyType: req.rawBody ? typeof req.rawBody : null,
      rawBodyLength: req.rawBody ? req.rawBody.length : null,
      hasSignatureHeader: !!sig,
      secretLength: stripeWebhookSecret.length,
    });
    // Verify webhook signature
    event = stripe.webhooks.constructEvent(req.rawBody, sig, stripeWebhookSecret);
  } catch (err: any) {
    console.error(`❌ Webhook signature verification failed: ${err.message}`);
    res.status(400).send(`Webhook Error: ${err.message}`);
    return;
  }

  console.log(`✅ Received Stripe webhook: ${event.type}`);

  try {
    // Handle different event types
    switch (event.type) {
      case 'customer.subscription.created':
      case 'customer.subscription.updated':
        await handleSubscriptionUpdate(event.data.object as Stripe.Subscription);
        break;

      case 'customer.subscription.deleted':
        await handleSubscriptionDeleted(event.data.object as Stripe.Subscription);
        break;

      case 'invoice.payment_succeeded':
        await handlePaymentSucceeded(event.data.object as Stripe.Invoice);
        break;

      case 'invoice.payment_failed':
        await handlePaymentFailed(event.data.object as Stripe.Invoice);
        break;

      case 'customer.created':
        await handleCustomerCreated(event.data.object as Stripe.Customer);
        break;

      default:
        console.log(`ℹ️  Unhandled event type: ${event.type}`);
    }

    res.json({ received: true });
  } catch (error: any) {
    console.error(`❌ Error processing webhook: ${error.message}`);
    res.status(500).send('Webhook processing failed');
  }
});

/**
 * Handle subscription created/updated
 */
async function handleSubscriptionUpdate(subscription: Stripe.Subscription) {
  console.log(`📝 Processing subscription update: ${subscription.id}`);

  const customerId = subscription.customer as string;
  const status = subscription.status;
  const priceId = subscription.items.data[0]?.price.id;

  // Map price ID to plan
  const plan = STRIPE_PRICE_TO_PLAN[priceId] || 'free';
  const credits = PLAN_CREDITS[plan] || 100;

  // Find user by Stripe customer ID
  const usersSnapshot = await db.collection('users')
    .where('stripeCustomerId', '==', customerId)
    .limit(1)
    .get();

  if (usersSnapshot.empty) {
    console.error(`❌ No user found for Stripe customer: ${customerId}`);
    return;
  }

  const userDoc = usersSnapshot.docs[0];
  const userId = userDoc.id;

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
    creditsTotal: credits,
    // Don't reset creditsUsedThisMonth here - only reset on monthly billing (handlePaymentSucceeded)
    stripeSubscriptionId: subscription.id,
    subscriptionStatus: status,
    currentPeriodStart: currentPeriodStart,
    nextBillingDate: nextBillingDate,
    planExpiresAt: null, // Clear trial expiration
    lastLoginAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Log credit transaction
  await db.collection('credit_transactions').add({
    userId: userId,
    amount: credits,
    type: 'plan_upgrade',
    description: `Subscription ${status}: ${plan} plan`,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    metadata: {
      stripeSubscriptionId: subscription.id,
      stripePriceId: priceId,
      subscriptionStatus: status,
    },
  });

  console.log(`✅ Updated user ${userId} to ${plan} plan with ${credits} credits`);
}

/**
 * Handle subscription deleted/canceled
 */
async function handleSubscriptionDeleted(subscription: Stripe.Subscription) {
  console.log(`🗑️  Processing subscription cancellation: ${subscription.id}`);

  const customerId = subscription.customer as string;

  const usersSnapshot = await db.collection('users')
    .where('stripeCustomerId', '==', customerId)
    .limit(1)
    .get();

  if (usersSnapshot.empty) {
    console.error(`❌ No user found for Stripe customer: ${customerId}`);
    return;
  }

  const userDoc = usersSnapshot.docs[0];
  const userId = userDoc.id;

  // Downgrade to free plan
  await userDoc.ref.update({
    plan: 'free',
    credits: 100,
    creditsUsedThisMonth: 0,
    stripeSubscriptionId: null,
    subscriptionStatus: 'canceled',
    currentPeriodStart: null,
    nextBillingDate: null,
  });

  // Log transaction
  await db.collection('credit_transactions').add({
    userId: userId,
    amount: 100,
    type: 'plan_upgrade',
    description: 'Subscription canceled - downgraded to Free plan',
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    metadata: {
      stripeSubscriptionId: subscription.id,
      previousStatus: subscription.status,
    },
  });

  console.log(`✅ Downgraded user ${userId} to free plan`);
}

/**
 * Handle successful payment
 */
async function handlePaymentSucceeded(invoice: Stripe.Invoice) {
  console.log(`💳 Processing payment success: ${invoice.id}`);

  const customerId = invoice.customer as string;
  const subscriptionId = invoice.subscription as string;

  if (!subscriptionId) {
    console.log('ℹ️  Invoice not associated with subscription');
    return;
  }

  const usersSnapshot = await db.collection('users')
    .where('stripeCustomerId', '==', customerId)
    .limit(1)
    .get();

  if (usersSnapshot.empty) {
    console.error(`❌ No user found for Stripe customer: ${customerId}`);
    return;
  }

  const userDoc = usersSnapshot.docs[0];
  const userId = userDoc.id;

  // Fetch latest subscription state from Stripe so we stay perfectly in sync
  const subscription = await stripe!.subscriptions.retrieve(subscriptionId);

  const priceId = subscription.items.data[0]?.price?.id || null;
  const plan = getPlanFromPrice(priceId);
  const credits = PLAN_CREDITS[plan] || PLAN_CREDITS['free'];

  const currentPeriodStart = subscription.current_period_start
    ? admin.firestore.Timestamp.fromMillis(subscription.current_period_start * 1000)
    : null;
  const nextBillingDate = subscription.current_period_end
    ? admin.firestore.Timestamp.fromMillis(subscription.current_period_end * 1000)
    : null;

  // Reset monthly credits and align billing period fields with Stripe
  await userDoc.ref.update({
    plan: plan,
    credits: credits,
    creditsTotal: credits,
    creditsUsedThisMonth: 0,
    subscriptionStatus: 'active',
    currentPeriodStart: currentPeriodStart,
    nextBillingDate: nextBillingDate,
    lastCreditedPeriodStart: currentPeriodStart,
  });

  // Log credit refresh
  await db.collection('credit_transactions').add({
    userId: userId,
    amount: credits,
    type: 'monthly_grant',
    description: 'Monthly credit refresh - payment successful',
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    metadata: {
      stripeInvoiceId: invoice.id,
      amountPaid: invoice.amount_paid,
      stripeSubscriptionId: subscription.id,
      stripePriceId: priceId,
      plan,
    },
  });

  console.log(`✅ Refreshed ${credits} credits for user ${userId} (plan=${plan})`);
}

/**
 * Handle failed payment
 */
async function handlePaymentFailed(invoice: Stripe.Invoice) {
  console.log(`⚠️  Processing payment failure: ${invoice.id}`);

  const customerId = invoice.customer as string;

  const usersSnapshot = await db.collection('users')
    .where('stripeCustomerId', '==', customerId)
    .limit(1)
    .get();

  if (usersSnapshot.empty) {
    console.error(`❌ No user found for Stripe customer: ${customerId}`);
    return;
  }

  const userDoc = usersSnapshot.docs[0];

  // Update subscription status
  await userDoc.ref.update({
    subscriptionStatus: 'past_due',
  });

  console.log(`⚠️  Marked subscription as past_due for user ${userDoc.id}`);
  
  // TODO: Send email notification about failed payment
}

/**
 * Handle new customer created
 */
async function handleCustomerCreated(customer: Stripe.Customer) {
  console.log(`👤 New Stripe customer created: ${customer.id}`);
  
  // Find user by email and link Stripe customer
  if (customer.email) {
    const usersSnapshot = await db.collection('users')
      .where('email', '==', customer.email)
      .limit(1)
      .get();

    if (!usersSnapshot.empty) {
      const userDoc = usersSnapshot.docs[0];
      await userDoc.ref.update({
        stripeCustomerId: customer.id,
      });
      console.log(`✅ Linked customer ${customer.id} to user ${userDoc.id}`);
    }
  }
}

/**
 * Scheduled function to check for expired trials
 * Runs daily at midnight UTC
 * 
 * NOTE: Credit resets happen via invoice.payment_succeeded webhook
 * when Stripe charges the subscription renewal (respects individual billing cycles).
 * This function only handles trial expirations and cleanup tasks.
 */
export const dailyMaintenance = onSchedule({ schedule: '0 0 * * *', timeZone: 'UTC' }, async (context) => {
    console.log('🔄 Starting daily maintenance...');

    const now = admin.firestore.Timestamp.now();
    const usersSnapshot = await db.collection('users').get();
    let expiredTrialCount = 0;
    let totalProjectsCreated = 0;

    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();

      // Check for expired free trials
      if (userData.plan === 'free' && userData.planExpiresAt) {
        const expiresAt = userData.planExpiresAt;
        
        if (expiresAt.seconds < now.seconds) {
          // Trial expired - downgrade to free
          console.log(`⏰ Trial expired for user ${userDoc.id}`);
          
          await userDoc.ref.update({
            plan: 'free',
            credits: 100,
            creditsUsedThisMonth: 0,
            planExpiresAt: null,
          });

          // Log transaction
          await db.collection('credit_transactions').add({
            userId: userDoc.id,
            amount: 100,
            type: 'plan_upgrade',
            description: 'Free trial expired',
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });

          expiredTrialCount++;
        }
      }

      // Aggregate total projects created
      if (userData.metadata && userData.metadata.totalProjectsCreated) {
        totalProjectsCreated += userData.metadata.totalProjectsCreated;
      }
    }

    // Update global analytics document
    const analyticsRef = db.collection('analytics').doc('global_stats');
    await analyticsRef.set({ 
        totalProjectsCreated: totalProjectsCreated,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    console.log(`✅ Maintenance complete. Expired trials: ${expiredTrialCount}. Total projects: ${totalProjectsCreated}.`);
  });

// Export health check endpoint
export const syncStripeForUser = onRequest({ invoker: 'public' }, async (req, res) => {
  if (req.method !== 'POST') { res.status(405).send('Method Not Allowed'); return; }

  if (!stripe) {
    console.error('❌ Stripe not configured');
    res.status(500).json({ ok: false, error: 'Stripe not configured' });
    return;
  }

  try {
    const { uid, email: tokenEmail } = await verifyFirebaseAuth(req);
    const userRef = db.collection('users').doc(uid);
    const userSnap = await userRef.get();
    const userData = userSnap.exists ? userSnap.data() as any : {};
    const email = userData.email || tokenEmail || '';

    let customerId: string | undefined = userData.stripeCustomerId;
    if (!customerId) {
      let customer: Stripe.Customer | undefined;
      if (email) {
        const list = await stripe.customers.list({ email, limit: 1 });
        if (list.data.length > 0) customer = list.data[0] as Stripe.Customer;
      }
      if (!customer) {
        customer = await stripe.customers.create({ email: email || undefined });
      }
      customerId = customer.id;
      await userRef.set({ stripeCustomerId: customerId }, { merge: true });
    }

    const subs = await stripe.subscriptions.list({ customer: customerId!, status: 'all', limit: 5 });
    let sub: Stripe.Subscription | undefined = undefined;
    const preferredOrder: Array<Stripe.Subscription.Status> = ['active', 'trialing', 'past_due', 'unpaid', 'incomplete'];
    for (const st of preferredOrder) {
      sub = subs.data.find(s => s.status === st);
      if (sub) break;
    }
    if (!sub && subs.data.length > 0) {
      sub = subs.data.sort((a, b) => (b.created || 0) - (a.created || 0))[0];
    }

    let update: any = {};
    let resetApplied = false;

    if (sub) {
      const priceId = sub.items.data[0]?.price?.id || null;
      const plan = getPlanFromPrice(priceId);
      const credits = PLAN_CREDITS[plan] || PLAN_CREDITS['free'];
      const status = mapSubscriptionStatus(sub.status);
      const nextBilling = sub.current_period_end ? admin.firestore.Timestamp.fromMillis(sub.current_period_end * 1000) : null;
      const currentPeriodStart = sub.current_period_start ? admin.firestore.Timestamp.fromMillis(sub.current_period_start * 1000) : null;

      update.plan = plan;
      update.stripeSubscriptionId = sub.id;
      update.subscriptionStatus = status;
      update.currentPeriodStart = currentPeriodStart;
      update.nextBillingDate = nextBilling;

      const lastCredited = userData.lastCreditedPeriodStart as admin.firestore.Timestamp | undefined;
      if (currentPeriodStart && (!lastCredited || lastCredited.seconds !== currentPeriodStart.seconds)) {
        update.credits = credits;
        update.creditsUsedThisMonth = 0;
        update.lastCreditedPeriodStart = currentPeriodStart;
        resetApplied = true;

        await db.collection('credit_transactions').add({
          userId: uid,
          amount: credits,
          type: 'monthly_grant',
          description: 'Monthly credit refresh (Stripe renewal)',
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          metadata: { stripeSubscriptionId: sub.id, stripePriceId: priceId }
        });
      }
    } else {
      update.plan = 'free';
      update.subscriptionStatus = null;
      update.stripeSubscriptionId = null;
      update.currentPeriodStart = null;
      update.nextBillingDate = null;
    }

    await userRef.set(update, { merge: true });
    res.json({ ok: true, resetApplied, ...update });
    return;
  } catch (err: any) {
    console.error('❌ syncStripeForUser failed', err?.message || err);
    res.status(400).json({ ok: false, error: err?.message || 'Sync failed' });
    return;
  }
});

export const createCustomerPortalSession = onRequest({ invoker: 'public' }, async (req, res) => {
  if (req.method !== 'POST') { res.status(405).send('Method Not Allowed'); return; }

  if (!stripe) {
    console.error('❌ Stripe not configured');
    res.status(500).json({ ok: false, error: 'Stripe not configured' });
    return;
  }

  try {
    const { uid, email: tokenEmail } = await verifyFirebaseAuth(req);
    const userRef = db.collection('users').doc(uid);
    const userSnap = await userRef.get();
    const userData = userSnap.exists ? userSnap.data() as any : {};
    const email = userData.email || tokenEmail || undefined;

    let customerId: string | undefined = userData.stripeCustomerId;
    if (!customerId) {
      let customer: Stripe.Customer | undefined;
      if (email) {
        const list = await stripe.customers.list({ email, limit: 1 });
        if (list.data.length > 0) customer = list.data[0] as Stripe.Customer;
      }
      if (!customer) {
        customer = await stripe.customers.create({ email });
      }
      customerId = customer.id;
      await userRef.set({ stripeCustomerId: customerId }, { merge: true });
    }

    const returnUrl = (req.body && (req.body.returnUrl as string)) || 'http://localhost:3000/account';
    const session = await stripe.billingPortal.sessions.create({
      customer: customerId!,
      return_url: returnUrl,
    });

    res.json({ ok: true, url: session.url });
    return;
  } catch (err: any) {
    console.error('❌ createCustomerPortalSession failed', err?.message || err);
    res.status(400).json({ ok: false, error: err?.message || 'Portal creation failed' });
    return;
  }
});

/**
 * Gemini AI proxy
 * Authenticates via Firebase ID token, enforces basic credit limits,
 * calls Gemini generateContent with a server-side API key, and returns text.
 */
export const generateWithGemini = onRequest({ invoker: 'public' }, async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).send('Method Not Allowed');
    return;
  }

  if (!geminiApiKey) {
    console.error('❌ GEMINI_API_KEY not configured');
    res.status(500).json({ ok: false, error: 'Gemini not configured' });
    return;
  }

  try {
    // Authenticate user via Firebase ID token
    const { uid } = await verifyFirebaseAuth(req);

    const userRef = db.collection('users').doc(uid);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      console.error(`❌ No user document for uid=${uid}`);
      res.status(403).json({ ok: false, error: 'User account not found' });
      return;
    }

    const userData = userSnap.data() as any;

    // Basic account checks
    if (userData.isActive === false) {
      res.status(403).json({ ok: false, error: 'Account is inactive. Please contact support.' });
      return;
    }

    // Trial expiration check for free plan
    const plan = (userData.plan as string) || 'free';
    if (plan === 'free' && userData.planExpiresAt) {
      const expiresAt = userData.planExpiresAt as admin.firestore.Timestamp;
      const now = admin.firestore.Timestamp.now();
      if (expiresAt.seconds < now.seconds) {
        res.status(403).json({ ok: false, error: 'Your free trial has expired. Upgrade your plan to continue.' });
        return;
      }
    }

    const credits = typeof userData.credits === 'number' ? userData.credits : 0;
    const creditsUsedThisMonth = typeof userData.creditsUsedThisMonth === 'number' ? userData.creditsUsedThisMonth : 0;

    if (credits <= 0) {
      res.status(403).json({ ok: false, error: 'Out of credits. Upgrade your plan to continue.' });
      return;
    }

    // Expect a pre-built Gemini request body from the client
    const { body } = req.body || {};
    if (!body || typeof body !== 'object') {
      res.status(400).json({ ok: false, error: 'Missing or invalid Gemini request body' });
      return;
    }

    const url = `${GEMINI_BASE_URL}/models/${GEMINI_MODEL_ID}:generateContent?key=${geminiApiKey}`;

    const geminiResponse = await (globalThis as any).fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });

    const rawText = await geminiResponse.text();

    if (!geminiResponse.ok) {
      console.error('❌ Gemini API error', geminiResponse.status, rawText);
      res.status(geminiResponse.status).json({ ok: false, error: 'Gemini API error', details: rawText });
      return;
    }

    let json: any;
    try {
      json = JSON.parse(rawText);
    } catch (err: any) {
      console.error('❌ Failed to parse Gemini response JSON', err?.message || err);
      res.status(500).json({ ok: false, error: 'Invalid response from Gemini' });
      return;
    }

    const candidates = Array.isArray(json.candidates) ? json.candidates : [];
    const first = candidates[0];
    const content = first && first.content;
    const parts = content && Array.isArray(content.parts) ? content.parts : [];
    const firstPart = parts[0];
    const text = firstPart && typeof firstPart.text === 'string' ? firstPart.text : '';

    if (!text) {
      console.error('❌ Gemini response missing text field');
      res.status(500).json({ ok: false, error: 'Gemini response missing text content' });
      return;
    }

    // Deduct one credit per successful generation (simple, conservative model)
    const newCredits = Math.max(0, credits - 1);
    const newUsed = creditsUsedThisMonth + 1;

    await userRef.update({
      credits: newCredits,
      creditsUsedThisMonth: newUsed,
    });

    await db.collection('credit_transactions').add({
      userId: uid,
      amount: -1,
      type: 'ai_generation',
      description: 'Gemini chat generation',
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({ ok: true, text, creditsRemaining: newCredits });
  } catch (err: any) {
    console.error('❌ generateWithGemini failed', err?.message || err);
    res.status(500).json({ ok: false, error: err?.message || 'AI generation failed' });
  }
});

export { health as healthV2 } from './health';
export { migrateCreditsFields, migrateUserStats } from './migrate-credits';
