/**
 * Database Migration: Rename 'done' field to 'completed_at' in tasks collection
 *
 * This migration:
 * 1. Renames the 'done' field to 'completed_at' for all tasks that have it
 * 2. Removes the orphan 'completed_at: null' field from incomplete tasks
 *
 * Run with: mongosh lumie_db --file migrate_done_to_completed_at.js
 */

// Step 1: Rename 'done' → 'completed_at' where 'done' exists
print("[Step 1/2] Renaming 'done' field to 'completed_at' for completed tasks...");
const renameResult = db.tasks.updateMany(
  { done: { $exists: true } },
  [{ $set: { completed_at: "$done" } }, { $unset: "done" }]
);
print(`  Modified ${renameResult.modifiedCount} documents`);

// Step 2: Remove the orphan 'completed_at: null' field from incomplete tasks
print("[Step 2/2] Removing orphan 'completed_at: null' field from incomplete tasks...");
const cleanupResult = db.tasks.updateMany(
  { completed_at: null },
  { $unset: { completed_at: "" } }
);
print(`  Modified ${cleanupResult.modifiedCount} documents`);

print("\n✅ Migration complete!");
print(`Summary:`);
print(`  - Tasks with 'done' field renamed: ${renameResult.modifiedCount}`);
print(`  - Incomplete tasks cleaned up: ${cleanupResult.modifiedCount}`);
