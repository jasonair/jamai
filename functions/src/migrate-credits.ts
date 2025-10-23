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
