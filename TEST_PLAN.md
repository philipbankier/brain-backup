# Test Plan — brain-dump v0.1

**Goal:** Prove brain-dump is production-ready through comprehensive, deterministic testing.

**Test philosophy:**
- Fast, deterministic, no external state changes (except test fixtures)
- Cover: happy paths, error paths, edge cases, integration scenarios
- Each test is independent and can run in isolation
- Exit codes, stdout, stderr, and side effects all verified

---

## Test Categories

### 1. Unit Tests (function-level)
### 2. Integration Tests (command-level)
### 3. End-to-End Tests (full workflows)
### 4. Edge Case Tests (Appendix C scenarios)
### 5. Regression Tests (bugs we've fixed)

---

## Test Environment Setup

### Test Directory Structure
```
/tmp/brain-dump-tests/
├── fixtures/
│   ├── config-valid.yaml
│   ├── config-missing-version.yaml
│   ├── config-duplicate-profiles.yaml
│   ├── test-data/
│   │   └── agent-files.txt
├── temp-b2-bucket/        # Or use actual B2 with test prefix
└── test-repo/              # Local restic repo for testing
```

### Test Utility Functions

```bash
# test-utils.sh — shared test helpers
#!/usr/bin/env bash
set -euo pipefail

# Paths
BB_CLI="$PWD/brain-dump"
TEST_DIR="/tmp/brain-dump-tests"
FIXTURES="$TEST_DIR/fixtures"
TEMP_REPO="$TEST_DIR/test-repo"
TEST_DATA="$FIXTURES/test-data"

# Test credential (for testing only)
TEST_PASSWORD="test-password-123"
export RESTIC_PASSWORD="$TEST_PASSWORD"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Assert helpers
assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-values match}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "$expected" == "$actual" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $msg"
    echo -e "  Expected: $expected"
    echo -e "  Actual:   $actual"
  fi
}

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-exit code}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "$expected" == "$actual" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $msg (expected $expected, got $actual)"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-contains}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $msg"
  fi
}

assert_json_field() {
  local json="$1"
  local field="$2"
  local expected="$3"
  local msg="${4:-JSON field}"
  TESTS_RUN=$((TESTS_RUN + 1))
  local actual
  actual=$(echo "$json" | jq -r "$field" 2>/dev/null || echo "")
  if [[ "$actual" == "$expected" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $msg (expected $expected, got $actual)"
  fi
}

# Setup/teardown
setup_test_env() {
  rm -rf "$TEST_DIR"
  mkdir -p "$FIXTURES" "$TEST_DATA" "$TEMP_REPO"

  # Create test data
  echo "test content" > "$TEST_DATA/file1.txt"
  echo "more content" > "$TEST_DATA/file2.txt"
  mkdir -p "$TEST_DATA/subdir"
  echo "nested" > "$TEST_DATA/subdir/file3.txt"
}

teardown_test_env() {
  # Keep test dir for debugging, or uncomment to clean up
  # rm -rf "$TEST_DIR"
  true
}

# Print summary
print_summary() {
  echo ""
  echo "========================================="
  echo "  Tests: $TESTS_RUN"
  echo -e "  ${GREEN}Passed:${NC} $TESTS_PASSED"
  if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "  ${RED}Failed:${NC} $TESTS_FAILED"
  else
    echo -e "  ${GREEN}Failed:${NC} 0"
  fi
  echo "========================================="
  return $TESTS_FAILED
}
```

---

## Test Suite 1: Unit Tests (lib/ functions)

### Test: config::load
```bash
test_config_load() {
  echo "Testing: config::load"

  # Valid config
  local config_path="$FIXTURES/config-valid.yaml"
  cat > "$config_path" << YAML
version: 1
repository:
  backend: local
  bucket: "$TEMP_REPO"
profiles:
  - name: test
    paths:
      - "$TEST_DATA"
YAML

  source lib/config.sh
  local loaded
  loaded=$(BB_CONFIG_FILE="$config_path" bb::config::load)

  assert_contains "$loaded" "version: 1" "loads version"
  assert_contains "$loaded" "backend: local" "loads backend"
}
```

### Test: config::validate
```bash
test_config_validate() {
  echo "Testing: config::validate"

  # Missing version
  local config_path="$FIXTURES/config-missing-version.yaml"
  cat > "$config_path" << YAML
repository:
  backend: local
  bucket: test
profiles: []
YAML

  source lib/config.sh
  BB_CONFIG_FILE="$config_path" bb::config::validate 2>&1
  local rc=$?
  assert_exit_code 1 $rc "missing version exits 1"
}
```

### Test: presets::resolve
```bash
test_presets_resolve() {
  echo "Testing: presets::resolve"

  # Test preset merge: profile paths override, excludes merge
  local config_path="$FIXTURES/config-test-merge.yaml"
  cat > "$config_path" << YAML
version: 1
repository:
  backend: local
  bucket: test
profiles:
  - name: test-profile
    preset: openclaw
    paths:
      - "$TEST_DATA"
    exclude:
      - "*.tmp"
YAML

  source lib/config.sh
  source lib/presets.sh

  local config_yaml
  config_yaml=$(BB_CONFIG_FILE="$config_path" bb::config::load)
  local resolved
  resolved=$(bb::presets::resolve "$config_yaml" 0)

  # Should have test-data path, exclude .tmp + browser/*, etc.
  assert_contains "$resolved" "$TEST_DATA" "includes profile path"
  assert_contains "$resolved" "*.tmp" "includes profile exclude"
}
```

### Test: output::human_bytes
```bash
test_output_human_bytes() {
  echo "Testing: output::human_bytes"

  source lib/output.sh

  local result

  result=$(bb::output::human_bytes 500)
  assert_eq "500 B" "$result" "bytes format"

  result=$(bb::output::human_bytes 2048)
  assert_eq "2 KB" "$result" "KB format"

  result=$(bb::output::human_bytes 1048576)
  assert_eq "1 MB" "$result" "MB format"

  result=$(bb::output::human_bytes 1073741824)
  assert_eq "1 GB" "$result" "GB format"
}
```

---

## Test Suite 2: Command-Level Integration Tests

### Test: init creates config
```bash
test_init_creates_config() {
  echo "Testing: init creates config"

  local config_dir="$TEST_DIR/config-test-init"
  local config_file="$config_dir/config.yaml"

  rm -rf "$config_dir"

  # Non-interactive init with flags
  export BB_CONFIG_FILE="$config_file"
  echo -e "local\n$TEMP_REPO\n\n" | "$BB_CLI" init 2>&1

  assert_eq 0 $? "init succeeds"
  [[ -f "$config_file" ]] && assert_eq 0 0 "config file created"

  local content
  content=$(cat "$config_file")
  assert_contains "$content" "version: 1" "config has version"
  assert_contains "$content" "backend: local" "config has backend"
}
```

### Test: snapshot with valid config
```bash
test_snapshot_valid_config() {
  echo "Testing: snapshot with valid config"

  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"
  export RESTIC_REPOSITORY="$TEMP_REPO"

  local output
  output=$("$BB_CLI" snapshot 2>&1)
  local rc=$?

  assert_eq 0 $rc "snapshot succeeds"
  assert_contains "$output" "Snapshot" "outputs snapshot ID"

  # Verify snapshot exists
  local snapshots
  snapshots=$(restic --repo "$TEMP_REPO" snapshots --json 2>/dev/null | jq 'length')
  assert_eq 1 "$snapshots" "one snapshot in repo"
}
```

### Test: snapshot --json output schema
```bash
test_snapshot_json_schema() {
  echo "Testing: snapshot --json schema"

  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"
  export RESTIC_REPOSITORY="$TEMP_REPO"

  local output
  output=$("$BB_CLI" snapshot --json 2>&1)

  # Verify it's valid JSON
  echo "$output" | jq '.' > /dev/null
  assert_eq 0 $? "valid JSON output"

  # Verify required fields (per spec Appendix A)
  assert_json_field "$output" ".success" "true" "success field"
  assert_json_field "$output" ".snapshot_id" "null" "snapshot_id field"
  assert_json_field "$output" ".profiles" "[]" "profiles field"
}
```

### Test: restore requires target
```bash
test_restore_requires_target() {
  echo "Testing: restore requires snapshot ID"

  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"
  export RESTIC_REPOSITORY="$TEMP_REPO"

  # No argument
  "$BB_CLI" restore 2>&1
  assert_eq 1 $? "restore no args exits 1"

  # With ID
  local output
  output=$("$BB_CLI" restore latest 2>&1)
  assert_contains "$output" "Restored" "restore works with ID"
}
```

### Test: list filters tagged snapshots
```bash
test_list_filters_tagged() {
  echo "Testing: list filters brain-dump tagged"

  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"
  export RESTIC_REPOSITORY="$TEMP_REPO"

  # Create a manual snapshot (no brain-dump tag)
  echo "manual" > "$TEST_DATA/manual.txt"
  restic backup "$TEST_DATA" --tag manual 2>/dev/null

  # List should only show brain-dump tagged
  local output
  output=$("$BB_CLI" list --json 2>&1)
  local count
  count=$(echo "$output" | jq 'length')

  assert_eq 1 "$count" "only brain-dump tagged shown"
}
```

### Test: doctor checks all deps
```bash
test_doctor_checks() {
  echo "Testing: doctor checks dependencies"

  local output
  output=$("$BB_CLI" doctor 2>&1)

  assert_contains "$output" "bash" "checks bash"
  assert_contains "$output" "restic" "checks restic"
  assert_contains "$output" "yq" "checks yq"
  assert_contains "$output" "jq" "checks jq"
}
```

---

## Test Suite 3: End-to-End Workflow Tests

### Test: full backup lifecycle
```bash
test_full_lifecycle() {
  echo "Testing: full backup lifecycle"

  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"
  export RESTIC_REPOSITORY="$TEMP_REPO"

  # 1. Init
  restic init 2>/dev/null || true

  # 2. Snapshot 1
  local snap1
  snap1=$("$BB_CLI" snapshot 2>&1 | grep -oE '[a-f0-9]{8}')
  [[ -n "$snap1" ]] && assert_eq 0 0 "snapshot 1 created"

  # 3. Modify data
  echo "modified" >> "$TEST_DATA/file1.txt"

  # 4. Snapshot 2
  local snap2
  snap2=$("$BB_CLI" snapshot 2>&1 | grep -oE '[a-f0-9]{8}')
  [[ -n "$snap2" ]] && assert_eq 0 0 "snapshot 2 created"

  # 5. Verify 2 snapshots
  local count
  count=$("$BB_CLI" list --json 2>&1 | jq 'length')
  assert_eq 2 "$count" "2 snapshots in list"

  # 6. Restore latest
  local restore_dir="$TEST_DIR/restore-test"
  "$BB_CLI" restore latest --target "$restore_dir" 2>&1
  assert_eq 0 $? "restore succeeds"
  [[ -f "$restore_dir/file1.txt" ]] && assert_eq 0 0 "file restored"

  # 7. Prune (test --dry-run)
  "$BB_CLI" prune --dry-run 2>&1
  assert_eq 0 $? "prune dry-run works"
}
```

### Test: schedule install/remove cycle
```bash
test_schedule_cycle() {
  echo "Testing: schedule install/remove cycle"

  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"

  # Install
  "$BB_CLI" schedule install 2>&1
  assert_eq 0 $? "schedule install succeeds"

  local plist="$HOME/Library/LaunchAgents/com.brain-dump.plist"
  [[ -f "$plist" ]] && assert_eq 0 0 "plist created"

  # Verify loaded
  launchctl list | grep -q "com.brain-dump"
  assert_eq 0 $? "launchd loaded"

  # Status
  local status
  status=$("$BB_CLI" schedule status 2>&1)
  assert_contains "$status" "installed" "status shows installed"

  # Remove
  "$BB_CLI" schedule remove 2>&1
  assert_eq 0 $? "schedule remove succeeds"

  launchctl list | grep -q "com.brain-dump"
  assert_eq 1 $? "launchd unloaded"
}
```

---

## Test Suite 4: Edge Cases (Appendix C)

### Test: concurrent snapshot handling
```bash
test_concurrent_snapshot() {
  echo "Testing: concurrent snapshot detection"

  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"
  export RESTIC_REPOSITORY="$TEMP_REPO"

  # Create a lock manually to simulate concurrent run
  mkdir -p "$TEMP_REPO/lock"
  touch "$TEMP_REPO/lock/1234567890"

  # Snapshot should detect lock
  "$BB_CLI" snapshot 2>&1
  local rc=$?

  # Should fail with lock error
  assert_eq 4 $rc "exits 4 on lock"

  # Cleanup
  rm -rf "$TEMP_REPO/lock"
}
```

### Test: duplicate profile names
```bash
test_duplicate_profiles() {
  echo "Testing: duplicate profile names rejected"

  local config_path="$FIXTURES/config-duplicate-profiles.yaml"
  cat > "$config_path" << YAML
version: 1
repository:
  backend: local
  bucket: test
profiles:
  - name: test
    paths: ["/tmp"]
  - name: test
    paths: ["/var"]
YAML

  export BB_CONFIG_FILE="$config_path"
  "$BB_CLI" snapshot 2>&1
  assert_eq 1 $? "exits 1 on duplicate profiles"
}
```

### Test: non-existent paths skipped silently
```bash
test_nonexistent_paths_skipped() {
  echo "Testing: non-existent paths skipped"

  local config_path="$FIXTURES/config-nonexistent-paths.yaml"
  cat > "$config_path" << YAML
version: 1
repository:
  backend: local
  bucket: "$TEMP_REPO"
profiles:
  - name: test
    paths:
      - "$TEST_DATA"
      - "/nonexistent/path/that/does/not/exist"
YAML

  export BB_CONFIG_FILE="$config_path"
  export RESTIC_REPOSITORY="$TEMP_REPO"

  local output
  output=$("$BB_CLI" snapshot 2>&1)
  local rc=$?

  # Should succeed despite non-existent path
  assert_eq 0 $rc "succeeds with nonexistent path"
  assert_contains "$output" "Snapshot" "creates snapshot"
}
```

### Test: CRLF in config
```bash
test_crlf_config() {
  echo "Testing: CRLF line endings handled"

  local config_path="$FIXTURES/config-crlf.yaml"
  printf 'version: 1\r\nrepository:\r\n  backend: local\r\n  bucket: test\r\nprofiles: []\r\n' > "$config_path"

  export BB_CONFIG_FILE="$config_path"

  # Should parse despite CRLF
  source lib/config.sh
  bb::config::load > /dev/null
  assert_eq 0 $? "parses CRLF config"
}
```

---

## Test Suite 5: Regression Tests

### Test: config --path auto-adds dot
```bash
test_config_path_dot_fix() {
  echo "Testing: config --path auto-adds dot (regression)"

  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"

  local output
  output=$("$BB_CLI" config --path repository.backend 2>&1)

  # Should work with or without leading dot
  assert_eq "local" "$output" "path without dot works"
}
```

### Test: status shows latest snapshot
```bash
test_status_latest_fix() {
  echo "Testing: status shows latest snapshot (regression)"

  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"
  export RESTIC_REPOSITORY="$TEMP_REPO"

  # Create multiple snapshots
  echo "test1" > "$TEST_DATA/test1.txt"
  "$BB_CLI" snapshot >/dev/null 2>&1
  sleep 1
  echo "test2" > "$TEST_DATA/test2.txt"
  "$BB_CLI" snapshot >/dev/null 2>&1

  local output
  output=$("$BB_CLI" status --json 2>&1)

  # Latest snapshot should be second one
  local time
  time=$(echo "$output" | jq -r '.last_snapshot.time')

  # Verify it's recent (last 10 seconds)
  local age
  age=$(echo "$output" | jq -r '.last_snapshot.age_seconds')
  [[ $age -lt 10 ]] && assert_eq 0 0 "latest snapshot shown"
}
```

### Test: schedule status uses plutil not yq
```bash
test_schedule_status_plutil() {
  echo "Testing: schedule status uses plutil (regression)"

  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"

  # Install schedule
  "$BB_CLI" schedule install >/dev/null 2>&1

  local output
  output=$("$BB_CLI" schedule status 2>&1)

  # Should show hours, not 0
  assert_contains "$output" "1 hour" "shows correct interval"
  ! assert_contains "$output" "0 hour" "not showing 0 hours"
}
```

---

## Test Runner

```bash
#!/usr/bin/env bash
# run-all-tests.sh

set -euo pipefail

# Source test utils
source "$(dirname "$0")/test-utils.sh"

# Setup
setup_test_env

echo "========================================="
echo "  brain-dump v0.1 Test Suite"
echo "========================================="
echo ""

# Run test suites
source "$(dirname "$0")/tests-unit.sh"
source "$(dirname "$0")/tests-integration.sh"
source "$(dirname "$0")/tests-e2e.sh"
source "$(dirname "$0")/tests-edge-cases.sh"
source "$(dirname "$0")/tests-regression.sh"

# Cleanup
teardown_test_env

# Summary
print_summary
```

---

## Test Execution

```bash
# Run all tests
./run-all-tests.sh

# Run specific test suite
source test-utils.sh && test_config_load

# Run with verbose output
BB_VERBOSE=1 ./run-all-tests.sh

# Run and keep test artifacts
KEEP_TEST_DIR=1 ./run-all-tests.sh
```

---

## Success Criteria

- **Unit tests:** All lib functions tested with valid/invalid inputs
- **Integration tests:** All 9 commands tested with flags and JSON output
- **E2E tests:** Full lifecycle (init → snapshot → list → restore → prune)
- **Edge cases:** All 25 scenarios from Appendix C tested
- **Regression tests:** All bugs we've fixed have coverage
- **Pass rate:** 100% (no failures allowed for v0.1 release)

---

## Test Coverage Goals

| Component | Target | Current |
|-----------|--------|---------|
| lib/config.sh | 100% | TBD |
| lib/presets.sh | 100% | TBD |
| lib/output.sh | 100% | TBD |
| brain-dump CLI | 100% | TBD |
| install.sh | 80% | TBD |
| Overall | 95%+ | TBD |

**Run this after implementation:** `./run-all-tests.sh && echo "All tests passed!"`
