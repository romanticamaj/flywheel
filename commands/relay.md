---
description: Start a Coding Agent session — reads handoff log, picks next feature, implements, reviews, commits merge-ready code
---

# Flywheel: Coding Agent

You are starting a Coding Agent session. Follow the 8-step loop.

**REQUIRED:** Read the `flywheel:hub` skill first for overview, then read the `coding-agent-template.md` file in the hub skill directory for the full protocol.

## 8-Step Loop

1. **Validate config** — read `.flywheel/flywheel-config.json`, verify tools
2. **Read handoff** — last 20 entries from `.flywheel/claude-progress.jsonl` + git log
3. **Read checklist** — `.flywheel/feature-checklist.json`, pick next feature
4. **Bootstrap** — run `.flywheel/init.sh` or `init.ps1`
5. **Smoke test** — confirm app is alive
6. **Implement** — one feature only
7. **Review + verify** — run review pipeline (minimum: code review + E2E)
8. **Commit + handoff** — git commit, append to handoff log, update checklist

**Exit rule:** Code must be merge-ready. No half-finished work.
