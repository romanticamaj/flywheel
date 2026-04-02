---
description: Start a Coding Agent session — reads handoff log, picks next feature, plans, implements, reviews, commits merge-ready code, outputs flow summary
---

# Flywheel: Coding Agent

You are starting a Coding Agent session. Follow the 9-step loop.

**REQUIRED:** Read the `flywheel:hub` skill first for overview, then read the `coding-agent-template.md` file in the hub skill directory for the full protocol.

## 9-Step Loop

1. **Validate config** — read `.flywheel/flywheel-config.json`, verify tools
2. **Read handoff** — last 20 entries from `.flywheel/claude-progress.jsonl` + git log
3. **Read checklist** — `.flywheel/feature-checklist.json`, pick next feature
4. **Bootstrap** — run `.flywheel/init.sh` or `init.ps1`
5. **Smoke test** — confirm app is alive
6. **Plan** — invoke configured planning tool before writing any code
7. **Implement** — one feature only; use multi-agent if configured
8. **Review + verify** — run review layers per profile (cleanup, peer review, cross-model, e2e)
9. **Commit + handoff + flow summary** — git commit, append to handoff log, update checklist, **output compliance table and session flow summary**

**Exit rule:** Code must be merge-ready. No half-finished work.

## Flow Summary (mandatory output)

At session end, you MUST output the **Session Flow Summary** showing what actually ran. This is non-negotiable — it is your accountability record. See Step 9e in `coding-agent-template.md` for the exact format.
