/**
 * JamAI Firebase Cloud Functions
 * Handles Stripe webhooks and scheduled tasks
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import Stripe from 'stripe';

// Initialize Firebase Admin
admin.initializeApp();
const db = admin.firestore();

// Initialize Stripe
const stripeSecretKey = functions.config().stripe?.secret_key;
const stripeWebhookSecret = functions.config().stripe?.webhook_secret;

if (!stripeSecretKey) {
  console.warn('⚠️  Stripe secret key not configured. Run: firebase functions:config:set stripe.secret_key="sk_..."');
}

const stripe = stripeSecretKey ? new Stripe(stripeSecretKey, {
  apiVersion: '2023-10-16',
}) : null;

// Plan mapping from Stripe Price IDs to JamAI plans
const STRIPE_PRICE_TO_PLAN: {[key: string]: string} = {
  'price_1SKfaPEVeQAdCfriBk3YNvSp': 'pro',        // Pro Monthly - $15
  'price_1SKfb9EVeQAdCfriqgQ8z0Kl': 'teams',      // Teams Monthly - $30
  'price_1SKlghEVeQAdCfriOsC3xS1b': 'enterprise', // Enterprise Monthly - $99
};

// Credit amounts per plan
const PLAN_CREDITS: {[key: string]: number} = {
  'trial': 100,
  'free': 100,
  'pro': 1000,
  'teams': 1500,
  'enterprise': 5000,
};

/**
 * Stripe Webhook Handler
 * Handles subscription lifecycle events
 */
export const stripeWebhook = functions.https.onRequest(async (req, res) => {
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

  // Calculate next billing date
  const nextBillingDate = subscription.current_period_end 
    ? admin.firestore.Timestamp.fromMillis(subscription.current_period_end * 1000)
    : null;

  // Update user account
  await userDoc.ref.update({
    plan: plan,
    credits: credits,
    creditsUsedThisMonth: 0,
    stripeSubscriptionId: subscription.id,
    subscriptionStatus: status,
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
  const userData = userDoc.data();

  // Reset monthly credits
  const credits = PLAN_CREDITS[userData.plan] || 100;

  await userDoc.ref.update({
    credits: credits,
    creditsUsedThisMonth: 0,
    subscriptionStatus: 'active',
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
    },
  });

  console.log(`✅ Refreshed ${credits} credits for user ${userId}`);
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
export const dailyMaintenance = functions.pubsub
  .schedule('0 0 * * *')
  .timeZone('UTC')
  .onRun(async (context) => {
    console.log('🔄 Starting daily maintenance...');

    const now = admin.firestore.Timestamp.now();
    const usersSnapshot = await db.collection('users').get();
    let expiredTrialCount = 0;

    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();

      // Check for expired trials
      if (userData.plan === 'trial' && userData.planExpiresAt) {
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
            description: 'Trial expired - downgraded to Free plan',
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });

          expiredTrialCount++;
        }
      }
    }

    console.log(`✅ Maintenance complete. Expired trials: ${expiredTrialCount}`);
    return null;
  });
