---
description: Start a Coding Agent session — reads handoff log, picks next feature, plans, implements, reviews, verifies, commits merge-ready code, outputs flow summary
---

# Flywheel: Coding Agent

You are starting a Coding Agent session. Follow the 10-step loop below **to completion**. Every step has a checkpoint marker — you MUST reach the final marker (Step 10) before the session ends.

> **Context budget rule:** If you sense context is running low (large diffs, many tool calls, complex native code), simplify remaining steps rather than abandoning them. A terse flow summary is better than no flow summary.

**REQUIRED:** Read the `flywheel:hub` skill first for overview, then read the `coding-agent-template.md` file in the hub skill directory for detailed sub-step instructions (8a–8f, 9a–9d, 10a–10f).

---

## Execution Contract

You MUST execute every step below and output its checkpoint marker. Do not skip steps. Do not stop early. If context is tight, compress output but still complete every step.

### Step 1/10 — Validate Config
- Read `.flywheel/flywheel-config.json`, verify tools are accessible.
- Fill the "Configured" column of the stage tracker.
- **Checkpoint:** `✅ Step 1/10: Config validated`

### Step 2/10 — Read Handoff
- Read last 20 entries from `.flywheel/claude-progress.jsonl` + `git log --oneline -20`.
- **Checkpoint:** `✅ Step 2/10: Handoff context loaded`

### Step 3/10 — Read Checklist + Select Profile
- Read `.flywheel/feature-checklist.json`, pick next feature (`needs-fix` first, then highest priority `pending`).
- Select profile (adaptive or fixed). Present profile choice to user.
- **Checkpoint:** `✅ Step 3/10: Feature selected — {feat-id}: "{title}" | Profile: {profile}`

### Step 4/10 — Bootstrap
- Run `.flywheel/init.sh` or `init.ps1`. Abort on non-zero exit.
- **Checkpoint:** `✅ Step 4/10: Bootstrap complete`

### Step 5/10 — Smoke Test
- Run test suite, health check, or build to confirm baseline is healthy.
- **Checkpoint:** `✅ Step 5/10: Smoke test passed`

### Step 6/10 — Plan
- Invoke the configured planning tool. Do NOT skip even for simple features.
- **Checkpoint:** `✅ Step 6/10: Plan complete — {tool used}`

### Step 7/10 — Implement
- Implement ONE feature. Write tests. No scope creep.
- **Checkpoint:** `✅ Step 7/10: Implementation complete`

### Step 8/10 — Review
- Run review layers per active profile (see coding-agent-template.md Steps 8a–8f for details).
- Layers: cleanup → peer-review → cross-model → e2e (code review).
- Each layer: attempt configured tool first → log error if fail → ask user before fallback.
- **Checkpoint:** `✅ Step 8/10: Review complete — {layers run summary}`

### Step 9/10 — Verify
- Run platform verification per active profile (see coding-agent-template.md Step 9 for details).
- Profile gate: `full` = required, `standard` = prompted, `light` = optional, `draft` = skipped.
- For each configured platform: run the selected verification tool.
- Verify acceptance criteria are met.
- If critical issues found: loop back to Step 7 (max 3 retries).
- **Checkpoint:** `✅ Step 9/10: Verification complete — {platforms tested}`

### Step 10/10 — Commit + Handoff + Flow Summary
- **10a.** `git add` + `git commit` with feature ID and title.
- **10b.** Append handoff entry to `.flywheel/claude-progress.jsonl`.
- **10c.** Update feature status in `.flywheel/feature-checklist.json` to `implemented`.
- **10d.** Log rotation if >50 entries.
- **10e.** Output the **Session Flow Summary** (see coding-agent-template.md Step 10e for exact format).
- **10f.** User verification checkpoint — prompt user to verify, mark as `verified`/`needs-fix`/`deferred`.
- **Checkpoint:** `✅ Step 10/10: Session complete — flow summary output`

---

## Stage Tracker (initialize at session start)

```
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
│ 8a │ Review: cleanup      │ {tool}     │              │        │
│ 8b │ Review: peer-review  │ {tool}     │              │        │
│ 8c │ Review: cross-model  │ {tool}     │              │        │
│ 8d │ Review: e2e          │ {tool}     │              │        │
│ 9  │ Verify: {platforms}  │ {tools}    │              │        │
│ 10 │ Commit + handoff     │ —          │              │        │
└────┴──────────────────────┴────────────┴──────────────┴────────┘
Status values: ✅ OK | ⚠️ FALLBACK | ❌ SKIPPED | 🔄 PENDING
```

## Rules

- **Exit rule:** Code must be merge-ready. No half-finished work.
- **Scope rule:** One feature per session. If blocked, mark it and move to next.
- **Completion rule:** You MUST reach Step 10/10 and output the flow summary. If you feel context pressure, compress review/verification output — but do NOT skip the commit, handoff, or flow summary.

## Flow Summary (mandatory output at Step 10e)

At session end, you MUST output the **Session Flow Summary** showing what actually ran. This is non-negotiable — it is your accountability record. See Step 10e in `coding-agent-template.md` for the exact format.
