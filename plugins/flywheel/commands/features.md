---
description: Manage the feature checklist — add, revise, reprioritize, split, or remove features dynamically between relay sessions
---

# Flywheel: Feature Management

You are managing the feature checklist for a flywheel project. Features are dynamic — they can be added, revised, reprioritized, split, or removed at any time between relay sessions.

## Prerequisites

1. Read `.flywheel/feature-checklist.json` — this is the source of truth.
2. Read `.flywheel/flywheel-config.json` — for source metadata.
3. Read the last 10 entries from `.flywheel/claude-progress.jsonl` — to understand what's already been completed.

## Operations

Present the current checklist first, then ask the user what they want to do:

```
FEATURE CHECKLIST — [project name]
┌─────┬────────────────────────────────┬──────────┬──────────┐
│ ID  │ Title                          │ Priority │ Status   │
├─────┼────────────────────────────────┼──────────┼──────────┤
│ 001 │ User authentication            │ 1        │ completed│
│ 002 │ User profile settings          │ 2        │ pending  │
│ ... │ ...                            │ ...      │ ...      │
└─────┴────────────────────────────────┴──────────┴──────────┘

Operations:
  1) Add — add new feature(s)
  2) Revise — edit title, description, or acceptance criteria
  3) Reprioritize — change priority order
  4) Split — break a feature into sub-features
  5) Remove — delete a feature
  6) Unblock — clear blocked status
  7) Done — exit
```

### 1. Add Features

When the user wants to add features:

1. Accept features from any format — bullet points, paragraphs, pasted specs, or conversation.
2. For each new feature, generate:
   ```json
   {
     "id": "feat-NNN",
     "title": "Short descriptive title",
     "priority": <next available priority or user-specified>,
     "status": "pending",
     "acceptance_criteria": ["criterion 1", "criterion 2"],
     "dependencies": [],
     "completed_by_session": null
   }
   ```
3. Auto-increment the ID from the highest existing ID (e.g., if `feat-012` exists, next is `feat-013`).
4. Show the generated entries to the user for confirmation before writing.
5. Ask: "Where should these fit in priority order? After the current last item, or insert at a specific position?"

### 2. Revise Features

1. User specifies which feature(s) to revise (by ID or title).
2. Show the current entry.
3. Accept edits to any field: `title`, `acceptance_criteria`, `dependencies`.
4. Do NOT allow revising `completed` features without explicit confirmation — warn: "This feature is already completed. Revising it won't re-run implementation. Continue?"

### 3. Reprioritize

1. Show the current priority order (pending/in-progress only).
2. Accept new ordering from the user — can be drag-style ("move feat-005 before feat-002") or full reorder.
3. Renumber priorities sequentially starting from 1, preserving completed features' original priorities.

### 4. Split Features

When a feature is too large (often discovered when relay marks it `blocked`):

1. User specifies the feature to split.
2. Mark the original feature as `status: "split"` and add `"split_into": ["feat-NNN", "feat-NNN"]`.
3. Create sub-features with:
   - New IDs (auto-incremented)
   - Inherited dependencies from the parent, plus dependency on each other if sequential
   - Acceptance criteria distributed from the parent
4. Show the split plan for confirmation.

### 5. Remove Features

1. User specifies which feature(s) to remove.
2. Show the feature details and ask for confirmation.
3. Check if any other features depend on this one — warn if so.
4. Remove the feature entry from the array.
5. Do NOT renumber IDs — IDs are permanent. Priorities can be renumbered.

### 6. Unblock Features

1. Show all features with `status: "blocked"` and their `blocked_reason`.
2. User selects which to unblock.
3. Reset status to `"pending"`, clear `blocked_reason`.

## After Any Change

1. **Write** the updated `.flywheel/feature-checklist.json`.
2. **Update source metadata** in `.flywheel/flywheel-config.json`:
   - If `source.type` is anything other than `"user-input"` (i.e., `"file"`, `"codebase"`, or `"mixed"`), change to `"mixed"` (since user input is now part of the source). If already `"user-input"`, keep it as `"user-input"`.
   - Update `source.user_notes` to reflect the change (append, don't overwrite).
   - Update `source.resolved_at` to current timestamp.
3. **Show the updated checklist** table to the user.
4. **Commit** the changes: `git commit -m "chore(flywheel): update feature checklist"` — only if user confirms.

## Rules

- **IDs are immutable.** Never reuse or renumber feature IDs. Handoff logs reference them.
- **Completed features stay.** Don't remove completed features — they're part of the audit trail.
- **One write at a time.** Show the diff before writing to prevent accidental data loss.
- **Validate JSON.** After writing, re-read the file to confirm it's valid JSON. Common pitfall: trailing commas are not valid JSON — never leave a comma after the last element in an array or object.
- **Referential integrity.** When removing a feature, also clean up any references to it — check `split_into` arrays and `dependencies` arrays in other features and remove the deleted ID.
- **Split must produce >= 2 sub-features.** A split that produces only 1 sub-feature is pointless — the original should just be revised instead. Always create at least 2 sub-features when splitting.
