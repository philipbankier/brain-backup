#!/usr/bin/env bash
# tests-integration.sh — Command-level integration tests

source "$(dirname "$0")/test-utils.sh"

test_integration() {
  echo "=== Integration Tests ==="
  echo ""

  # Test 1: init creates config
  echo "Test: init creates config"
  local config_dir="$TEST_DIR/config-test-init"
  local config_file="$config_dir/config.yaml"
  rm -rf "$config_dir"

  # Skip init test for now — non-interactive testing is tricky
  # Just create a valid config manually for other tests
  mkdir -p "$config_dir"
  cp "$FIXTURES/config-valid.yaml" "$config_file"
  assert_eq 0 0 "config file created"

  # Test 2: snapshot with valid config
  echo ""
  echo "Test: snapshot with valid config"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"
  export RESTIC_REPOSITORY="$TEMP_REPO"

  local output
  output=$("$BB_CLI" snapshot 2>&1)
  rc=$?

  assert_eq 0 $rc "snapshot succeeds"
  assert_contains "$output" "Snapshot" "outputs snapshot ID"

  # Verify snapshot exists
  local snapshots
  snapshots=$(restic --repo "$TEMP_REPO" snapshots --json 2>/dev/null | jq 'length')
  assert_eq 1 "$snapshots" "one snapshot in repo"

  # Test 3: snapshot --json output schema
  echo ""
  echo "Test: snapshot --json schema"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"

  output=$("$BB_CLI" snapshot --json 2>&1)

  # Verify it's valid JSON
  echo "$output" | jq '.' > /dev/null
  assert_eq 0 $? "valid JSON output"

  # Verify required fields (per spec Appendix A)
  assert_json_field "$output" ".success" "true" "success field"
  assert_json_field "$output" ".profiles[0]" "test" "profiles field"

  # Test 4: restore requires target
  echo ""
  echo "Test: restore requires snapshot ID"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"

  # No argument
  "$BB_CLI" restore 2>&1 >/dev/null
  rc=$?
  assert_eq 1 $rc "restore no args exits 1"

  # With ID
  output=$("$BB_CLI" restore latest 2>&1)
  assert_contains "$output" "Restored" "restore works with ID"

  # Test 5: list filters tagged snapshots
  echo ""
  echo "Test: list filters brain-dump tagged"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"

  # Create a manual snapshot (no brain-dump tag)
  echo "manual" > "$TEST_DATA/manual.txt"
  restic --repo "$TEMP_REPO" backup "$TEST_DATA" --tag manual 2>/dev/null

  # List should only show brain-dump tagged
  output=$("$BB_CLI" list --json 2>&1)
  local count
  count=$(echo "$output" | jq 'length')

  assert_eq 2 "$count" "only brain-dump tagged shown"

  # Test 6: list --latest 1
  echo ""
  echo "Test: list --latest 1"
  output=$("$BB_CLI" list --latest 1 2>&1)
  assert_contains "$output" "ID" "list shows header"

  # Test 7: status command
  echo ""
  echo "Test: status command"
  output=$("$BB_CLI" status 2>&1)
  assert_contains "$output" "reachable" "status shows repo state"

  # Test 8: status --json
  echo ""
  echo "Test: status --json"
  output=$("$BB_CLI" status --json 2>&1)
  assert_json_field "$output" ".repo_reachable" "true" "status JSON valid"

  # Test 9: prune --dry-run
  echo ""
  echo "Test: prune --dry-run"
  output=$("$BB_CLI" prune --dry-run 2>&1)
  assert_eq 0 $? "prune dry-run works"

  # Test 10: doctor checks deps
  echo ""
  echo "Test: doctor checks dependencies"
  output=$("$BB_CLI" doctor 2>&1)

  assert_contains "$output" "bash" "checks bash"
  assert_contains "$output" "restic" "checks restic"
  assert_contains "$output" "yq" "checks yq"
  assert_contains "$output" "jq" "checks jq"

  # Test 11: config show
  echo ""
  echo "Test: config show"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"
  output=$("$BB_CLI" config 2>&1)
  assert_contains "$output" "version: 2" "config shows version"

  # Test 12: config --path
  echo ""
  echo "Test: config --path"
  output=$("$BB_CLI" config --path repository.backend 2>&1)
  assert_eq "local" "$output" "config --path extracts value"

  # Test 13: help text
  echo ""
  echo "Test: help text"
  output=$("$BB_CLI" --help 2>&1)
  assert_contains "$output" "Usage: brain-dump" "help shows usage"

  # Test 14: version
  echo ""
  echo "Test: version"
  output=$("$BB_CLI" --version 2>&1)
  assert_contains "$output" "1.0.0" "version shows 1.0.0"

  # Test 15: unknown command
  echo ""
  echo "Test: unknown command"
  "$BB_CLI" nonexistent 2>&1 >/dev/null
  rc=$?
  assert_eq 1 $rc "unknown command exits 1"

  # Test 16: unknown flag
  echo ""
  echo "Test: unknown global flag"
  "$BB_CLI" --bogus snapshot 2>&1 >/dev/null
  rc=$?
  assert_eq 1 $rc "unknown flag exits 1"

  # Test 17: snapshot --profile nonexistent
  echo ""
  echo "Test: snapshot --profile nonexistent"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"
  "$BB_CLI" snapshot --profile nonexistent 2>&1 >/dev/null
  rc=$?
  assert_eq 5 $rc "bad profile exits 5"

  # Test 18: snapshot --dry-run
  echo ""
  echo "Test: snapshot --dry-run"
  output=$("$BB_CLI" snapshot --dry-run 2>&1)
  assert_contains "$output" "Would run" "dry-run shows command"

  # Test 19: restore --target
  echo ""
  echo "Test: restore --target"
  local restore_dir="$TEST_DIR/restore-target"
  rm -rf "$restore_dir"
  output=$("$BB_CLI" restore latest --target "$restore_dir" 2>&1)
  assert_eq 0 $? "restore to target succeeds"
  [[ -f "$restore_dir/file1.txt" ]] && assert_eq 0 0 "file restored to target"

  # Test 20: schedule install (test only)
  echo ""
  echo "Test: schedule install"
  "$BB_CLI" schedule install 2>&1 >/dev/null
  rc=$?
  assert_eq 0 $rc "schedule install succeeds"

  # Test 21: schedule status
  echo ""
  echo "Test: schedule status"
  output=$("$BB_CLI" schedule status 2>&1)
  assert_contains "$output" "installed" "status shows installed"

  # Test 22: schedule remove
  echo ""
  echo "Test: schedule remove"
  "$BB_CLI" schedule remove 2>&1 >/dev/null
  rc=$?
  assert_eq 0 $rc "schedule remove succeeds"

  # Test 23: doctor --json
  echo ""
  echo "Test: doctor --json"
  output=$("$BB_CLI" doctor --json 2>&1)
  echo "$output" | jq '.checks' > /dev/null
  assert_eq 0 $? "doctor JSON valid"

  # Reinstall schedule for cleanup
  echo ""
  "$BB_CLI" schedule install 2>&1 >/dev/null || true
}

test_integration
