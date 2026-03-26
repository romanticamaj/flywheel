---
description: Initialize flywheel for a new project — detects tools, creates .flywheel/ artifacts, generates feature checklist
---

# Flywheel: Initialize

You are setting up flywheel for this project. Follow the Initializer protocol.

**REQUIRED:** Read the `flywheel:hub` skill first for overview, then read the `initializer-template.md` file in the hub skill directory for the full protocol.

## Steps

1. Run the runtime detection algorithm (scan skills, node_modules, PATH)
2. Present detected tools to the user
3. Prompt user to choose tools per spoke (planning, multi-agent, review)
4. Generate all artifacts in `.flywheel/`:
   - `flywheel-config.json` (tool choices)
   - `feature-checklist.json` (prompt user for features)
   - `init.sh` + `init.ps1` (auto-detect project type)
   - `claude-progress.jsonl` (empty)
5. Create initial git commit
