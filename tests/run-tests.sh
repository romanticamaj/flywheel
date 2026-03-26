#!/usr/bin/env bash
set -euo pipefail

# ── Flywheel E2E Test Harness ──
# Tests the flywheel skill by invoking Claude Code in print mode
# against a mock project with real prompts.
#
# Usage: ./tests/run-tests.sh [--test <test_name>]
#   --test init        Run only the init test
#   --test relay       Run only the relay test
#   --test all         Run all tests (default)

FLYWHEEL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_WORKSPACE="/tmp/flywheel-test-$(date +%s)"
RESULTS_DIR="$TEST_WORKSPACE/.test-results"
PASSED=0
FAILED=0
TEST_FILTER="${2:-all}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log()  { echo -e "${CYAN}[flywheel-test]${NC} $*"; }
pass() { echo -e "${GREEN}  ✓ $*${NC}"; ((PASSED++)); }
fail() { echo -e "${RED}  ✗ $*${NC}"; ((FAILED++)); }
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

invoke_claude() {
  local test_name="$1"
  local prompt="$2"
  local output_file="$RESULTS_DIR/${test_name}.txt"
  local json_file="$RESULTS_DIR/${test_name}.json"

  log "Invoking Claude Code for test: $test_name"

  # Run Claude Code in print mode with flywheel plugin
  # --dangerously-skip-permissions to avoid interactive prompts in CI
  # --plugin-dir to load the flywheel skill
  # --output-format json to get structured output
  set +e
  claude -p "$prompt" \
    --plugin-dir "$FLYWHEEL_DIR" \
    --dangerously-skip-permissions \
    --output-format json \
    --no-session-persistence \
    --model sonnet \
    --max-budget-usd 1.00 \
    2>"$RESULTS_DIR/${test_name}.stderr" \
    > "$json_file"
  local exit_code=$?
  set -e

  if [[ $exit_code -ne 0 ]]; then
    warn "Claude exited with code $exit_code for test: $test_name"
    cat "$RESULTS_DIR/${test_name}.stderr" 2>/dev/null || true
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

1. "Health endpoint" (priority 1): Add a /health endpoint that returns {"status":"ok","uptime":<seconds>}. Acceptance criteria: GET /health returns 200 with JSON body containing status and uptime fields.

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
Start a flywheel coding agent session. Follow the 9-step loop from the coding-agent-template.

Important constraints for this test:
- For ALL review layers, use built-in defaults (do not try to invoke gstack or superpowers — they are not installed).
- Skip the cross-model review layer (it requires external tools).
- For E2E, just run "npm test" and "npm run build" as the built-in smoke test.
- Commit your changes when done.
- Output the compliance table at the end.

Pick the highest-priority feature from the checklist and implement it.
PROMPT
)

  local output_file
  output_file=$(invoke_claude "relay" "$prompt")

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
completed = [f for f in c['features'] if f['status'] == 'completed']
if completed:
    print(f'Completed: {completed[0][\"id\"]} — {completed[0][\"title\"]}')
    assert completed[0].get('completed_by_session') is not None, 'missing completed_by_session'
else:
    raise AssertionError('No completed features')
" 2>/dev/null; then
    pass "Feature checklist updated (at least one feature completed)"
  else
    fail "No feature marked as completed in checklist"
  fi

  # Check that code was actually implemented
  local new_commits
  new_commits=$(cd "$TEST_WORKSPACE" && git log --oneline -5 | grep -i "feat\|health\|user\|log" | head -1)
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
    # Quick check: does the code reference /health with uptime?
    if grep -q "uptime\|health" "$TEST_WORKSPACE/src/index.js" 2>/dev/null; then
      pass "Implementation references health/uptime in source"
    else
      warn "Could not verify health endpoint implementation in source"
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
print(len([f for f in c['features'] if f['status'] == 'completed']))
" 2>/dev/null || echo "0")

  if [[ "$completed_count" -lt 1 ]]; then
    fail "Skipping continuity test — no completed features from first relay"
    return
  fi

  local prompt
  prompt=$(cat << 'PROMPT'
Start a flywheel coding agent session. Follow the 9-step loop.

This is NOT the first session — read the handoff log and checklist first. Pick the next uncompleted feature.

Important constraints:
- Use built-in defaults for all review layers.
- Skip cross-model review.
- For E2E, run "npm test" and "npm run build".
- Commit your changes and write the handoff entry.
- Output the compliance table at the end.
PROMPT
)

  local output_file
  output_file=$(invoke_claude "relay_continuity" "$prompt")

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
completed = [f for f in c['features'] if f['status'] == 'completed']
print(len(completed))
" 2>/dev/null || echo "0")

  if [[ "$new_completed" -ge 2 ]]; then
    pass "$new_completed features now completed (continuity works — picked next feature)"
  else
    fail "Only $new_completed features completed (expected >= 2 after second session)"
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

  case "$TEST_FILTER" in
    init)
      test_init
      ;;
    relay)
      test_init   # relay depends on init
      test_relay
      ;;
    continuity)
      test_init
      test_relay
      test_relay_continuity
      ;;
    all)
      test_init
      test_relay
      test_relay_continuity
      ;;
    *)
      echo "Unknown test: $TEST_FILTER"
      echo "Usage: $0 [--test init|relay|continuity|all]"
      exit 1
      ;;
  esac

  # ── Summary ──
  section "Results"
  echo -e "${GREEN}Passed: $PASSED${NC}"
  echo -e "${RED}Failed: $FAILED${NC}"
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

main
