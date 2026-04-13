#!/usr/bin/env bash
# test-utils.sh — Shared test helpers for brain-dump
set -euo pipefail

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_CLI="$SCRIPT_DIR/brain-dump"
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
  echo "Setting up test environment..."
  rm -rf "$TEST_DIR"
  mkdir -p "$FIXTURES" "$TEST_DATA" "$TEMP_REPO"

  # Create test data
  echo "test content" > "$TEST_DATA/file1.txt"
  echo "more content" > "$TEST_DATA/file2.txt"
  mkdir -p "$TEST_DATA/subdir"
  echo "nested" > "$TEST_DATA/subdir/file3.txt"

  # Create valid config fixture
  cat > "$FIXTURES/config-valid.yaml" << YAML
version: 1
repository:
  backend: local
  bucket: "$TEMP_REPO"
profiles:
  - name: test
    paths:
      - "$TEST_DATA"
schedule:
  interval: 3600
retention:
  hourly: 24
  daily: 30
  monthly: 12
YAML

  # Create other fixtures
  cat > "$FIXTURES/config-missing-version.yaml" << YAML
repository:
  backend: local
  bucket: test
profiles: []
YAML

  cat > "$FIXTURES/config-duplicate-profiles.yaml" << YAML
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

  cat > "$FIXTURES/config-nonexistent-paths.yaml" << YAML
version: 1
repository:
  backend: local
  bucket: "$TEMP_REPO"
profiles:
  - name: test
    paths:
      - "$TEST_DATA"
      - "/nonexistent/path/that/does/not/exist"
schedule:
  interval: 3600
retention:
  hourly: 24
  daily: 30
  monthly: 12
YAML

  # Initialize restic repo
  export RESTIC_REPOSITORY="$TEMP_REPO"
  restic init 2>/dev/null || true

  echo "✓ Test environment ready"
  echo ""
}

teardown_test_env() {
  if [[ "${KEEP_TEST_DIR:-}" != "1" ]]; then
    rm -rf "$TEST_DIR"
  else
    echo ""
    echo "Test artifacts kept at: $TEST_DIR"
  fi
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

reset_counters() {
  TESTS_RUN=0
  TESTS_PASSED=0
  TESTS_FAILED=0
}
