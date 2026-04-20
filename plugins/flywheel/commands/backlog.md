---
description: Capture ideas quickly — inline or conversational. Ideas live in a separate backlog until promoted to the feature checklist via /flywheel:features
---

# Flywheel: Backlog

You are capturing ideas for the project backlog. The backlog is a low-friction scratchpad for thoughts that aren't ready to be features yet — extensions of existing features, "what if" ideas, things noticed while working on something else.

## Inline Capture

The primary mode is inline — the user types the idea right after the command:

```
/flywheel:backlog add rate limiting per user, not just global
/flywheel:backlog the settings page could use a search/filter
/flywheel:backlog feat-003 might need websocket support for real-time updates
```

When invoked this way:

1. Parse the idea text from the arguments.
2. Auto-detect if it references an existing feature (look for `feat-NNN` patterns in the text). If found, set `related_to` to that feature ID. Otherwise set `related_to` to `null`.
3. Auto-increment the idea ID from the highest existing ID in `.flywheel/backlog.jsonl` (start at `idea-001` if the file is empty or doesn't exist).
4. Append one JSON line to `.flywheel/backlog.jsonl`:
   ```json
   {"id": "idea-001", "text": "add rate limiting per user, not just global", "related_to": "feat-003", "captured_at": "2026-04-20T14:30:00Z"}
   ```
5. Confirm briefly — one line:
   ```
   Captured idea-001: "add rate limiting per user, not just global" (→ feat-003)
   ```
   Or without a relation:
   ```
   Captured idea-002: "the settings page could use a search/filter"
   ```

That's it. No questions, no menus, no confirmation prompts. Speed is the point.

## Conversational Capture

If the user runs `/flywheel:backlog` with no arguments, switch to conversational mode:

1. Ask: "What's the idea?"
2. Accept the idea in any format.
3. Ask: "Related to an existing feature?" — show a compact list of pending features for reference. Accept a feature ID, or "no".
4. Capture and confirm as above.

## Batch Capture

If the user provides multiple ideas (bullet points, numbered list, multiple lines), capture each as a separate entry:

```
/flywheel:backlog
- rate limiting per user
- export data as CSV
- dark mode for the dashboard
```

Auto-increment IDs for each. Confirm all at once:
```
Captured 3 ideas: idea-003, idea-004, idea-005
```

## List

If the user says `/flywheel:backlog list` or `/flywheel:backlog show`:

1. Read `.flywheel/backlog.jsonl`.
2. Display as a table:
   ```
   BACKLOG — [project name]
   ┌──────────┬─────────────────────────────────────────┬────────────┐
   │ ID       │ Idea                                    │ Related to │
   ├──────────┼─────────────────────────────────────────┼────────────┤
   │ idea-001 │ add rate limiting per user, not just…   │ feat-003   │
   │ idea-002 │ settings page search/filter             │ —          │
   │ idea-003 │ export data as CSV                      │ —          │
   └──────────┴─────────────────────────────────────────┴────────────┘
   3 ideas in backlog
   ```
3. If the backlog is empty, say: "Backlog is empty. Capture ideas with `/flywheel:backlog <your idea>`."

## Remove

If the user says `/flywheel:backlog remove idea-001` (or `drop`, `delete`):

1. Show the idea and ask for confirmation.
2. Remove the line from `.flywheel/backlog.jsonl`.
3. Do NOT renumber IDs — IDs are permanent.

## File Format

**Path**: `.flywheel/backlog.jsonl`

One JSON object per line (JSONL). Fields:

| Field | Type | Description |
|---|---|---|
| `id` | string | `"idea-NNN"`, auto-incremented, permanent |
| `text` | string | The idea, captured verbatim from user input |
| `related_to` | string\|null | Feature ID if related (e.g., `"feat-003"`), otherwise `null` |
| `captured_at` | string | ISO 8601 timestamp |

No status field, no priority, no acceptance criteria. That structure comes when the idea is promoted to the feature checklist via `/flywheel:features`.

## Rules

- **Speed over ceremony.** Inline capture should feel instant — one command in, one line out. Never ask unnecessary questions in inline mode.
- **IDs are permanent.** Never reuse or renumber idea IDs, even after removal. The next ID is always max + 1.
- **No relay integration.** The backlog is invisible to `/flywheel:relay`. Ideas only enter the relay loop after promotion to the feature checklist.
- **Create the file lazily.** If `.flywheel/backlog.jsonl` doesn't exist, create it on first capture. Don't require `/flywheel:init` to have been run — the backlog can exist independently.
- **Validate JSONL.** Each line must be valid JSON. After writing, re-read the last line to confirm.
- **No git commits.** Backlog changes are too small and frequent to warrant commits. The user can commit when they want.
- **Related feature validation.** When `related_to` is set, verify the feature ID exists in `.flywheel/feature-checklist.json` if the file exists. If the feature ID doesn't exist, still capture the idea but note: "Note: feat-NNN not found in checklist — captured anyway."
