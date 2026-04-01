---
description: Show the current feature checklist — read-only view with status summary and progress
---

# Flywheel: Feature List

You are displaying the feature checklist. This is read-only — no modifications.

## Steps

1. Read `.flywheel/feature-checklist.json`.
2. If the file doesn't exist, say: "No feature checklist found. Run `/flywheel:init` first."
3. Display the checklist as a formatted table:

```
FEATURE CHECKLIST
┌───────────┬────────────────────────────────┬──────────┬───────────┐
│ ID        │ Title                          │ Priority │ Status    │
├───────────┼────────────────────────────────┼──────────┼───────────┤
│ feat-001  │ User authentication            │ 1        │ ✅ done   │
│ feat-002  │ User profile settings          │ 2        │ 🔄 next   │
│ feat-003  │ Request logging middleware     │ 3        │ ⏳ pending │
│ feat-004  │ Rate limiting                  │ 4        │ 🚫 blocked│
│ feat-005  │ Error handling                 │ 5        │ ✂️ split   │
└───────────┴────────────────────────────────┴──────────┴───────────┘

Progress: 1/5 completed | Next up: feat-002 — User profile settings
```

### Status icons

| Status | Icon | Meaning |
|---|---|---|
| `completed` | ✅ done | Implemented and merged |
| `pending` (lowest priority#) | 🔄 next | Will be picked by next `/flywheel:relay` |
| `pending` | ⏳ pending | Waiting in queue |
| `in-progress` | 🏗️ active | Currently being worked on |
| `blocked` | 🚫 blocked | Show `blocked_reason` inline if present |
| `split` | ✂️ split | Show `split_into` IDs inline |

### Progress line

Show: `Progress: X/Y completed | Next up: feat-NNN — Title`

Where:
- X = count of `completed` features
- Y = total features (excluding `split` parents — they're replaced by children)
- "Next up" = highest priority `pending` feature (lowest priority number)
- If all done: `Progress: X/X completed | All features done! 🎉`
- If none pending (all blocked/split): `Progress: X/Y completed | ⚠️ No actionable features — unblock or add new ones`

## Rules

- **Read-only.** Do not modify any files.
- **No prompts.** Do not ask the user what to do next. Just show the table and stop.
- **Fast.** No Claude invocations, no git operations — just read and display.
