---
name: brain-backup
description: >
  Back up and restore AI agent memory to S3-compatible storage.
  Use when: checking backup status, taking a manual snapshot,
  restoring from a previous snapshot, or listing snapshot history.
  Requires: brain-backup CLI installed and configured.
license: MIT
compatibility: Requires brain-backup CLI (shell), restic, macOS or Linux.
metadata:
  author: philipbankier
  version: "0.1"
---

# brain-backup

## Available Actions

### Check status
Run: `brain-backup status --json`
Returns: last backup time, repo health, total snapshots, stored size.

### Take a snapshot now
Run: `brain-backup snapshot --json`
Returns: snapshot ID, files new/changed, bytes added.
Only run when user asks. Scheduled backups handle this automatically.

### List snapshots
Run: `brain-backup list --latest 5 --json`
Returns: array of recent snapshots with IDs, timestamps, sizes.

### Restore (REQUIRES USER CONFIRMATION)
1. Show available snapshots: `brain-backup list --latest 10`
2. Ask user which snapshot to restore
3. ALWAYS restore to a temp directory: `brain-backup restore <ID> --target ~/brain-backup-restore`
4. Tell user where files are. Let THEM decide what to copy back.
5. NEVER run restore without user confirmation.
6. NEVER overwrite live agent directories automatically.

## When NOT to use this skill
- Don't run snapshot during time-sensitive operations
- Don't restore without explicit user request
- Don't modify the config file
- Don't change the schedule
