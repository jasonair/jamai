/**
 * LOCAL MIGRATION SCRIPT
 * 
 * To run this script:
 * 1. Make sure you are logged in: `gcloud auth application-default login`
 * 2. Run the script: `node run-local-migration.js`
 */

const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

// --- Configuration ---
const projectId = 'jamai-dev';
// ---------------------

async function main() {
  console.log(`🚀 Initializing connection to project: ${projectId}`);

  try {
    initializeApp({
      credential: applicationDefault(),
      projectId: projectId,
    });
  } catch (e) {
    console.error('❌ Initialization failed. Make sure you are authenticated.');
    console.error('Run `gcloud auth application-default login` in your terminal.');
    return;
  }

  const db = getFirestore();
  console.log('🔄 Starting credits field migration...');

  try {
    const usersSnapshot = await db.collection('users').get();
    let migratedCount = 0;
    const batch = db.batch();

    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const userId = userDoc.id;
      const updates = {};
      let needsUpdate = false;

      if ('creditsUsed' in userData) {
        updates['creditsUsed'] = require('firebase-admin/firestore').FieldValue.delete();
        needsUpdate = true;
        console.log(`  - User ${userId}: Removing legacy 'creditsUsed' field.`);
      }

      const credits = userData.credits || 0;
      const creditsTotal = userData.creditsTotal || 0;
      const currentUsed = userData.creditsUsedThisMonth || 0;
      const calculatedUsed = Math.max(0, creditsTotal - credits);

      if (calculatedUsed !== currentUsed) {
        updates['creditsUsedThisMonth'] = calculatedUsed;
        needsUpdate = true;
        console.log(`  - User ${userId}: Correcting 'creditsUsedThisMonth' from ${currentUsed} to ${calculatedUsed}.`);
      }

      if (needsUpdate) {
        batch.update(userDoc.ref, updates);
        migratedCount++;
      }
    }

    if (migratedCount > 0) {
      await batch.commit();
      console.log(`✅ Committed updates for ${migratedCount} users.`);
    } else {
      console.log('✅ No users needed migration.');
    }

    console.log('🎉 Migration complete!');
  } catch (error) {
    console.error('❌ Migration failed during database operation:', error);
  }
}

main();
