#!/bin/bash

# JamAI Stripe Webhook Setup Script
# This script helps configure and deploy the Stripe webhook integration

set -e

echo "🔧 JamAI Stripe Webhook Setup"
echo "=============================="
echo ""

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found. Install it with:"
    echo "   npm install -g firebase-tools"
    exit 1
fi

# Check if logged in to Firebase
if ! firebase projects:list &> /dev/null; then
    echo "🔑 Logging in to Firebase..."
    firebase login
fi

echo "✅ Firebase CLI ready"
echo ""

# Check if in functions directory
if [ ! -f "package.json" ]; then
    echo "⚠️  Please run this script from the functions/ directory"
    exit 1
fi

# Install dependencies
echo "📦 Installing dependencies..."
npm install
echo "✅ Dependencies installed"
echo ""

# Prompt for Stripe keys
echo "🔑 Stripe Configuration"
echo "----------------------"
echo "Get your keys from: https://dashboard.stripe.com/apikeys"
echo ""

read -p "Enter your Stripe Secret Key (sk_test_... or sk_live_...): " STRIPE_KEY
read -p "Enter your Stripe Webhook Secret (whsec_... or skip for now): " WEBHOOK_SECRET

if [ -z "$STRIPE_KEY" ]; then
    echo "❌ Stripe secret key is required"
    exit 1
fi

# Set Firebase config
echo ""
echo "🔧 Configuring Firebase Functions..."
firebase functions:config:set "stripe.secret_key=$STRIPE_KEY"

if [ -n "$WEBHOOK_SECRET" ]; then
    firebase functions:config:set "stripe.webhook_secret=$WEBHOOK_SECRET"
    echo "✅ Webhook secret configured"
else
    echo "⚠️  Skipping webhook secret (you'll need to set this after creating the webhook endpoint)"
fi

echo ""
echo "📝 Next steps to configure Price IDs:"
echo "1. Edit src/index.ts"
echo "2. Find STRIPE_PRICE_TO_PLAN object"
echo "3. Replace placeholder Price IDs with your actual ones from Stripe Dashboard"
echo ""

read -p "Have you updated the Price IDs in src/index.ts? (y/n): " PRICE_IDS_UPDATED

if [ "$PRICE_IDS_UPDATED" != "y" ]; then
    echo ""
    echo "⚠️  Please update Price IDs before deploying"
    echo "   Open src/index.ts and update STRIPE_PRICE_TO_PLAN"
    echo "   Then run: firebase deploy --only functions"
    exit 0
fi

# Build TypeScript
echo ""
echo "🔨 Building functions..."
npm run build
echo "✅ Build complete"

# Deploy
echo ""
echo "🚀 Deploying to Firebase..."
firebase deploy --only functions

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📋 Next Steps:"
echo "1. Copy the webhook URL from the output above"
echo "2. Go to https://dashboard.stripe.com/webhooks"
echo "3. Create a new webhook endpoint with that URL"
echo "4. Select these events:"
echo "   - customer.subscription.created"
echo "   - customer.subscription.updated"  
echo "   - customer.subscription.deleted"
echo "   - invoice.payment_succeeded"
echo "   - invoice.payment_failed"
echo "   - customer.created"
echo "5. Copy the webhook signing secret (whsec_...)"
echo "6. Run: firebase functions:config:set stripe.webhook_secret='whsec_...'"
echo "7. Run: firebase deploy --only functions"
echo ""
echo "🎉 Setup complete! Test with a subscription in Stripe Dashboard."
