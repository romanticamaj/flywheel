# Coding Agent Template — 9-Step Session Loop (with Flow Summary)

This template defines the loop that every Coding Agent session follows in the flywheel protocol. Each session picks up where the last left off, implements exactly one feature, and leaves the codebase merge-ready.

---

## Stage Tracker

Initialize a compliance tracker at the start of every session. Update it as each stage completes. Output the final flow summary at session end (Step 9e).

```
STAGE TRACKER (initialize at session start):
┌────┬──────────────────────┬────────────┬──────────────┬────────┐
│ #  │ Stage                │ Configured │ Actual       │ Status │
├────┼──────────────────────┼────────────┼──────────────┼────────┤
│ 1  │ Validate config      │ —          │              │        │
│ 2  │ Read handoff         │ —          │              │        │
│ 3  │ Read checklist       │ —          │              │        │
│ 4  │ Bootstrap            │ init.sh    │              │        │
│ 5  │ Smoke test           │ —          │              │        │
│ 6  │ Plan                 │ {plan.tool}│              │        │
│ 7  │ Implement            │ —          │              │        │
│ 8a │ Review: self-review  │ {tool}     │              │        │
│ 8b │ Review: code-review  │ {tool}     │              │        │
│ 8c │ Review: cross-model  │ {tool}     │              │        │
│ 8d │ Review: e2e          │ {tool}     │              │        │
│ 9  │ Commit + handoff     │ —          │              │        │
└────┴──────────────────────┴────────────┴──────────────┴────────┘

Status values: ✅ OK | ⚠️ FALLBACK | ❌ SKIPPED | 🔄 PENDING
```

Fill in the "Configured" column from `flywheel-config.json` during Step 1. Update "Actual" and "Status" as each stage completes.

**Enforcement rules:**
1. **Attempt before fallback.** Every configured tool MUST be invoked before trying alternatives. Substituting a different tool without attempting the configured one is a violation, not a fallback.
2. **Ask before skipping.** If a configured tool fails or is not installed, ask the user before skipping: `"[Layer X] configured as [tool] — [error]. A) Try [alternative], B) Skip this layer"`. Do NOT skip silently.
3. **Log the error.** When a tool fails, record the actual error message in the "Actual" column (e.g., `"gstack:/codex — command not found"`), not just `"skipped"`.
4. **Output at session end.** The compliance table is a mandatory part of Step 9. It goes in the handoff log AND is shown to the user.

---

## Step 1: Validate Config

Read `.flywheel/flywheel-config.json` and verify that all configured tools (spokes) are still installed and accessible.

- Parse the `tools` object in the config file.
- For each configured spoke (planning, review-pipeline, etc.), confirm the tool is available.
- **If a tool is missing:** Warn the user in output, then fall back to the built-in default for that spoke. Do not abort.
- **Fill the "Configured" column** of the stage tracker with the tool names from the config.

## Step 2: Read Handoff Log

Build context from the previous session's work:

1. Read the **last 20 entries** from `.flywheel/claude-progress.jsonl` (the active file holds up to 50 entries).
2. Run `git log --oneline -20` to get recent commit history.
3. Combine both sources to understand: what was done, what's next, and any notes from the previous session.

If `.flywheel/claude-progress.jsonl` is missing or corrupt, treat this as the first session and rely on `git log` only.

## Step 3: Read Checklist

Read `.flywheel/feature-checklist.json` and select the next feature to implement:

1. Parse the checklist.
2. Skip any item with status `blocked`.
3. Pick the highest priority uncompleted item (lowest `priority` number).
4. Read the feature's `title`, `description`, and `acceptance_criteria` — these define the scope for this session.

If no uncompleted items remain, report "all features complete" and exit the session.

---

## Step 4: Bootstrap

Run the project's initialization script to start the development environment:

- **Unix/macOS:** `.flywheel/init.sh`
- **Windows:** `.flywheel/init.ps1`

Wait for the script to complete. If the script exits with a **non-zero exit code**, log the error to `.flywheel/claude-progress.jsonl` and abort the session with a diagnostic message. Do not proceed to implementation.

## Step 5: Smoke Test

Before making any changes, confirm the application is alive and functional:

- Run the project's existing test suite, health check endpoint, or build command as appropriate.
- The goal is to verify the baseline is healthy — do not touch code until this passes.

If the app is **not responding or the smoke test fails**, log the error to `.flywheel/claude-progress.jsonl` and abort the session with a diagnostic message.

---

## Step 6: Plan the Implementation

**REQUIRED before writing any code.** Invoke the configured planning tool from `planning.tool` in the config to design the implementation approach.

1. Read `planning.tool` from `.flywheel/flywheel-config.json`.
2. Invoke the configured tool (e.g., `superpowers` → use the brainstorming/writing-plans skill; `planning-with-files` → create task_plan.md; `built-in` → outline the approach in a message to the user).
3. If the configured tool is unavailable, try each tool in `planning.alternatives` in order.
4. The plan should cover: what files to create/modify, key technical decisions, risks, and how acceptance criteria will be verified.
5. **Do not skip this step.** Even for research/benchmark features, plan the approach before executing.

---

## Step 7: Implement One Feature

Implement the feature selected in Step 3, following the plan from Step 6. Rules:

- **Strictly one feature.** No scope creep. Do not start a second feature.
- Reference the feature's `acceptance_criteria` from the checklist as the definition of done.
- Write tests as part of implementation (unit tests at minimum).
- Use `multi_agent.tool` from the config when tasks can be parallelized (e.g., independent installations, concurrent tests). Do not default to serial execution when parallel agents are configured.

**If blocked by an unresolvable issue:**

1. Mark the feature as `blocked` in `.flywheel/feature-checklist.json` with a `blocked_reason` explaining why.
2. Move to the next highest priority uncompleted item in the checklist.
3. If there is no next priority item, abort the session.

---

## Step 8: Review + Verify

Run the review pipeline by iterating through each configured layer in `.flywheel/flywheel-config.json`.

### 8a. Execute Each Review Layer

**ENFORCEMENT: You MUST attempt the configured tool first. Running a different tool "because it's similar" is a VIOLATION, not a fallback.** The only legitimate fallback triggers are: (1) the tool command is not found, (2) the tool invocation returns an error, (3) the tool is `null` in config (explicitly disabled).

For each layer in `review.layers` (self-review, code-review, cross-model, e2e):

1. Read the tool name from `review.tools[layer]`.
2. If the tool is `null` → **skip** (layer explicitly disabled). Log as `"skipped (disabled)"`. Update tracker: Status = `✅ OK`.
3. **Attempt the configured tool first:**
   - Invoke it using the Skill tool (e.g., `superpowers:/simplify`, `gstack:/review`, `gstack:/codex`, `gstack:/qa`).
   - If the tool succeeds → update tracker: Actual = tool name, Status = `✅ OK`.
4. **If the configured tool fails:**
   - Log the actual error: update tracker: Actual = `"{tool} — {error message}"`.
   - **Ask the user before proceeding:**
     ```
     "[Layer] configured as {tool} — {error}.
      A) Try {first alternative}
      B) Skip this layer
      C) Abort session"
     ```
   - Try each tool in `review.alternatives[layer]` in order (only if user approves).
   - Update tracker: Status = `⚠️ FALLBACK` with the tool that actually ran.
5. Only if ALL alternatives also fail → use built-in fallback. Update tracker: Status = `⚠️ FALLBACK (built-in)`.
6. If user chose to skip → update tracker: Status = `❌ SKIPPED (user approved)`.

**Common rationalization traps (these are VIOLATIONS, not fallbacks):**
- "The simplify agents already covered code review" → NO. `gstack:/review` must still be invoked.
- "Codex is not installed so I'll skip cross-model" → NO. Attempt the invocation first; if it fails, ask the user.
- "The mock test covers E2E" → NO. `gstack:/qa` must be attempted first.
- "I already found issues, so another review pass is redundant" → NO. Each layer catches different things.

### 8b. Minimum Tier (Required)

At minimum, these two layers MUST run — even if using built-in fallbacks:

- **Layer 2 (code-review):** Invoke the configured tool, or fall back to alternatives, or spawn a code-reviewer subagent.
- **Layer 4 (e2e):** Invoke the configured tool, or run built-in smoke test: `init.sh` exit 0, test suite passes, health endpoint returns 200.

### 8c. Log Review Results

Record which tool was used for each layer — this goes into the handoff entry (Step 9b):

```json
"review": {
  "self-review": "superpowers:/simplify",
  "code-review": "gstack:/review",
  "cross-model": "gstack:/codex — command not found → skipped (user approved)",
  "e2e": "gstack:/qa"
}
```

When logging fallbacks, include the chain: `"{configured} — {error} → {fallback used}"`.

### 8d. Verify Acceptance Criteria

After all review layers pass, verify each acceptance criterion from the checklist is met.

**If critical issues are found:**

1. Loop back to Step 7 to fix the issues.
2. Re-run the review pipeline.
3. **Maximum 3 retries.** If the feature still fails after 3 review cycles:
   - Revert all changes made during this session.
   - Mark the feature as `blocked` in `.flywheel/feature-checklist.json` with details of the failures.
   - Abort the session.

---

## Step 9: Commit + Handoff

The feature is complete. Finalize and hand off to the next session.

### 9a. Commit

```bash
git add <changed files>
git commit -m "feat(feat-XXX): <feature title>"
```

Use the feature ID and title from the checklist. Only add files that were changed as part of this feature.

### 9b. Append Handoff Entry

Append a single JSONL entry to `.flywheel/claude-progress.jsonl`:

```json
{"timestamp":"2026-03-23T14:30:00Z","feature_id":"feat-001","feature_title":"User authentication","status":"completed","changes":["Added auth module (src/auth/)","Login/signup endpoints","JWT middleware"],"tests":{"unit":12,"e2e":1,"all_passing":true},"review":{"self-review":"superpowers:/simplify","code-review":"gstack:/review","cross-model":"skipped (disabled)","e2e":"built-in smoke test"},"planning":{"tool":"planning-with-files","output":"task_plan.md with 5 steps"},"multi_agent":{"tool":"not used","reason":"single-threaded implementation"},"compliance":{"total":16,"ok":15,"fallback":0,"skipped":1,"violations":0},"flow_summary":"Planning: planning-with-files (task_plan.md). Multi-agent: not used. Review: self-review OK, code-review OK, cross-model skipped (user-approved), e2e OK. 6/6 acceptance criteria met.","next_priority":"feat-002","notes":"Used bcrypt for password hashing, tokens expire in 24h"}
```

Fields:
- `timestamp` — ISO 8601 UTC timestamp of commit
- `feature_id` — the feature ID from the checklist (e.g., `feat-001`)
- `feature_title` — human-readable title
- `status` — `completed`, `blocked`, or `aborted`
- `changes` — array of short descriptions of what changed
- `tests` — object with `unit` count, `e2e` count, and `all_passing` boolean
- `review` — object recording which tool was used (or skipped/fallback) for each review layer
- `planning` — object with `tool` used and `output` description
- `multi_agent` — object with `tool` used and `reason` if not used
- `compliance` — object with stage counts: `total`, `ok`, `fallback`, `skipped`, `violations`
- `flow_summary` — single-line narrative of how planning, multi-agent, and review were used
- `next_priority` — the feature ID the next session should pick up
- `notes` — any context the next session needs to know

### 9c. Update Checklist

In `.flywheel/feature-checklist.json`:
- Set the feature's `status` to `completed`.
- Set `completed_by_session` to the current ISO 8601 UTC timestamp.

### 9d. Log Rotation

Check the entry count in `.flywheel/claude-progress.jsonl`. If it exceeds **50 entries**:
- Move older entries to `.flywheel/claude-progress-archive.jsonl` (append to archive).
- Keep only the most recent 50 entries in the active file.
- The Coding Agent only reads the active file; the archive is for human reference.

### 9e. Output Session Flow Summary

**REQUIRED.** Output the session flow summary to the user. This is the session's accountability record — one glanceable output that shows what ran, what was skipped, and what comes next.

Format:

```
SESSION FLOW SUMMARY — feat-XXX: <feature title>
Branch: <branch name> | Commits: <commit hashes>

┌─────────────────────────────────────────────────────────────────────────────────┐
│ STAGE COMPLIANCE                                                                │
├────┬──────────────────────┬──────────────────┬─────────────────────────┬────────┤
│ #  │ Stage                │ Configured       │ Actual                  │ Status │
├────┼──────────────────────┼──────────────────┼─────────────────────────┼────────┤
│ 1  │ Validate config      │ —                │ Done                    │ ✅ OK  │
│ 2  │ Read handoff         │ —                │ 5 entries + git log     │ ✅ OK  │
│ 3  │ Read checklist       │ —                │ feat-006 selected       │ ✅ OK  │
│ 4  │ Bootstrap            │ init.sh          │ npm install + vite dev  │ ✅ OK  │
│ 5  │ Smoke test           │ —                │ npm run build passes    │ ✅ OK  │
│ 6  │ Plan                 │ planning-w-files │ task_plan.md created    │ ✅ OK  │
│ 7  │ Implement            │ —                │ 3 files created         │ ✅ OK  │
│ 8a │ Review: self-review  │ /simplify        │ superpowers:/simplify   │ ✅ OK  │
│ 8b │ Review: code-review  │ code-reviewer    │ code-reviewer agent     │ ✅ OK  │
│ 8c │ Review: cross-model  │ codex            │ codex — not found       │ ❌ SKIP│
│ 8d │ Review: e2e          │ built-in         │ npm test + curl :3000   │ ✅ OK  │
│ 9  │ Commit + handoff     │ —                │ 2 commits, log updated  │ ✅ OK  │
├────┴──────────────────────┴──────────────────┴─────────────────────────┴────────┤
│ RESULT: 12/13 stages OK, 1 skipped (user-approved), 0 violations              │
└────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│ SPOKE USAGE                                                                     │
├──────────────┬──────────────────┬───────────────────────────────────────────────┤
│ Spoke        │ Tool             │ Detail                                        │
├──────────────┼──────────────────┼───────────────────────────────────────────────┤
│ Planning     │ planning-w-files │ task_plan.md with 5 steps                     │
│ Multi-agent  │ not used         │ single-threaded — no parallelizable subtasks  │
│ Review (L1)  │ /simplify        │ pass — simplified 2 functions                 │
│ Review (L2)  │ code-reviewer    │ pass — no issues                              │
│ Review (L3)  │ codex            │ skipped — command not found (user approved)   │
│ Review (L4)  │ built-in         │ pass — tests green, health check 200          │
└──────────────┴──────────────────┴───────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│ ACCEPTANCE CRITERIA                                                             │
├───┬─────────────────────────────────────────────────────────────────────────────┤
│ ✅│ User can sign up with email/password                                        │
│ ✅│ User can log in and receive a session token                                 │
│ ✅│ Invalid credentials return 401                                              │
└───┴─────────────────────────────────────────────────────────────────────────────┘

KEY DECISIONS:
  - Used bcrypt for password hashing (argon2 considered, bcrypt simpler for MVP)
  - JWT tokens expire in 24h (configurable in env)

NEXT UP: feat-002 — User profile settings
```

**Rules:**
1. **Every section must be filled in.** If a spoke was not used, show it in the table with a reason (e.g., "not used — no parallelizable subtasks").
2. **Spoke Usage table must show all 4 review layers**, even if some were skipped or disabled.
3. **Acceptance Criteria must list ALL criteria** from the checklist with pass/fail status.
4. **Key Decisions** — list any notable technical decisions, trade-offs, or surprises. If none, write "None — straightforward implementation."
5. A **violation** is when a stage was skipped or substituted WITHOUT attempting the configured tool and WITHOUT user approval. Violations should be zero. If non-zero, explain in Key Decisions.

Also include in the handoff JSONL entry:

```json
"compliance": {
  "total": 13,
  "ok": 12,
  "fallback": 0,
  "skipped": 1,
  "violations": 0
},
"flow_summary": "Planning: planning-with-files (task_plan.md). Multi-agent: not used. Review: L1 OK, L2 OK, L3 skipped (user), L4 OK. 3/3 acceptance criteria met."
```

---

## Error Handling

| Step | Failure | Action |
|------|---------|--------|
| 1. Validate config | Tool missing | Warn user, fall back to built-in for that spoke |
| 2. Read handoff | File missing/corrupt | Treat as first session, rely on git log only |
| 3. Read checklist | No uncompleted items | Report "all features complete" and exit |
| 4. Bootstrap | `init.sh` exits non-zero | Log error to handoff, abort session with diagnostic |
| 5. Smoke test | App not responding | Log error to handoff, abort session with diagnostic |
| 6. Plan | Planning tool unavailable | Try alternatives, then built-in (outline approach in message) |
| 7. Implement | Unresolvable blocker | Mark feature as `blocked` in checklist with reason, move to next priority. If no next priority, abort session. |
| 8. Review | Critical issues found | Loop back to step 7 (max 3 retries). If still failing, revert changes, mark feature `blocked`, abort session. |
| 9. Commit | Git conflict | Abort session, log conflict details to handoff for human resolution |

---

## Exit Rule

Code must be **merge-ready** at session end. No half-finished work, no "WIP" commits. If a feature cannot be completed, revert to last clean state.

## Scope Rule

**One feature per session.** If a feature is too big to complete in a single session, the agent marks it `blocked` — the **human orchestrator** decomposes blocked features into sub-features in the checklist. The agent does not attempt to break down features on its own.

## Common Agent Anti-Patterns

These are failure modes observed in real sessions. If you catch yourself doing any of these, stop and correct.

| Anti-Pattern | What Happens | Fix |
|---|---|---|
| **Silent substitution** | Agent runs a "similar" tool instead of the configured one, without attempting the configured tool first | Always invoke the configured tool. If it fails, log the error and ask the user. |
| **Rationalized skip** | Agent says "X already covered this" to skip a layer | Each layer catches different things. Invoke it anyway. |
| **Deferred handoff** | Agent implements + commits but forgets to update the handoff log | Handoff log is part of the commit loop, not an afterthought. |
| **Stale handoff notes** | Handoff note contains outdated information from earlier in the session | Re-read your handoff note before writing it. Does it reflect the final state? |
| **Missing flow summary** | Agent outputs "done" without the session flow summary | The flow summary is Step 9e. It is not optional — it shows stage compliance, spoke usage, and acceptance criteria in one output. |
| **Skipped planning** | Agent jumps straight to implementation without invoking the planning tool | Step 6 is required. Even for simple features, plan the approach first. |
