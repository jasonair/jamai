#!/bin/bash

# This script syncs your Stripe subscription data to Firebase
# It will populate the currentPeriodStart and nextBillingDate fields

echo "🔄 Syncing Stripe subscription data..."
echo ""
echo "First, we need your Firebase User ID."
echo "You can find it in the Firebase Console:"
echo "https://console.firebase.google.com/project/jamai-dev/authentication/users"
echo ""
read -p "Enter your Firebase User ID: " USER_ID

if [ -z "$USER_ID" ]; then
    echo "❌ Error: User ID is required"
    exit 1
fi

echo ""
echo "🚀 Calling sync function for user: $USER_ID"
echo ""

curl -X POST "https://syncstripeforuser-rlhocrenuq-ew.a.run.app" \
  -H "Content-Type: application/json" \
  -d "{\"userId\": \"$USER_ID\"}"

echo ""
echo ""
echo "✅ Sync complete!"
echo ""
echo "Now:"
echo "1. Restart your JamAI app"
echo "2. Open Account Settings"
echo "3. You should see the correct dates from Stripe"
