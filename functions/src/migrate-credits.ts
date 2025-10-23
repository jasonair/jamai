/**
 * Migration Script: Clean Up Legacy creditsUsed Field
 * 
 * This script:
 * 1. Removes the legacy 'creditsUsed' field from all user documents
 * 2. Ensures 'creditsUsedThisMonth' is correctly calculated
 * 
 * Run this once via Firebase Functions or Cloud Shell
 */

import * as admin from 'firebase-admin';
import { onRequest } from 'firebase-functions/v2/https';

/**
 * One-time migration script to backfill user metadata from analytics collections.
 * This should be run once to correct historical data.
 */
export const migrateUserStats = onRequest({ invoker: 'private' }, async (req, res) => {
  const db = admin.firestore();
  const usersRef = db.collection("users");
  const analyticsNodeRef = db.collection("analytics_node_creation");
  const analyticsTokenRef = db.collection("analytics_token_usage");
  const analyticsTeamRef = db.collection("analytics_team_member_usage");

  console.log("Starting user stats migration...");

  try {
    // 1. Aggregate analytics data
    const userStats: { [key: string]: any } = {};

    const nodeSnapshot = await analyticsNodeRef.get();
    nodeSnapshot.forEach(doc => {
      const data = doc.data();
      const userId = data.userId;
      if (!userStats[userId]) userStats[userId] = {};

      switch (data.creationMethod) {
        case 'manual':
          userStats[userId].totalNodesCreated = (userStats[userId].totalNodesCreated || 0) + 1;
          break;
        case 'note':
          userStats[userId].totalNotesCreated = (userStats[userId].totalNotesCreated || 0) + 1;
          break;
        case 'child_node':
        case 'expand':
          userStats[userId].totalChildNodesCreated = (userStats[userId].totalChildNodesCreated || 0) + 1;
          break;
      }
    });

    const tokenSnapshot = await analyticsTokenRef.get();
    tokenSnapshot.forEach(doc => {
      const data = doc.data();
      const userId = data.userId;
      if (!userStats[userId]) userStats[userId] = {};

      switch (data.generationType) {
        case 'chat':
          userStats[userId].totalMessagesGenerated = (userStats[userId].totalMessagesGenerated || 0) + 1;
          break;
        case 'expand':
          userStats[userId].totalExpandActions = (userStats[userId].totalExpandActions || 0) + 1;
          break;
      }
    });

    const teamSnapshot = await analyticsTeamRef.where('actionType', '==', 'attached').get();
    teamSnapshot.forEach(doc => {
      const data = doc.data();
      const userId = data.userId;
      if (!userStats[userId]) userStats[userId] = {};
      userStats[userId].totalTeamMembersUsed = (userStats[userId].totalTeamMembersUsed || 0) + 1;
    });

    // 2. Update user documents
    const batch = db.batch();
    let migratedCount = 0;

    for (const userId in userStats) {
      const userRef = usersRef.doc(userId);
      const stats = userStats[userId];
      const updateData: { [key: string]: any } = {};

      for (const field in stats) {
        updateData[`metadata.${field}`] = stats[field];
      }

      batch.update(userRef, updateData);
      migratedCount++;
    }

    await batch.commit();

    console.log('✅ User stats migration complete!');
    res.status(200).json({
      success: true,
      migratedUsers: migratedCount,
      message: 'User stats migration completed successfully'
    });

  } catch (error: any) {
    console.error('❌ User stats migration failed:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});


// Use the already-initialized admin instance
const db = admin.firestore();

export const migrateCreditsFields = onRequest({ invoker: 'private' }, async (req, res) => {
  console.log('🔄 Starting credits field migration...');
  
  try {
    const usersSnapshot = await db.collection('users').get();
    let migratedCount = 0;
    let errorCount = 0;
    
    const batch = db.batch();
    
    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const userId = userDoc.id;
      
      console.log(`Processing user ${userId}...`);
      
      // Prepare update object
      const updates: any = {};
      let needsUpdate = false;
      
      // 1. Remove legacy 'creditsUsed' field if it exists
      if ('creditsUsed' in userData) {
        updates['creditsUsed'] = admin.firestore.FieldValue.delete();
        needsUpdate = true;
        console.log(`  - Removing legacy creditsUsed field`);
      }
      
      // 2. Calculate correct creditsUsedThisMonth if needed
      const credits = userData.credits || 0;
      const creditsTotal = userData.creditsTotal || 0;
      const currentUsed = userData.creditsUsedThisMonth || 0;
      
      // Calculate what the usage SHOULD be
      const calculatedUsed = Math.max(0, creditsTotal - credits);
      
      // Only update if there's a mismatch
      if (calculatedUsed !== currentUsed) {
        updates['creditsUsedThisMonth'] = calculatedUsed;
        needsUpdate = true;
        console.log(`  - Correcting creditsUsedThisMonth: ${currentUsed} → ${calculatedUsed}`);
      }
      
      // Apply updates if needed
      if (needsUpdate) {
        batch.update(userDoc.ref, updates);
        migratedCount++;
      }
    }
    
    // Commit all updates
    await batch.commit();
    
    console.log('✅ Migration complete!');
    console.log(`   - Total users processed: ${usersSnapshot.size}`);
    console.log(`   - Users migrated: ${migratedCount}`);
    console.log(`   - Errors: ${errorCount}`);
    
    res.status(200).json({
      success: true,
      totalUsers: usersSnapshot.size,
      migrated: migratedCount,
      errors: errorCount,
      message: 'Migration completed successfully'
    });
    
  } catch (error: any) {
    console.error('❌ Migration failed:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});
