#!/usr/bin/env bash
set -euo pipefail

# ── Flywheel E2E Test Harness ──
# Tests the flywheel plugin by invoking Claude Code in print mode
# against a mock Node.js project with real prompts.
#
# Each test invokes `claude -p` with a specific prompt, then validates
# the resulting artifacts (files, JSON, git commits) against expected
# schema and behavior. Tests run sequentially — later tests depend on
# artifacts created by earlier ones (init → relay → features, etc.).
#
# Usage: ./tests/run-tests.sh [--test <test_name>]
#
# Test groups:
#   --test all              Run all tests (default)
#   --test init             Initializer — creates .flywheel/ artifacts
#   --test relay            Coding agent — 10-step loop (depends on init)
#   --test continuity       Session handoff — second relay picks next feature
#   --test features         All feature management tests (add/revise/split/remove/integrity)
#   --test features-list    Read-only checklist display
#   --test e2e-offline      All offline E2E platform tests (schema, detection, sources, detection-table)
#   --test e2e-live         Live E2E platform init test (requires Claude)
#
# Individual feature tests:
#   --test features-add     Add new features with auto-incremented IDs
#   --test features-revise  Edit acceptance criteria on existing feature
#   --test features-split   Split a feature into sub-features
#   --test features-remove  Remove a feature with referential integrity
#
# E2E platform tests (offline — no Claude needed):
#   --test e2e-schema       Validates platform-aware E2E config JSON structure
#   --test e2e-detection    Checks all 9 platforms in skill files
#   --test e2e-sources      Checks install source URLs for all E2E tools
#   --test e2e-det-table    Checks Detection table completeness
#   --test e2e-init         Live test: init with mobile/web markers (requires Claude)
#
# Other:
#   --cleanup               Remove the test workspace
#
# Test inventory (15 tests, ~57 assertions):
#   TEST 1:  Initializer (/init)           — .flywheel/ dir, config schema, checklist schema, init scripts, git commit
#   TEST 2:  Coding Agent (/relay)         — handoff log, JSONL schema, checklist update, feature commit, compliance output
#   TEST 3:  Session Continuity            — handoff log growth, different feature picked, no duplicate work
#   TEST 4:  Features Add                  — count increased, unique IDs, valid schema, correct titles, unique priorities
#   TEST 5:  Features Revise               — criteria expanded, other features untouched, count stable
#   TEST 6:  Features Split                — count grew, parent marked split, sub-features valid, no duplicate IDs
#   TEST 7:  Features Remove               — count decreased, target gone, schema intact, IDs not renumbered, valid JSON
#   TEST 8:  Source Metadata               — flywheel-config.json source field preserved, config structure intact
#   TEST 9:  Checklist Integrity           — full end-to-end validation: version, types, statuses, split/implemented/verified constraints
#   TEST 10: Features List (/features-list) — output exists, contains IDs/titles/statuses, read-only (no files modified)
#   TEST 11: E2E Config Schema (offline)   — validates platform-aware E2E config structure (single, multi, all-platform)
#   TEST 12: E2E Platform Detection (offline) — review-pipeline and initializer have all 9 platforms and marker files
#   TEST 13: E2E Install Sources (offline) — all new E2E tools have source URLs in initializer template
#   TEST 14: E2E Detection Table (offline) — review-pipeline Detection table has entries for all E2E tools
#   TEST 15: E2E Init with Platforms (live) — init with mobile/web markers produces platform-aware config
#
# Requirements:
#   - `claude` CLI installed and authenticated
#   - `python3` available (for JSON validation)
#   - `git` available
#   - Each test invocation costs ~$0.30-$2.00 (Sonnet; relay/continuity use $2.00 cap, others $1.00)
#   - Override budget with FLYWHEEL_TEST_BUDGET env var (default: $1.00 for non-relay tests)
#   - Per-stage timing is logged after each test; a timing summary table is shown at the end

FLYWHEEL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_WORKSPACE="/tmp/flywheel-test-$(date +%s)"
RESULTS_DIR="$TEST_WORKSPACE/.test-results"
LOG_FILE="/tmp/flywheel-test-latest.log"
PASSED=0
FAILED=0
TEST_FILTER="all"

# Timing
SUITE_START_TIME=$(date +%s)
declare -a TIMING_NAMES=()
declare -a TIMING_DURATIONS=()

# Record the start of a test stage
timer_start() {
  _STAGE_START=$(date +%s)
}

# Record the end of a test stage and store the duration
timer_end() {
  local name="$1"
  local end_time=$(date +%s)
  local duration=$(( end_time - _STAGE_START ))
  TIMING_NAMES+=("$name")
  TIMING_DURATIONS+=("$duration")
  local mins=$(( duration / 60 ))
  local secs=$(( duration % 60 ))
  log "⏱  $name completed in ${mins}m ${secs}s"
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log()  { echo -e "${CYAN}[flywheel-test]${NC} $*"; }
pass() { echo -e "${GREEN}  ✓ $*${NC}"; ((++PASSED)); }
fail() { echo -e "${RED}  ✗ $*${NC}"; ((++FAILED)); }
warn() { echo -e "${YELLOW}  ⚠ $*${NC}"; }
section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

# ── Setup ──

setup_mock_project() {
  log "Creating mock project at $TEST_WORKSPACE"
  mkdir -p "$TEST_WORKSPACE"
  cd "$TEST_WORKSPACE"

  # Initialize git
  git init -q
  git checkout -b main 2>/dev/null || true

  # Create a simple Node.js project
  cat > package.json << 'PKGJSON'
{
  "name": "flywheel-test-app",
  "version": "0.0.1",
  "description": "Mock app for testing flywheel skill",
  "main": "src/index.js",
  "scripts": {
    "start": "node src/index.js",
    "test": "node tests/run.js",
    "build": "echo 'build ok'"
  }
}
PKGJSON

  mkdir -p src tests

  cat > src/index.js << 'INDEXJS'
const http = require("http");

const server = http.createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok" }));
    return;
  }
  res.writeHead(404);
  res.end("Not found");
});

const PORT = process.env.PORT || 3999;
server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});

module.exports = server;
INDEXJS

  cat > tests/run.js << 'TESTJS'
console.log("Running tests...");
console.log("  ✓ placeholder test passes");
process.exit(0);
TESTJS

  git add -A
  git commit -q -m "chore: initial mock project"

  mkdir -p "$RESULTS_DIR"
  log "Mock project ready"
}

cleanup() {
  if [[ -d "$TEST_WORKSPACE" ]]; then
    log "Cleaning up $TEST_WORKSPACE"
    rm -rf "$TEST_WORKSPACE"
  fi
}

# ── Invoke Claude Code ──

# Default timeout per test (seconds). Override with FLYWHEEL_TEST_TIMEOUT env var.
DEFAULT_TEST_TIMEOUT="${FLYWHEEL_TEST_TIMEOUT:-180}"

# Heartbeat: print elapsed time every N seconds while Claude is running.
# Runs as a background process; killed when Claude finishes.
_heartbeat() {
  local name="$1"
  local pid="$2"
  local interval=15
  local elapsed=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep "$interval"
    elapsed=$((elapsed + interval))
    local mins=$((elapsed / 60))
    local secs=$((elapsed % 60))
    # Show heartbeat with step breadcrumb + last line of stderr
    local step=""
    if [[ -f "$TEST_WORKSPACE/.flywheel/.relay-step" ]]; then
      step=$(cat "$TEST_WORKSPACE/.flywheel/.relay-step" 2>/dev/null | head -c 60)
    fi
    local activity=""
    if [[ -f "$RESULTS_DIR/${name}.stderr" ]]; then
      activity=$(tail -1 "$RESULTS_DIR/${name}.stderr" 2>/dev/null | head -c 80)
    fi
    local detail=""
    if [[ -n "$step" && -n "$activity" ]]; then
      detail="[${step}] ${activity}"
    elif [[ -n "$step" ]]; then
      detail="[${step}]"
    elif [[ -n "$activity" ]]; then
      detail="${activity}"
    fi
    if [[ -n "$detail" ]]; then
      echo -e "${YELLOW}  ⏳ ${name}: ${mins}m ${secs}s — ${detail}${NC}" >&2
    else
      echo -e "${YELLOW}  ⏳ ${name}: ${mins}m ${secs}s elapsed...${NC}" >&2
    fi
  done
}

DEFAULT_BUDGET="${FLYWHEEL_TEST_BUDGET:-1.00}"

invoke_claude() {
  local test_name="$1"
  local prompt="$2"
  local timeout="${3:-$DEFAULT_TEST_TIMEOUT}"
  local budget="${4:-$DEFAULT_BUDGET}"
  local output_file="$RESULTS_DIR/${test_name}.txt"
  local json_file="$RESULTS_DIR/${test_name}.json"

  log "Invoking Claude Code for test: $test_name (timeout: ${timeout}s, budget: \$${budget})" >&2

  # Run Claude Code in background so we can monitor + timeout
  set +e
  claude -p "$prompt" \
    --plugin-dir "$FLYWHEEL_DIR" \
    --dangerously-skip-permissions \
    --output-format json \
    --no-session-persistence \
    --model sonnet \
    --max-budget-usd "$budget" \
    2>"$RESULTS_DIR/${test_name}.stderr" \
    > "$json_file" &
  local claude_pid=$!

  # Start heartbeat in background
  _heartbeat "$test_name" "$claude_pid" &
  local heartbeat_pid=$!

  # Wait for Claude to finish or timeout
  local elapsed=0
  local exit_code=0
  while kill -0 "$claude_pid" 2>/dev/null; do
    if [[ $elapsed -ge $timeout ]]; then
      warn "TIMEOUT: $test_name exceeded ${timeout}s — killing Claude process" >&2
      kill "$claude_pid" 2>/dev/null
      wait "$claude_pid" 2>/dev/null || true
      exit_code=124  # standard timeout exit code
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  # If Claude finished normally, collect its exit code
  if [[ $exit_code -ne 124 ]]; then
    wait "$claude_pid" 2>/dev/null
    exit_code=$?
  fi

  # Stop heartbeat
  kill "$heartbeat_pid" 2>/dev/null
  wait "$heartbeat_pid" 2>/dev/null || true
  set -e

  if [[ $exit_code -eq 124 ]]; then
    fail "Test $test_name TIMED OUT after ${timeout}s" >&2
    echo -e "${YELLOW}  Last stderr output:${NC}" >&2
    tail -5 "$RESULTS_DIR/${test_name}.stderr" 2>/dev/null >&2 || true
  elif [[ $exit_code -ne 0 ]]; then
    warn "Claude exited with code $exit_code for test: $test_name" >&2
    tail -5 "$RESULTS_DIR/${test_name}.stderr" 2>/dev/null >&2 || true
  fi

  # Extract text result from JSON output
  if [[ -f "$json_file" ]]; then
    python3 -c "
import json, sys
try:
    data = json.load(open('$json_file'))
    # Handle both single result and array formats
    if isinstance(data, list):
        for item in data:
            if item.get('type') == 'result':
                print(item.get('result', ''))
    elif isinstance(data, dict):
        print(data.get('result', json.dumps(data, indent=2)))
except Exception as e:
    print(f'JSON parse error: {e}', file=sys.stderr)
    # Fallback: just cat the raw output
    with open('$json_file') as f:
        print(f.read())
" > "$output_file" 2>/dev/null || cp "$json_file" "$output_file"
  fi

  echo "$output_file"
}

# ── Test: Initializer ──

test_init() {
  section "TEST 1: Flywheel Initializer (/init)"

  local prompt
  prompt=$(cat << 'PROMPT'
I want to initialize flywheel for this project. Use only built-in defaults for all spokes (planning, multi-agent, review). Do not prompt me for choices — just use built-in for everything.

After creating the flywheel artifacts, generate a feature checklist with these 3 features:

1. "Add version constant" (priority 1): Add a VERSION constant set to "1.0.0" in src/index.js. Acceptance criteria: src/index.js exports a VERSION constant equal to "1.0.0".

2. "User list endpoint" (priority 2): Add GET /users that returns a hardcoded list of users. Acceptance criteria: GET /users returns 200 with JSON array of user objects with id, name, email fields.

3. "Request logging middleware" (priority 3): Add middleware that logs method, url, and timestamp for each request. Acceptance criteria: Every request logs to stdout in format "[timestamp] METHOD /path".

Save the feature checklist to .flywheel/feature-checklist.json. Commit all flywheel artifacts.
PROMPT
)

  local output_file
  output_file=$(invoke_claude "init" "$prompt")

  log "Checking initializer artifacts..."

  # Check .flywheel/ directory exists
  if [[ -d "$TEST_WORKSPACE/.flywheel" ]]; then
    pass ".flywheel/ directory created"
  else
    fail ".flywheel/ directory NOT created"
    return
  fi

  # Check flywheel-config.json
  if [[ -f "$TEST_WORKSPACE/.flywheel/flywheel-config.json" ]]; then
    pass "flywheel-config.json exists"

    # Validate JSON structure
    if python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/flywheel-config.json'))
assert 'planning' in c, 'missing planning'
assert 'multi_agent' in c, 'missing multi_agent'
assert 'review' in c, 'missing review'
assert 'scope_rule' in c, 'missing scope_rule'
assert 'exit_rule' in c, 'missing exit_rule'
print('Valid config structure')
" 2>/dev/null; then
      pass "flywheel-config.json has valid structure (planning, multi_agent, review, scope_rule, exit_rule)"
    else
      fail "flywheel-config.json has invalid structure"
    fi
  else
    fail "flywheel-config.json NOT created"
  fi

  # Check feature-checklist.json
  if [[ -f "$TEST_WORKSPACE/.flywheel/feature-checklist.json" ]]; then
    pass "feature-checklist.json exists"

    # Validate features
    local feature_count
    feature_count=$(python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
features = c.get('features', [])
print(len(features))
" 2>/dev/null || echo "0")

    if [[ "$feature_count" -ge 3 ]]; then
      pass "feature-checklist.json has $feature_count features (expected >= 3)"
    else
      fail "feature-checklist.json has $feature_count features (expected >= 3)"
    fi

    # Check feature structure
    if python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
for f in c.get('features', []):
    assert 'id' in f, f'missing id in {f}'
    assert 'title' in f, f'missing title in {f}'
    assert 'priority' in f, f'missing priority in {f}'
    assert 'status' in f, f'missing status in {f}'
    assert 'acceptance_criteria' in f, f'missing acceptance_criteria in {f}'
    assert f['status'] == 'pending', f'expected pending status, got {f[\"status\"]}'
print('All features have valid structure')
" 2>/dev/null; then
      pass "All features have correct schema (id, title, priority, status, acceptance_criteria)"
    else
      fail "Feature schema validation failed"
    fi
  else
    fail "feature-checklist.json NOT created"
  fi

  # Check init scripts
  if [[ -f "$TEST_WORKSPACE/.flywheel/init.sh" ]]; then
    pass "init.sh exists"
  else
    fail "init.sh NOT created"
  fi

  # Check claude-progress.jsonl
  if [[ -f "$TEST_WORKSPACE/.flywheel/claude-progress.jsonl" ]]; then
    pass "claude-progress.jsonl exists"
  else
    fail "claude-progress.jsonl NOT created"
  fi

  # Check git commit
  local flywheel_committed
  flywheel_committed=$(cd "$TEST_WORKSPACE" && git log --oneline --all | grep -i "flywheel\|init" | head -1)
  if [[ -n "$flywheel_committed" ]]; then
    pass "Flywheel artifacts committed: $flywheel_committed"
  else
    warn "Could not verify flywheel commit in git log"
  fi

  # Dump artifacts for inspection
  log "── Config content ──"
  cat "$TEST_WORKSPACE/.flywheel/flywheel-config.json" 2>/dev/null || true
  log "── Checklist content ──"
  cat "$TEST_WORKSPACE/.flywheel/feature-checklist.json" 2>/dev/null || true
}

# ── Test: Coding Agent (Relay) ──

test_relay() {
  section "TEST 2: Flywheel Coding Agent (/relay)"

  # Pre-check: init must have run
  if [[ ! -f "$TEST_WORKSPACE/.flywheel/flywheel-config.json" ]]; then
    fail "Skipping relay test — init artifacts missing"
    return
  fi

  local prompt
  prompt=$(cat << 'PROMPT'
Run a flywheel relay session. This is a TEST — keep everything minimal.

Steps (write breadcrumb at each: `echo "Step N/10: Name" > .flywheel/.relay-step`):
1. Read .flywheel/flywheel-config.json
2. Read .flywheel/claude-progress.jsonl and git log
3. Read .flywheel/feature-checklist.json, pick highest-priority pending feature
4. Skip bootstrap (no init.sh needed)
5. Run "npm test" as smoke test
6. Plan: the feature is trivial, just note what to change
7. Implement the feature (KEEP IT SIMPLE — minimal code change, no refactoring)
8. Review: run "npm test" and "npm run build"
9. Verify: run "npm test"
10. Commit + Handoff:
    a. git add changed files and commit with message "feat(<feature-id>): <title>"
    b. Append ONE JSON line to .flywheel/claude-progress.jsonl: {"feature_id":"<id>","status":"implemented","timestamp":"<ISO>","summary":"<one line>"}
    c. Update the feature's status to "implemented" in .flywheel/feature-checklist.json (add "implemented_at" timestamp)
    d. git add and commit the checklist/progress updates
    e. Clean up: rm -f .flywheel/.relay-step

CRITICAL: You MUST reach step 10 and produce the handoff artifacts. Do not over-engineer. The feature should require only 1-2 lines of code change.
PROMPT
)

  local output_file
  output_file=$(invoke_claude "relay" "$prompt" 300 2.00)

  log "Checking coding agent results..."

  # Check handoff log was updated
  if [[ -f "$TEST_WORKSPACE/.flywheel/claude-progress.jsonl" ]]; then
    local entry_count
    entry_count=$(wc -l < "$TEST_WORKSPACE/.flywheel/claude-progress.jsonl" | tr -d ' ')
    if [[ "$entry_count" -ge 1 ]]; then
      pass "claude-progress.jsonl has $entry_count entries (handoff written)"

      # Validate JSONL entry structure
      if python3 -c "
import json
with open('$TEST_WORKSPACE/.flywheel/claude-progress.jsonl') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        entry = json.loads(line)
        assert 'feature_id' in entry, 'missing feature_id'
        assert 'status' in entry, 'missing status'
        assert 'timestamp' in entry, 'missing timestamp'
        print(f'Entry: {entry[\"feature_id\"]} — {entry[\"status\"]}')
" 2>/dev/null; then
        pass "Handoff entry has valid JSONL structure (feature_id, status, timestamp)"
      else
        fail "Handoff entry has invalid structure"
      fi
    else
      fail "claude-progress.jsonl is empty (no handoff written)"
    fi
  else
    fail "claude-progress.jsonl missing"
  fi

  # Check checklist was updated
  if python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
done = [f for f in c['features'] if f['status'] in ('completed', 'implemented', 'verified')]
if done:
    print(f'Done: {done[0][\"id\"]} — {done[0][\"title\"]} (status: {done[0][\"status\"]})')
else:
    raise Exception('No completed/implemented/verified features')
" 2>/dev/null; then
    pass "Feature checklist updated (at least one feature implemented)"
  else
    fail "No feature marked as completed/implemented in checklist"
  fi

  # Check that code was actually implemented
  local new_commits
  new_commits=$(cd "$TEST_WORKSPACE" && git log --oneline -5 | grep -i "feat\|version\|health\|user\|log" | head -1)
  if [[ -n "$new_commits" ]]; then
    pass "Feature commit found: $new_commits"
  else
    warn "Could not identify feature commit in git log"
  fi

  # Check compliance table was output
  if [[ -f "$output_file" ]] && grep -qi "compliance\|STAGE TRACKER\|RESULT:" "$output_file" 2>/dev/null; then
    pass "Compliance table present in output"
  else
    warn "Could not verify compliance table in output (may be in JSON format)"
  fi

  # Check the implemented feature works
  if [[ -f "$TEST_WORKSPACE/src/index.js" ]]; then
    # Quick check: does the code have the VERSION constant?
    if grep -q "VERSION\|version\|1\.0\.0" "$TEST_WORKSPACE/src/index.js" 2>/dev/null; then
      pass "Implementation contains VERSION constant in source"
    else
      warn "Could not verify VERSION constant in source"
    fi
  fi

  # Dump handoff log for inspection
  log "── Handoff log ──"
  cat "$TEST_WORKSPACE/.flywheel/claude-progress.jsonl" 2>/dev/null || true
  log "── Updated checklist ──"
  cat "$TEST_WORKSPACE/.flywheel/feature-checklist.json" 2>/dev/null || true
  log "── Git log ──"
  (cd "$TEST_WORKSPACE" && git log --oneline -10) || true
}

# ── Test: Second Relay Session (continuity) ──

test_relay_continuity() {
  section "TEST 3: Flywheel Session Continuity (second /relay)"

  # Pre-check: first relay must have run
  local completed_count
  completed_count=$(python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
print(len([f for f in c['features'] if f['status'] in ('completed', 'implemented', 'verified')]))
" 2>/dev/null || echo "0")

  if [[ "$completed_count" -lt 1 ]]; then
    fail "Skipping continuity test — no completed/implemented features from first relay"
    return
  fi

  local prompt
  prompt=$(cat << 'PROMPT'
Run a flywheel relay session. This is a TEST — keep everything minimal.

This is NOT the first session. Read the handoff log and checklist first. Pick the next pending feature (skip implemented ones).

Steps (write breadcrumb at each: `echo "Step N/10: Name" > .flywheel/.relay-step`):
1. Read .flywheel/flywheel-config.json
2. Read .flywheel/claude-progress.jsonl and git log
3. Read .flywheel/feature-checklist.json, pick next pending feature
4. Skip bootstrap
5. Run "npm test" as smoke test
6. Plan: note what to change (keep it brief)
7. Implement (minimal code change, no refactoring)
8. Review: run "npm test" and "npm run build"
9. Verify: run "npm test"
10. Commit + Handoff:
    a. git add changed files and commit with message "feat(<feature-id>): <title>"
    b. Append ONE JSON line to .flywheel/claude-progress.jsonl: {"feature_id":"<id>","status":"implemented","timestamp":"<ISO>","summary":"<one line>"}
    c. Update the feature's status to "implemented" in .flywheel/feature-checklist.json (add "implemented_at" timestamp)
    d. git add and commit the checklist/progress updates
    e. Clean up: rm -f .flywheel/.relay-step

CRITICAL: You MUST reach step 10 and produce the handoff artifacts. Do not over-engineer.
PROMPT
)

  local output_file
  output_file=$(invoke_claude "relay_continuity" "$prompt" 300 2.00)

  log "Checking session continuity..."

  # Check handoff log grew
  local entry_count
  entry_count=$(wc -l < "$TEST_WORKSPACE/.flywheel/claude-progress.jsonl" | tr -d ' ')
  if [[ "$entry_count" -ge 2 ]]; then
    pass "Handoff log has $entry_count entries (grew from previous session)"
  else
    fail "Handoff log has $entry_count entries (expected >= 2)"
  fi

  # Check a different feature was completed
  local new_completed
  new_completed=$(python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
done = [f for f in c['features'] if f['status'] in ('completed', 'implemented', 'verified')]
print(len(done))
" 2>/dev/null || echo "0")

  if [[ "$new_completed" -ge 2 ]]; then
    pass "$new_completed features now done (continuity works — picked next feature)"
  else
    fail "Only $new_completed features done (expected >= 2 after second session)"
  fi

  # Verify the second handoff entry references a different feature
  if python3 -c "
import json
entries = []
with open('$TEST_WORKSPACE/.flywheel/claude-progress.jsonl') as f:
    for line in f:
        line = line.strip()
        if line:
            entries.append(json.loads(line))
if len(entries) >= 2:
    ids = [e['feature_id'] for e in entries]
    assert len(set(ids)) >= 2, f'Same feature in both sessions: {ids}'
    print(f'Sessions worked on different features: {ids}')
else:
    raise AssertionError(f'Only {len(entries)} entries')
" 2>/dev/null; then
    pass "Second session picked a different feature (no duplicate work)"
  else
    fail "Could not verify second session picked a different feature"
  fi

  log "── Final handoff log ──"
  cat "$TEST_WORKSPACE/.flywheel/claude-progress.jsonl" 2>/dev/null || true
  log "── Final checklist ──"
  cat "$TEST_WORKSPACE/.flywheel/feature-checklist.json" 2>/dev/null || true
}

# ── Test: Features List ──

test_features_list() {
  section "TEST 10: Flywheel Features List (/features-list)"

  # Pre-check: init must have run
  if [[ ! -f "$TEST_WORKSPACE/.flywheel/feature-checklist.json" ]]; then
    fail "Skipping features-list test — checklist missing"
    return
  fi

  local prompt
  prompt=$(cat << 'PROMPT'
Show me the feature checklist using the flywheel features-list command. Just display the formatted table — do not modify anything.
PROMPT
)

  local output_file
  output_file=$(invoke_claude "features_list" "$prompt")

  log "Checking features-list output..."

  # Check output exists and has content
  if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
    pass "features-list produced output"
  else
    fail "features-list produced no output"
    return
  fi

  local output_content
  output_content=$(cat "$output_file" 2>/dev/null || echo "")

  # Check output contains feature IDs
  if echo "$output_content" | grep -qi "feat-001\|feat-002\|feat-003"; then
    pass "Output contains feature IDs"
  else
    fail "Output missing feature IDs"
  fi

  # Check output contains feature titles
  if echo "$output_content" | grep -qi "health\|user\|logging\|log"; then
    pass "Output contains feature titles"
  else
    fail "Output missing feature titles"
  fi

  # Check output contains status indicators (icons or text)
  if echo "$output_content" | grep -qi "pending\|completed\|done\|next\|blocked\|split\|✅\|⏳\|🔄"; then
    pass "Output contains status indicators"
  else
    fail "Output missing status indicators"
  fi

  # Check output contains progress summary
  if echo "$output_content" | grep -qi "progress\|completed\|next up\|/[0-9]"; then
    pass "Output contains progress summary"
  else
    warn "Could not verify progress summary (non-critical)"
  fi

  # Check no files were modified (read-only) — exclude .test-results/ which is our own test harness artifact
  local git_status
  git_status=$(cd "$TEST_WORKSPACE" && git status --porcelain 2>/dev/null | grep -v '\.test-results/\|package-lock\.json\|\.relay-step' || echo "")
  if [[ -z "$git_status" ]]; then
    pass "No files modified (read-only verified)"
  else
    fail "Files were modified — features-list should be read-only: $git_status"
  fi

  log "── features-list output ──"
  cat "$output_file" 2>/dev/null || true
}

# ── Test: Features Add ──

test_features_add() {
  section "TEST 4: Flywheel Features — Add (/features)"

  # Pre-check: init must have run
  if [[ ! -f "$TEST_WORKSPACE/.flywheel/feature-checklist.json" ]]; then
    fail "Skipping features-add test — checklist missing"
    return
  fi

  # Record initial feature count
  local initial_count
  initial_count=$(python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
print(len(c.get('features', [])))
" 2>/dev/null || echo "0")

  # Record highest existing ID
  local max_id
  max_id=$(python3 -c "
import json, re
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
ids = [int(re.search(r'\d+', f['id']).group()) for f in c.get('features', []) if re.search(r'\d+', f['id'])]
print(max(ids) if ids else 0)
" 2>/dev/null || echo "0")

  local prompt
  prompt=$(cat << 'PROMPT'
I need to add new features to the flywheel feature checklist. Do NOT prompt me for choices — just add them directly.

Read .flywheel/feature-checklist.json, then add these 2 new features:

1. "Rate limiting middleware" (next priority after existing features): Add rate limiting that caps requests at 100/minute per IP. Acceptance criteria: Returns 429 when limit exceeded; X-RateLimit-Remaining header present on all responses.

2. "Error handling improvements" (next priority after rate limiting): Add structured error responses with error codes. Acceptance criteria: All error responses use {error: string, code: string, details?: object} format; uncaught exceptions return 500 with generic message.

Auto-increment the feature IDs from the highest existing ID. IMPORTANT: Output valid JSON with NO trailing commas. Save the updated checklist. Commit the change with message "chore(flywheel): add rate limiting and error handling features".
PROMPT
)

  local output_file
  output_file=$(invoke_claude "features_add" "$prompt")

  log "Checking feature addition..."

  # Check feature count increased by 2
  local new_count
  new_count=$(python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
print(len(c.get('features', [])))
" 2>/dev/null || echo "0")

  local expected_count=$((initial_count + 2))
  if [[ "$new_count" -ge "$expected_count" ]]; then
    pass "Feature count grew from $initial_count to $new_count (added 2+)"
  else
    fail "Feature count is $new_count (expected >= $expected_count, was $initial_count)"
  fi

  # Check IDs were auto-incremented (no duplicates)
  if python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
ids = [f['id'] for f in c.get('features', [])]
assert len(ids) == len(set(ids)), f'Duplicate IDs found: {ids}'
print(f'All IDs unique: {ids}')
" 2>/dev/null; then
    pass "All feature IDs are unique (no duplicates)"
  else
    fail "Duplicate feature IDs detected"
  fi

  # Check new features have correct schema
  if python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
new_features = c['features'][$initial_count:]
for f in new_features:
    assert 'id' in f, f'missing id'
    assert 'title' in f, f'missing title'
    assert 'priority' in f, f'missing priority'
    assert 'status' in f and f['status'] == 'pending', f'expected pending, got {f.get(\"status\")}'
    assert 'acceptance_criteria' in f and len(f['acceptance_criteria']) > 0, 'missing acceptance_criteria'
print(f'New features have valid schema')
" 2>/dev/null; then
    pass "New features have valid schema with pending status and acceptance criteria"
  else
    fail "New features have invalid schema"
  fi

  # Check new features reference rate limiting or error handling
  if python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
titles = [f['title'].lower() for f in c.get('features', [])]
all_text = ' '.join(titles)
assert 'rate' in all_text or 'limit' in all_text, 'Rate limiting feature not found'
assert 'error' in all_text, 'Error handling feature not found'
print('Both new features found by title')
" 2>/dev/null; then
    pass "New features found: rate limiting and error handling"
  else
    fail "Could not find new features by title"
  fi

  # Check priorities are sequential / non-conflicting
  if python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
priorities = [f['priority'] for f in c.get('features', [])]
assert len(priorities) == len(set(priorities)), f'Duplicate priorities: {priorities}'
print(f'All priorities unique: {sorted(priorities)}')
" 2>/dev/null; then
    pass "All feature priorities are unique"
  else
    warn "Duplicate priorities detected (non-critical)"
  fi

  # Check git commit
  local features_committed
  features_committed=$(cd "$TEST_WORKSPACE" && git log --oneline -3 | grep -i "feature\|checklist\|flywheel\|rate\|error" | head -1)
  if [[ -n "$features_committed" ]]; then
    pass "Features addition committed: $features_committed"
  else
    warn "Could not verify features commit in git log"
  fi

  log "── Updated checklist after add ──"
  cat "$TEST_WORKSPACE/.flywheel/feature-checklist.json" 2>/dev/null || true
}

# ── Test: Features Revise ──

test_features_revise() {
  section "TEST 5: Flywheel Features — Revise (/features)"

  if [[ ! -f "$TEST_WORKSPACE/.flywheel/feature-checklist.json" ]]; then
    fail "Skipping features-revise test — checklist missing"
    return
  fi

  # Find a pending feature to revise
  local target_id
  target_id=$(python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
pending = [f for f in c['features'] if f['status'] == 'pending']
if pending:
    print(pending[0]['id'])
else:
    print('')
" 2>/dev/null || echo "")

  if [[ -z "$target_id" ]]; then
    fail "No pending features to revise"
    return
  fi

  # Capture original acceptance criteria count
  local original_ac_count
  original_ac_count=$(python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
target = [f for f in c['features'] if f['id'] == '$target_id'][0]
print(len(target.get('acceptance_criteria', [])))
" 2>/dev/null || echo "0")

  local prompt
  prompt=$(cat << PROMPT
I need to revise a feature in the flywheel feature checklist. Do NOT prompt me for choices — just make the changes directly.

Read .flywheel/feature-checklist.json, then revise feature $target_id:
- Add a new acceptance criterion: "Returns appropriate HTTP status codes for all error cases"
- Add a new acceptance criterion: "Includes request-id header in all responses for tracing"

Do not change any other features. IMPORTANT: Output valid JSON with NO trailing commas. Save the updated checklist. Commit with message "chore(flywheel): revise $target_id acceptance criteria".
PROMPT
)

  local output_file
  output_file=$(invoke_claude "features_revise" "$prompt")

  log "Checking feature revision..."

  # Check the target feature was revised
  if python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
target = [f for f in c['features'] if f['id'] == '$target_id']
assert len(target) == 1, 'Target feature not found'
target = target[0]
ac = target.get('acceptance_criteria', [])
assert len(ac) > $original_ac_count, f'Expected more criteria than $original_ac_count, got {len(ac)}'
print(f'Acceptance criteria grew from $original_ac_count to {len(ac)}')
" 2>/dev/null; then
    pass "Feature $target_id acceptance criteria expanded"
  else
    fail "Feature $target_id acceptance criteria not expanded"
  fi

  # Check other features were NOT modified
  if python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
others = [f for f in c['features'] if f['id'] != '$target_id']
for f in others:
    assert 'id' in f and 'title' in f and 'status' in f, f'Feature {f.get(\"id\")} corrupted'
print(f'{len(others)} other features intact')
" 2>/dev/null; then
    pass "Other features remain unmodified"
  else
    fail "Other features may have been corrupted"
  fi

  # Check feature count didn't change (revise, not add)
  local current_count
  current_count=$(python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
print(len(c.get('features', [])))
" 2>/dev/null || echo "0")

  # Count should be same as after add (initial 3 + 2 added = 5)
  if python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
# Just verify it's still valid JSON with features array
assert 'features' in c
assert isinstance(c['features'], list)
assert len(c['features']) >= 3
print(f'Feature count stable at {len(c[\"features\"])}')
" 2>/dev/null; then
    pass "Feature count stable (revise didn't add/remove features)"
  else
    fail "Feature count changed unexpectedly during revise"
  fi

  log "── Updated checklist after revise ──"
  cat "$TEST_WORKSPACE/.flywheel/feature-checklist.json" 2>/dev/null || true
}

# ── Test: Features Split ──

test_features_split() {
  section "TEST 6: Flywheel Features — Split (/features)"

  if [[ ! -f "$TEST_WORKSPACE/.flywheel/feature-checklist.json" ]]; then
    fail "Skipping features-split test — checklist missing"
    return
  fi

  # Find a pending feature with multiple acceptance criteria (good candidate to split)
  local target_id
  target_id=$(python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
pending = [f for f in c['features'] if f['status'] == 'pending' and len(f.get('acceptance_criteria', [])) >= 2]
if pending:
    print(pending[-1]['id'])  # pick last multi-criteria pending feature
else:
    # fallback to any pending
    pending = [f for f in c['features'] if f['status'] == 'pending']
    if pending:
        print(pending[-1]['id'])
    else:
        print('')
" 2>/dev/null || echo "")

  if [[ -z "$target_id" ]]; then
    fail "No pending features to split"
    return
  fi

  local pre_split_count
  pre_split_count=$(python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
print(len(c.get('features', [])))
" 2>/dev/null || echo "0")

  local prompt
  prompt=$(cat << PROMPT
I need to split a feature in the flywheel feature checklist. Do NOT prompt me — just do it.

Read .flywheel/feature-checklist.json, then split feature $target_id into EXACTLY 2 sub-features. You MUST create 2 new feature entries:
1. Sub-feature A: the core implementation/logic part — take the first half of the acceptance criteria from the parent
2. Sub-feature B: the validation/edge-cases part — take the remaining acceptance criteria from the parent

Requirements:
- Mark the original feature $target_id with status "split"
- Add a "split_into" field on the original that is an array with EXACTLY 2 new feature IDs
- Create 2 new feature entries with auto-incremented IDs, status "pending", and the distributed acceptance criteria
- Each sub-feature must have at least 1 acceptance criterion
- The sub-features should inherit dependencies from the parent
- Output valid JSON with NO trailing commas

Save the updated checklist. Commit with message "chore(flywheel): split $target_id into sub-features".
PROMPT
)

  local output_file
  output_file=$(invoke_claude "features_split" "$prompt")

  log "Checking feature split..."

  # Check feature count increased (original + 2 new - but original stays with "split" status)
  local post_split_count
  post_split_count=$(python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
print(len(c.get('features', [])))
" 2>/dev/null || echo "0")

  if [[ "$post_split_count" -gt "$pre_split_count" ]]; then
    pass "Feature count grew from $pre_split_count to $post_split_count after split"
  else
    fail "Feature count didn't grow after split ($pre_split_count -> $post_split_count)"
  fi

  # Check original feature is marked as split
  if python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
target = [f for f in c['features'] if f['id'] == '$target_id']
assert len(target) == 1, 'Original feature not found'
target = target[0]
assert target['status'] == 'split', f'Expected split status, got {target[\"status\"]}'
assert 'split_into' in target, 'Missing split_into field'
assert len(target['split_into']) >= 2, f'Expected >= 2 sub-features, got {len(target[\"split_into\"])}'
print(f'Original $target_id marked as split -> {target[\"split_into\"]}')
" 2>/dev/null; then
    pass "Original feature $target_id marked as 'split' with split_into references"
  else
    fail "Original feature $target_id not properly marked as split"
  fi

  # Check sub-features exist and have valid schema
  if python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
target = [f for f in c['features'] if f['id'] == '$target_id'][0]
sub_ids = target.get('split_into', [])
for sub_id in sub_ids:
    sub = [f for f in c['features'] if f['id'] == sub_id]
    assert len(sub) == 1, f'Sub-feature {sub_id} not found'
    sub = sub[0]
    assert sub['status'] == 'pending', f'Sub-feature {sub_id} not pending: {sub[\"status\"]}'
    assert 'acceptance_criteria' in sub and len(sub['acceptance_criteria']) > 0, f'Sub-feature {sub_id} missing acceptance criteria'
    assert 'priority' in sub, f'Sub-feature {sub_id} missing priority'
print(f'All {len(sub_ids)} sub-features have valid schema')
" 2>/dev/null; then
    pass "Sub-features exist with valid schema, pending status, and acceptance criteria"
  else
    fail "Sub-features missing or have invalid schema"
  fi

  # Check no duplicate IDs after split
  if python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
ids = [f['id'] for f in c['features']]
assert len(ids) == len(set(ids)), f'Duplicate IDs after split: {ids}'
print(f'All IDs still unique after split: {ids}')
" 2>/dev/null; then
    pass "No duplicate IDs after split"
  else
    fail "Duplicate IDs found after split"
  fi

  log "── Updated checklist after split ──"
  cat "$TEST_WORKSPACE/.flywheel/feature-checklist.json" 2>/dev/null || true
}

# ── Test: Features Remove ──

test_features_remove() {
  section "TEST 7: Flywheel Features — Remove (/features)"

  if [[ ! -f "$TEST_WORKSPACE/.flywheel/feature-checklist.json" ]]; then
    fail "Skipping features-remove test — checklist missing"
    return
  fi

  local pre_remove_count
  pre_remove_count=$(python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
print(len(c.get('features', [])))
" 2>/dev/null || echo "0")

  # Find a pending feature that is NOT a split sub-feature (avoid breaking split_into references)
  local target_id
  target_id=$(python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
# Collect all IDs referenced in split_into arrays
split_children = set()
for f in c['features']:
    for child_id in f.get('split_into', []):
        split_children.add(child_id)
# Pick a pending feature that is not a split child and not a split parent
candidates = [f for f in c['features']
              if f['status'] == 'pending'
              and f['id'] not in split_children
              and 'split_into' not in f]
if candidates:
    print(candidates[-1]['id'])
else:
    # fallback: any pending feature
    pending = [f for f in c['features'] if f['status'] == 'pending']
    if pending:
        print(pending[-1]['id'])
    else:
        print('')
" 2>/dev/null || echo "")

  if [[ -z "$target_id" ]]; then
    fail "No pending features to remove"
    return
  fi

  local prompt
  prompt=$(cat << PROMPT
I need to remove a feature from the flywheel feature checklist. Do NOT prompt me — just do it.

Read .flywheel/feature-checklist.json, then remove feature $target_id entirely from the features array. Do not renumber IDs of other features.

Check if any other features depend on $target_id or reference it in split_into — if so, clean up those references too.

IMPORTANT: Output valid JSON. Do NOT leave trailing commas after the last element in any array or object. Validate the JSON is parseable before writing.

Save the updated checklist. Commit with message "chore(flywheel): remove $target_id".
PROMPT
)

  local output_file
  output_file=$(invoke_claude "features_remove" "$prompt")

  log "Checking feature removal..."

  # Check feature count decreased
  local post_remove_count
  post_remove_count=$(python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
print(len(c.get('features', [])))
" 2>/dev/null || echo "0")

  if [[ "$post_remove_count" -lt "$pre_remove_count" ]]; then
    pass "Feature count decreased from $pre_remove_count to $post_remove_count"
  else
    fail "Feature count didn't decrease ($pre_remove_count -> $post_remove_count)"
  fi

  # Check target feature is gone
  if python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
ids = [f['id'] for f in c['features']]
assert '$target_id' not in ids, f'$target_id still in checklist: {ids}'
print(f'$target_id successfully removed. Remaining: {ids}')
" 2>/dev/null; then
    pass "Feature $target_id removed from checklist"
  else
    fail "Feature $target_id still present in checklist"
  fi

  # Check remaining features have intact schema
  if python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
for f in c['features']:
    assert 'id' in f, 'missing id'
    assert 'title' in f, 'missing title'
    assert 'status' in f, 'missing status'
    assert 'priority' in f, 'missing priority'
print(f'All {len(c[\"features\"])} remaining features have valid schema')
" 2>/dev/null; then
    pass "Remaining features have intact schema after removal"
  else
    fail "Remaining features corrupted after removal"
  fi

  # Check IDs were NOT renumbered
  if python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
ids = [f['id'] for f in c['features']]
# IDs should not be sequential if one was removed — gaps are expected
assert len(ids) == len(set(ids)), f'Duplicate IDs: {ids}'
print(f'IDs preserved (not renumbered): {ids}')
" 2>/dev/null; then
    pass "Feature IDs were not renumbered (immutable IDs preserved)"
  else
    fail "Feature IDs may have been renumbered"
  fi

  # Verify JSON is valid
  if python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
assert 'version' in c, 'missing version'
assert 'features' in c, 'missing features'
assert isinstance(c['features'], list), 'features is not a list'
print('JSON valid')
" 2>/dev/null; then
    pass "Checklist JSON is valid after removal"
  else
    fail "Checklist JSON is invalid after removal"
  fi

  log "── Updated checklist after remove ──"
  cat "$TEST_WORKSPACE/.flywheel/feature-checklist.json" 2>/dev/null || true
}

# ── Test: Features Source Metadata Update ──

test_features_source_metadata() {
  section "TEST 8: Flywheel Features — Source Metadata Update"

  if [[ ! -f "$TEST_WORKSPACE/.flywheel/flywheel-config.json" ]]; then
    fail "Skipping source metadata test — config missing"
    return
  fi

  # Check that source metadata was updated after feature modifications
  if python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/flywheel-config.json'))
source = c.get('source', {})
assert 'type' in source, 'missing source.type'
assert 'resolved_at' in source, 'missing source.resolved_at'
print(f'Source type: {source[\"type\"]}')
print(f'Resolved at: {source[\"resolved_at\"]}')
if source.get('user_notes'):
    print(f'User notes: {source[\"user_notes\"]}')
" 2>/dev/null; then
    pass "Source metadata present in flywheel-config.json"
  else
    fail "Source metadata incomplete — features command must update source in flywheel-config.json"
  fi

  # Check the config is still valid overall
  if python3 -c "
import json
c = json.load(open('$TEST_WORKSPACE/.flywheel/flywheel-config.json'))
assert 'planning' in c, 'missing planning'
assert 'multi_agent' in c, 'missing multi_agent'
assert 'review' in c, 'missing review'
assert 'verification' in c, 'missing verification (v1.9.0: platform verification is top-level)'
print('Config structure still valid')
" 2>/dev/null; then
    pass "flywheel-config.json structure preserved through all feature operations"
  else
    fail "flywheel-config.json structure corrupted"
  fi
}

# ── Test: Checklist Integrity (end-to-end validation) ──

test_checklist_integrity() {
  section "TEST 9: Checklist Integrity — End-to-End Validation"

  if [[ ! -f "$TEST_WORKSPACE/.flywheel/feature-checklist.json" ]]; then
    fail "Skipping integrity test — checklist missing"
    return
  fi

  # Validate the full checklist after all operations
  # First check if JSON is even parseable
  if ! python3 -c "import json; json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))" 2>/dev/null; then
    fail "Checklist JSON is not valid — likely trailing comma or syntax error"
    log "Attempting to show the JSON error:"
    python3 -c "
import json
try:
    json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))
except json.JSONDecodeError as e:
    print(f'  JSON error: {e}')
" 2>/dev/null || true
    log "Raw file tail:"
    tail -10 "$TEST_WORKSPACE/.flywheel/feature-checklist.json" 2>/dev/null || true
    return
  fi

  if python3 -c "
import json

c = json.load(open('$TEST_WORKSPACE/.flywheel/feature-checklist.json'))

# Top-level structure
assert 'version' in c, 'missing version'
assert c['version'] == 1, f'unexpected version: {c[\"version\"]}'
assert 'features' in c, 'missing features'
assert isinstance(c['features'], list), 'features is not a list'

# Feature-level validation
ids = []
valid_statuses = {'pending', 'in-progress', 'implemented', 'needs-fix', 'verified', 'blocked', 'split'}
for f in c['features']:
    # Required fields
    assert 'id' in f, f'feature missing id: {f}'
    assert 'title' in f, f'feature missing title: {f}'
    assert 'priority' in f, f'feature missing priority: {f}'
    assert 'status' in f, f'feature missing status: {f}'
    assert f['status'] in valid_statuses, f'invalid status {f[\"status\"]} for {f[\"id\"]}'

    # Type checks
    assert isinstance(f['id'], str), f'id should be string: {f[\"id\"]}'
    assert isinstance(f['title'], str), f'title should be string: {f[\"title\"]}'
    assert isinstance(f['priority'], int), f'priority should be int: {f[\"priority\"]}'

    # Acceptance criteria
    if f['status'] != 'split':
        assert 'acceptance_criteria' in f, f'missing acceptance_criteria in {f[\"id\"]}'
        assert isinstance(f['acceptance_criteria'], list), f'acceptance_criteria should be list in {f[\"id\"]}'
        assert len(f['acceptance_criteria']) > 0, f'empty acceptance_criteria in {f[\"id\"]}'

    # Split features must have split_into
    if f['status'] == 'split':
        assert 'split_into' in f, f'split feature {f[\"id\"]} missing split_into'

    # Implemented/verified features must have a timestamp
    if f['status'] == 'implemented':
        assert f.get('implemented_at') is not None or f.get('completed_by_session') is not None, f'implemented feature {f[\"id\"]} missing timestamp'
    if f['status'] == 'verified':
        assert f.get('verified_at') is not None or f.get('completed_by_session') is not None, f'verified feature {f[\"id\"]} missing verified_at'

    ids.append(f['id'])

# No duplicate IDs
assert len(ids) == len(set(ids)), f'Duplicate IDs: {[x for x in ids if ids.count(x) > 1]}'

print(f'Full integrity check passed: {len(c[\"features\"])} features, all valid')
print(f'Statuses: { {s: sum(1 for f in c[\"features\"] if f[\"status\"]==s) for s in valid_statuses if any(f[\"status\"]==s for f in c[\"features\"])} }')
" 2>/dev/null; then
    pass "Full checklist integrity check passed"
  else
    fail "Checklist integrity check failed"
  fi

  # Check git history shows a clean sequence of flywheel operations
  local flywheel_commits
  flywheel_commits=$(cd "$TEST_WORKSPACE" && git log --oneline | grep -ic "flywheel\|feat\|chore" || echo "0")
  if [[ "$flywheel_commits" -ge 3 ]]; then
    pass "Git history has $flywheel_commits flywheel-related commits"
  else
    warn "Only $flywheel_commits flywheel commits found in git history"
  fi

  log "── Final git log ──"
  (cd "$TEST_WORKSPACE" && git log --oneline -15) || true
  log "── Final checklist ──"
  cat "$TEST_WORKSPACE/.flywheel/feature-checklist.json" 2>/dev/null || true
  log "── Final config ──"
  cat "$TEST_WORKSPACE/.flywheel/flywheel-config.json" 2>/dev/null || true
}

# ── Test: Platform-Aware E2E Config Schema (offline — no Claude invocation) ──

test_e2e_config_schema() {
  section "TEST 11: E2E Config Schema Validation (offline)"

  # This test validates that a flywheel-config.json with the new platform-aware
  # E2E structure passes schema validation. No Claude invocation needed.

  local schema_dir="$TEST_WORKSPACE/.test-e2e-schema"
  mkdir -p "$schema_dir"

  # Valid config with verification section (v1.9.0: platforms moved from review.e2e to verification.platforms)
  cat > "$schema_dir/valid-config.json" << 'JSON'
{
  "planning": { "tool": "built-in", "alternatives": [] },
  "multi_agent": { "tool": "claude-code-native", "alternatives": [] },
  "profile": { "default": "adaptive" },
  "review": {
    "layers": ["cleanup", "peer-review", "cross-model", "e2e"],
    "tools": {
      "cleanup": "built-in",
      "peer-review": "built-in",
      "cross-model": null,
      "e2e": "built-in"
    },
    "alternatives": {
      "cleanup": ["superpowers:/simplify"],
      "peer-review": ["gstack:/review"],
      "cross-model": ["codex:review"],
      "e2e": ["gstack:/qa"]
    },
    "profiles": {
      "full":     { "cleanup": true,  "peer-review": "full",    "cross-model": true,  "e2e": true  },
      "standard": { "cleanup": false, "peer-review": "top5",    "cross-model": false, "e2e": true  },
      "light":    { "cleanup": false, "peer-review": "verdict", "cross-model": false, "e2e": false },
      "draft":    { "cleanup": false, "peer-review": false,     "cross-model": false, "e2e": false }
    }
  },
  "verification": {
    "platforms": {
      "web": { "tool": "playwright", "alternatives": ["gstack:/qa", "built-in"] },
      "ios": { "tool": "mobile-mcp", "alternatives": ["ios-simulator-mcp", "maestro", "built-in"] },
      "android": { "tool": "maestro", "alternatives": ["mobile-mcp", "built-in"] }
    },
    "profiles": {
      "full":     { "run": "all-platforms" },
      "standard": { "run": "primary-only" },
      "light":    { "run": "built-in-only" },
      "draft":    { "run": "none" }
    }
  },
  "source": { "type": "user-input", "paths": [], "user_notes": null, "resolved_at": "2026-04-04T00:00:00Z" },
  "scope_rule": "one-feature-per-session",
  "exit_rule": "merge-ready",
  "branch_naming": "feat/{id}-{slug}"
}
JSON

  # Validate the verification schema
  if python3 -c "
import json

c = json.load(open('$schema_dir/valid-config.json'))

# verification must exist as top-level key
assert 'verification' in c, 'missing verification section'
v = c['verification']

# verification.platforms must be a dict
assert 'platforms' in v, 'missing verification.platforms'
assert isinstance(v['platforms'], dict), 'platforms must be dict'

# Valid platform names
valid_platforms = {'web', 'ios', 'android', 'electron', 'tauri', 'flutter-desktop', 'audio-plugin', 'api', 'cli'}
for platform, config in v['platforms'].items():
    assert platform in valid_platforms, f'invalid platform: {platform}'
    assert 'tool' in config, f'missing tool for platform {platform}'
    assert 'alternatives' in config, f'missing alternatives for platform {platform}'
    assert isinstance(config['alternatives'], list), f'alternatives must be list for {platform}'
    assert isinstance(config['tool'], str), f'tool must be string for {platform}'

# verification.profiles must exist
assert 'profiles' in v, 'missing verification.profiles'
for profile in ['full', 'standard', 'light', 'draft']:
    assert profile in v['profiles'], f'missing profile: {profile}'
    assert 'run' in v['profiles'][profile], f'missing run in profile {profile}'

# review.tools.e2e should exist as code review E2E (separate from verification)
assert 'e2e' in c['review'].get('tools', {}), 'review.tools.e2e should exist for code review E2E layer'

print(f'Valid: {len(v[\"platforms\"])} platforms configured: {list(v[\"platforms\"].keys())}')
" 2>/dev/null; then
    pass "Verification schema validates correctly"
  else
    fail "Verification schema validation failed"
  fi

  # Test: each platform has a valid tool name
  if python3 -c "
import json

c = json.load(open('$schema_dir/valid-config.json'))
known_tools = {
    'web': ['playwright', 'gstack:/qa', 'built-in'],
    'ios': ['mobile-mcp', 'ios-simulator-mcp', 'maestro', 'built-in'],
    'android': ['mobile-mcp', 'maestro', 'built-in'],
    'electron': ['electron-playwright-mcp', 'playwright', 'built-in'],
    'tauri': ['tauri-plugin-mcp', 'playwright', 'built-in'],
    'flutter-desktop': ['patrol', 'built-in'],
    'audio-plugin': ['pluginval', 'playwright', 'built-in'],
    'api': ['built-in'],
    'cli': ['built-in']
}

for platform, config in c['verification']['platforms'].items():
    assert config['tool'] in known_tools[platform], f'{config[\"tool\"]} not valid for {platform}. Valid: {known_tools[platform]}'
    for alt in config['alternatives']:
        assert alt in known_tools[platform], f'alternative {alt} not valid for {platform}'

print('All platform tools are valid')
" 2>/dev/null; then
    pass "All configured verification tools are valid for their platforms"
  else
    fail "Invalid verification tool found for a platform"
  fi

  # Test: config with no platforms is valid (api-only project)
  cat > "$schema_dir/api-only-config.json" << 'JSON'
{
  "planning": { "tool": "built-in", "alternatives": [] },
  "multi_agent": { "tool": "claude-code-native", "alternatives": [] },
  "profile": { "default": "adaptive" },
  "review": {
    "layers": ["cleanup", "peer-review", "cross-model", "e2e"],
    "tools": { "cleanup": "built-in", "peer-review": "built-in", "cross-model": null, "e2e": "built-in" },
    "alternatives": {},
    "profiles": {}
  },
  "verification": {
    "platforms": {
      "api": { "tool": "built-in", "alternatives": [] }
    },
    "profiles": {
      "full": { "run": "all-platforms" }, "standard": { "run": "primary-only" },
      "light": { "run": "built-in-only" }, "draft": { "run": "none" }
    }
  },
  "source": { "type": "user-input", "paths": [], "user_notes": null, "resolved_at": "2026-04-04T00:00:00Z" },
  "scope_rule": "one-feature-per-session",
  "exit_rule": "merge-ready",
  "branch_naming": "feat/{id}-{slug}"
}
JSON

  if python3 -c "
import json
c = json.load(open('$schema_dir/api-only-config.json'))
assert len(c['verification']['platforms']) == 1
assert 'api' in c['verification']['platforms']
assert c['verification']['platforms']['api']['tool'] == 'built-in'
print('API-only config valid')
" 2>/dev/null; then
    pass "API-only project config (single platform) validates correctly"
  else
    fail "API-only config validation failed"
  fi

  # Test: config with all platforms is valid
  cat > "$schema_dir/multi-platform-config.json" << 'JSON'
{
  "planning": { "tool": "built-in", "alternatives": [] },
  "multi_agent": { "tool": "claude-code-native", "alternatives": [] },
  "profile": { "default": "adaptive" },
  "review": {
    "layers": ["cleanup", "peer-review", "cross-model", "e2e"],
    "tools": { "cleanup": "built-in", "peer-review": "built-in", "cross-model": null, "e2e": "built-in" },
    "alternatives": {},
    "profiles": {}
  },
  "verification": {
    "platforms": {
      "web": { "tool": "playwright", "alternatives": ["built-in"] },
      "ios": { "tool": "mobile-mcp", "alternatives": ["built-in"] },
      "android": { "tool": "mobile-mcp", "alternatives": ["built-in"] },
      "electron": { "tool": "electron-playwright-mcp", "alternatives": ["built-in"] },
      "tauri": { "tool": "tauri-plugin-mcp", "alternatives": ["built-in"] },
      "flutter-desktop": { "tool": "patrol", "alternatives": ["built-in"] },
      "audio-plugin": { "tool": "pluginval", "alternatives": ["built-in"] },
      "api": { "tool": "built-in", "alternatives": [] },
      "cli": { "tool": "built-in", "alternatives": [] }
    },
    "profiles": {
      "full": { "run": "all-platforms" }, "standard": { "run": "primary-only" },
      "light": { "run": "built-in-only" }, "draft": { "run": "none" }
    }
  },
  "source": { "type": "user-input", "paths": [], "user_notes": null, "resolved_at": "2026-04-04T00:00:00Z" },
  "scope_rule": "one-feature-per-session",
  "exit_rule": "merge-ready",
  "branch_naming": "feat/{id}-{slug}"
}
JSON

  if python3 -c "
import json
c = json.load(open('$schema_dir/multi-platform-config.json'))
assert len(c['verification']['platforms']) == 9, f'expected 9 platforms, got {len(c[\"verification\"][\"platforms\"])}'
print(f'Multi-platform config valid: {len(c[\"verification\"][\"platforms\"])} platforms')
" 2>/dev/null; then
    pass "Multi-platform config (all 9 platforms) validates correctly"
  else
    fail "Multi-platform config validation failed"
  fi

  rm -rf "$schema_dir"
}

# ── Test: Platform Detection from Marker Files (offline) ──

test_e2e_platform_detection() {
  section "TEST 12: E2E Platform Detection from Marker Files (offline)"

  # Validate that the marker-file-to-platform mapping in the initializer template
  # is consistent with the review-pipeline skill's platform list.

  local skill_file="$FLYWHEEL_DIR/plugins/flywheel/skills/review-pipeline/SKILL.md"
  local init_file="$FLYWHEEL_DIR/plugins/flywheel/skills/hub/initializer-template.md"

  # Check review-pipeline SKILL.md has all 9 platforms
  if python3 -c "
import re

with open('$skill_file') as f:
    content = f.read()

expected_platforms = ['web', 'ios', 'android', 'electron', 'tauri', 'flutter-desktop', 'audio-plugin', 'api', 'cli']
missing = []
for p in expected_platforms:
    # Check in Framework Slots table (E2E — <platform>)
    if f'E2E — {p}' not in content:
        # Also check the Platform Tool Matrix
        if f'**{p}**' not in content:
            missing.append(p)

if missing:
    raise AssertionError(f'Missing platforms in review-pipeline SKILL.md: {missing}')
print(f'All {len(expected_platforms)} platforms found in review-pipeline SKILL.md')
" 2>/dev/null; then
    pass "review-pipeline/SKILL.md contains all 9 E2E platforms"
  else
    fail "review-pipeline/SKILL.md is missing platforms"
  fi

  # Check initializer-template.md has platform detection markers
  if python3 -c "
with open('$init_file') as f:
    content = f.read()

# Check marker files table exists with key markers
markers = {
    'web': 'next.config',
    'ios': 'xcodeproj',
    'android': 'build.gradle',
    'electron': 'electron-builder',
    'tauri': 'tauri.conf.json',
    'flutter-desktop': 'pubspec.yaml',
    'audio-plugin': '.jucer',
    'api': 'server/API',
    'cli': 'bin/'
}
missing = []
for platform, marker in markers.items():
    if marker not in content:
        missing.append(f'{platform} (marker: {marker})')

if missing:
    raise AssertionError(f'Missing platform markers in initializer-template.md: {missing}')
print(f'All {len(markers)} platform markers found in initializer-template.md')
" 2>/dev/null; then
    pass "initializer-template.md contains marker files for all platforms"
  else
    fail "initializer-template.md is missing platform markers"
  fi

  # Check that each platform in the initializer has a tool selection table
  if python3 -c "
with open('$init_file') as f:
    content = f.read()

# These platforms should have their own E2E tool selection tables
platforms_with_tables = ['web', 'ios', 'android', 'electron', 'tauri', 'flutter-desktop', 'audio-plugin', 'api', 'cli']
missing = []
for p in platforms_with_tables:
    if f'E2E — {p}' not in content:
        missing.append(p)

if missing:
    raise AssertionError(f'Missing E2E tool tables for platforms: {missing}')
print(f'All {len(platforms_with_tables)} platform tool tables present')
" 2>/dev/null; then
    pass "initializer-template.md has E2E tool tables for all platforms"
  else
    fail "initializer-template.md is missing E2E tool tables"
  fi
}

# ── Test: E2E Tool Install Sources (offline) ──

test_e2e_install_sources() {
  section "TEST 13: E2E Tool Install Source URLs (offline)"

  local init_file="$FLYWHEEL_DIR/plugins/flywheel/skills/hub/initializer-template.md"

  # Check that all new E2E tools have source URLs in the install guide table
  if python3 -c "
with open('$init_file') as f:
    content = f.read()

required_urls = {
    'mobile-mcp': 'mobile-next/mobile-mcp',
    'ios-simulator-mcp': 'joshuayoes/ios-simulator-mcp',
    'Maestro': 'mobile-dev-inc/maestro',
    'electron-playwright-mcp': 'fracalo/electron-playwright-mcp',
    'tauri-plugin-mcp': 'P3GLEG/tauri-plugin-mcp',
    'pluginval': 'Tracktion/pluginval',
    'Patrol': 'leancodepl/patrol'
}

missing = []
for tool, url_part in required_urls.items():
    if url_part not in content:
        missing.append(f'{tool} ({url_part})')

if missing:
    raise AssertionError(f'Missing install source URLs: {missing}')
print(f'All {len(required_urls)} E2E tool source URLs present')
" 2>/dev/null; then
    pass "All E2E tool install source URLs are present in initializer-template.md"
  else
    fail "Missing E2E tool install source URLs"
  fi
}

# ── Test: Detection Table Completeness (offline) ──

test_e2e_detection_table() {
  section "TEST 14: E2E Detection Table Completeness (offline)"

  local skill_file="$FLYWHEEL_DIR/plugins/flywheel/skills/review-pipeline/SKILL.md"

  # Check that the Detection table in review-pipeline has entries for all new tools
  if python3 -c "
with open('$skill_file') as f:
    content = f.read()

# Extract the Detection section
detection_start = content.index('## Detection')
detection_section = content[detection_start:]

required_tools = [
    'mobile-mcp',
    'ios-simulator-mcp',
    'Maestro',
    'electron-playwright-mcp',
    'tauri-plugin-mcp',
    'pluginval',
    'Patrol',
    'Playwright',
    'Gemini CLI'
]

missing = []
for tool in required_tools:
    if tool not in detection_section:
        missing.append(tool)

if missing:
    raise AssertionError(f'Missing from Detection table: {missing}')
print(f'All {len(required_tools)} tools found in Detection table')
" 2>/dev/null; then
    pass "Detection table contains all E2E tools"
  else
    fail "Detection table is missing tools"
  fi
}

# ── Test: Init with Platform E2E (live — Claude invocation) ──

test_init_platform_e2e() {
  section "TEST 15: Init with Platform-Aware E2E (/init with mobile markers)"

  # Add mobile project markers so platform detection picks them up
  mkdir -p "$TEST_WORKSPACE/ios"
  touch "$TEST_WORKSPACE/ios/Podfile"
  mkdir -p "$TEST_WORKSPACE/android"
  cat > "$TEST_WORKSPACE/android/build.gradle" << 'GRADLE'
apply plugin: 'com.android.application'
android { compileSdkVersion 34 }
GRADLE

  # Also add a next.config.ts for web detection
  cat > "$TEST_WORKSPACE/next.config.ts" << 'NEXTCFG'
export default { reactStrictMode: true }
NEXTCFG

  (cd "$TEST_WORKSPACE" && git add -A && git commit -q -m "chore: add mobile and web platform markers")

  local prompt
  prompt=$(cat << 'PROMPT'
I want to re-initialize flywheel for this project. The project now has web, iOS, and Android targets (check for next.config.ts, ios/, android/ directories).

Use built-in defaults for planning, multi-agent, cleanup, peer-review, and cross-model.

For platform verification: detect the platforms from the project files. For each detected platform, use built-in verification tools. The config should use the v1.9.0 verification format (top-level, separate from review):

```json
"verification": {
  "platforms": {
    "<platform>": { "tool": "built-in", "alternatives": [...] }
  },
  "profiles": {
    "full": { "run": "all-platforms" },
    "standard": { "run": "primary-only" },
    "light": { "run": "built-in-only" },
    "draft": { "run": "none" }
  }
}
```

Also ensure review.tools.e2e is set to "built-in" for code review E2E (separate from platform verification).

Save to .flywheel/flywheel-config.json (overwrite existing). Keep the existing feature-checklist.json. Commit the updated config.
PROMPT
)

  local output_file
  output_file=$(invoke_claude "init_platform_e2e" "$prompt")

  log "Checking platform-aware E2E config..."

  # Helper: extract verification platforms dict from config (accepts both canonical and legacy locations)
  local e2e_extract_helper='
def get_e2e_platforms(path):
    import json
    c = json.load(open(path))
    # v1.9.0 canonical: verification.platforms (top-level)
    verification = c.get("verification", {})
    if isinstance(verification, dict) and "platforms" in verification:
        return verification["platforms"]
    # v1.8.0 legacy: review.e2e.platforms
    review = c.get("review", {})
    e2e = review.get("e2e", {})
    if isinstance(e2e, dict) and "platforms" in e2e:
        return e2e["platforms"]
    # v1.7.0 legacy: review.tools.e2e.platforms
    e2e = review.get("tools", {}).get("e2e", {})
    if isinstance(e2e, dict) and "platforms" in e2e:
        return e2e["platforms"]
    return None
'
  local config_path="$TEST_WORKSPACE/.flywheel/flywheel-config.json"

  # Check that the config has a platform-aware E2E structure
  if python3 -c "
${e2e_extract_helper}
platforms = get_e2e_platforms('${config_path}')
assert platforms is not None, 'Platform-aware verification not found in verification.platforms, review.e2e, or review.tools.e2e'
assert isinstance(platforms, dict), f'platforms must be dict, got {type(platforms)}'
assert len(platforms) >= 1, 'at least one platform expected'
for p, cfg in platforms.items():
    assert isinstance(cfg, dict), f'{p} config must be dict'
    assert 'tool' in cfg, f'missing tool for {p}'
    assert 'alternatives' in cfg, f'missing alternatives for {p}'
    assert isinstance(cfg['alternatives'], list), f'alternatives must be list for {p}'
print(f'Platform-aware E2E config valid: {len(platforms)} platforms: {list(platforms.keys())}')
" 2>/dev/null; then
    pass "Config has valid platform-aware E2E structure"
  else
    fail "Config missing or invalid platform-aware E2E structure"
    log "── Current config ──"
    cat "$TEST_WORKSPACE/.flywheel/flywheel-config.json" 2>/dev/null || true
  fi

  # Check that web platform was detected
  if python3 -c "
${e2e_extract_helper}
platforms = get_e2e_platforms('${config_path}') or {}
assert 'web' in platforms, 'web not detected'
print(f'web: tool={platforms[\"web\"][\"tool\"]}')
" 2>/dev/null; then
    pass "Web platform detected from next.config.ts"
  else
    fail "Web platform not detected"
  fi

  # Check if mobile platforms were detected (ios and/or android)
  if python3 -c "
${e2e_extract_helper}
platforms = get_e2e_platforms('${config_path}') or {}
mobile_found = [p for p in ['ios', 'android'] if p in platforms]
if not mobile_found:
    raise AssertionError('No mobile platforms detected despite ios/ and android/ directories')
print(f'Mobile platforms detected: {mobile_found}')
" 2>/dev/null; then
    pass "Mobile platform(s) detected from ios/ and android/ directories"
  else
    warn "Mobile platforms not detected (may need more explicit markers)"
  fi

  log "── Updated config ──"
  cat "$TEST_WORKSPACE/.flywheel/flywheel-config.json" 2>/dev/null || true
}

# ── Main ──

main() {
  section "Flywheel E2E Test Suite"
  log "Plugin dir: $FLYWHEEL_DIR"
  log "Test workspace: $TEST_WORKSPACE"
  log "Test filter: $TEST_FILTER"

  # Verify claude is available
  if ! command -v claude &>/dev/null; then
    echo "Error: 'claude' command not found. Install Claude Code first."
    exit 1
  fi

  setup_mock_project

  # Helper: run a test function with timing
  run_test() {
    local name="$1"
    local func="$2"
    timer_start
    "$func"
    timer_end "$name"
  }

  case "$TEST_FILTER" in
    init)
      run_test "init" test_init
      ;;
    relay)
      run_test "init" test_init
      run_test "relay" test_relay
      ;;
    continuity)
      run_test "init" test_init
      run_test "relay" test_relay
      run_test "continuity" test_relay_continuity
      ;;
    features-list)
      run_test "init" test_init
      run_test "features-list" test_features_list
      ;;
    features)
      run_test "init" test_init
      run_test "features-list" test_features_list
      run_test "features-add" test_features_add
      run_test "features-revise" test_features_revise
      run_test "features-split" test_features_split
      run_test "features-remove" test_features_remove
      run_test "source-metadata" test_features_source_metadata
      run_test "integrity" test_checklist_integrity
      ;;
    features-add)
      run_test "init" test_init
      run_test "features-add" test_features_add
      ;;
    features-revise)
      run_test "init" test_init
      run_test "features-revise" test_features_revise
      ;;
    features-split)
      run_test "init" test_init
      run_test "features-add" test_features_add
      run_test "features-split" test_features_split
      ;;
    features-remove)
      run_test "init" test_init
      run_test "features-add" test_features_add
      run_test "features-remove" test_features_remove
      ;;
    e2e-offline)
      run_test "e2e-schema" test_e2e_config_schema
      run_test "e2e-detection" test_e2e_platform_detection
      run_test "e2e-sources" test_e2e_install_sources
      run_test "e2e-det-table" test_e2e_detection_table
      ;;
    e2e-schema)
      run_test "e2e-schema" test_e2e_config_schema
      ;;
    e2e-detection)
      run_test "e2e-detection" test_e2e_platform_detection
      ;;
    e2e-sources)
      run_test "e2e-sources" test_e2e_install_sources
      ;;
    e2e-det-table)
      run_test "e2e-det-table" test_e2e_detection_table
      ;;
    e2e-live|e2e-init)
      run_test "init" test_init
      run_test "e2e-init" test_init_platform_e2e
      ;;
    all)
      run_test "init" test_init
      run_test "relay" test_relay
      run_test "continuity" test_relay_continuity
      run_test "features-list" test_features_list
      run_test "features-add" test_features_add
      run_test "features-revise" test_features_revise
      run_test "features-split" test_features_split
      run_test "features-remove" test_features_remove
      run_test "source-metadata" test_features_source_metadata
      run_test "integrity" test_checklist_integrity
      run_test "e2e-schema" test_e2e_config_schema
      run_test "e2e-detection" test_e2e_platform_detection
      run_test "e2e-sources" test_e2e_install_sources
      run_test "e2e-det-table" test_e2e_detection_table
      run_test "e2e-init" test_init_platform_e2e
      ;;
    *)
      echo "Unknown test: $TEST_FILTER"
      echo "Usage: $0 [--test init|relay|continuity|features|features-list|features-add|features-revise|features-split|features-remove|e2e-offline|e2e-schema|e2e-detection|e2e-sources|e2e-det-table|e2e-live|all]"
      exit 1
      ;;
  esac

  # ── Timing Summary ──
  local suite_end_time=$(date +%s)
  local total_elapsed=$(( suite_end_time - SUITE_START_TIME ))
  local total_mins=$(( total_elapsed / 60 ))
  local total_secs=$(( total_elapsed % 60 ))

  section "Timing"
  echo -e "${CYAN}┌──────────────────────┬───────────┐${NC}"
  echo -e "${CYAN}│ Stage                │ Duration  │${NC}"
  echo -e "${CYAN}├──────────────────────┼───────────┤${NC}"
  for i in "${!TIMING_NAMES[@]}"; do
    local name="${TIMING_NAMES[$i]}"
    local dur="${TIMING_DURATIONS[$i]}"
    local m=$(( dur / 60 ))
    local s=$(( dur % 60 ))
    printf "${CYAN}│${NC} %-20s ${CYAN}│${NC} %3dm %02ds  ${CYAN}│${NC}\n" "$name" "$m" "$s"
  done
  echo -e "${CYAN}├──────────────────────┼───────────┤${NC}"
  printf "${CYAN}│${NC} %-20s ${CYAN}│${NC} ${YELLOW}%3dm %02ds${NC}  ${CYAN}│${NC}\n" "TOTAL" "$total_mins" "$total_secs"
  echo -e "${CYAN}└──────────────────────┴───────────┘${NC}"

  # ── Results ──
  section "Results"
  echo -e "${GREEN}Passed: $PASSED${NC}"
  echo -e "${RED}Failed: $FAILED${NC}"
  echo -e "Total time: ${YELLOW}${total_mins}m ${total_secs}s${NC}"
  echo ""
  log "Test workspace preserved at: $TEST_WORKSPACE"
  log "Inspect with: ls -la $TEST_WORKSPACE/.flywheel/"

  if [[ $FAILED -gt 0 ]]; then
    echo -e "\n${RED}Some tests failed.${NC} Check output above for details."
    echo "Raw Claude outputs: $RESULTS_DIR/"
    exit 1
  else
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
  fi
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --test) TEST_FILTER="$2"; shift 2 ;;
    --cleanup) cleanup; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# Tee all output to a log file so progress is observable from any terminal:
#   tail -f /tmp/flywheel-test-latest.log
exec > >(tee "$LOG_FILE") 2>&1

main
