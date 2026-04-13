#!/usr/bin/env bash
# tests-regression.sh — Regression tests for fixed bugs

source "$(dirname "$0")/test-utils.sh"

test_regressions() {
  echo "=== Regression Tests (Bugs We Fixed) ==="
  echo ""

  # Regression 1: config --path auto-adds dot
  echo "Test: config --path auto-adds dot (regression)"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"

  local output
  output=$("$BB_CLI" config --path repository.backend 2>&1)

  # Should work with or without leading dot
  assert_eq "local" "$output" "path without dot works"

  output=$("$BB_CLI" config --path .repository.backend 2>&1)
  assert_eq "local" "$output" "path with dot works"

  # Regression 2: status shows latest snapshot (not oldest)
  echo ""
  echo "Test: status shows latest snapshot (regression)"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"
  export RESTIC_REPOSITORY="$TEMP_REPO"

  # Create multiple snapshots
  echo "test1" > "$TEST_DATA/test1.txt"
  "$BB_CLI" snapshot >/dev/null 2>&1
  sleep 1
  echo "test2" > "$TEST_DATA/test2.txt"
  "$BB_CLI" snapshot >/dev/null 2>&1
  sleep 1
  echo "test3" > "$TEST_DATA/test3.txt"
  "$BB_CLI" snapshot >/dev/null 2>&1

  local output
  output=$("$BB_CLI" status --json 2>&1)

  # Verify latest snapshot is shown (age < 10 seconds)
  local age
  age=$(echo "$output" | jq -r '.last_snapshot.age_seconds')
  [[ $age -lt 10 ]] && assert_eq 0 0 "latest snapshot shown" || assert_eq 1 0 "latest snapshot shown"

  # Regression 3: schedule status uses plutil not yq
  echo ""
  echo "Test: schedule status uses plutil (regression)"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"

  # Install schedule
  "$BB_CLI" schedule install >/dev/null 2>&1

  local output
  output=$("$BB_CLI" schedule status 2>&1)

  # Should show hours, not 0
  assert_contains "$output" "1 hour" "shows correct interval"

  # Regression 4: restic JSON parsing (filter for summary)
  echo ""
  echo "Test: restic JSON summary filtering (regression)"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"

  local output
  output=$("$BB_CLI" snapshot --json 2>&1)

  # Should be valid JSON
  echo "$output" | jq '.' > /dev/null
  assert_eq 0 $? "JSON parse succeeds"

  # Regression 5: preset resolve compact JSON output
  echo ""
  echo "Test: preset resolve compact JSON (regression)"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"

  # Create config with preset
  local config_path="$FIXTURES/config-preset-merge.yaml"
  cat > "$config_path" << YAML
version: 1
repository:
  backend: local
  bucket: "$TEMP_REPO"
profiles:
  - name: openclaw-custom
    preset: openclaw
    paths: ["$TEST_DATA"]
schedule:
  interval: 3600
retention:
  hourly: 24
  daily: 30
  monthly: 12
YAML

  export BB_CONFIG_FILE="$config_path"
  "$BB_CLI" snapshot 2>&1 >/dev/null
  local rc=$?
  assert_eq 0 $rc "preset resolve works"

  # Regression 6: doctor strips control characters
  echo ""
  echo "Test: doctor strips control chars (regression)"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"

  local output
  output=$("$BB_CLI" doctor --json 2>&1)

  # Should be valid JSON
  echo "$output" | jq '.checks' > /dev/null
  assert_eq 0 $? "doctor JSON valid"

  # Regression 7: human_bytes strips quotes
  echo ""
  echo "Test: human_bytes strips quotes (regression)"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"

  local output
  output=$("$BB_CLI" status 2>&1)

  # Should NOT have double quotes around size
  ! assert_contains "$output" '""' "no double quotes in size"

  # Regression 8: snapshot with profile filter
  echo ""
  echo "Test: snapshot --profile filter (regression)"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"

  "$BB_CLI" snapshot --profile test 2>&1 >/dev/null
  local rc=$?
  assert_eq 0 $rc "profile filter works"

  # Regression 9: restore to temp directory
  echo ""
  echo "Test: restore to timestamped temp dir (regression)"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"

  local output
  output=$("$BB_CLI" restore latest 2>&1)
  local rc=$?

  assert_eq 0 $rc "restore succeeds"
  assert_contains "$output" "brain-dump-restore" "uses temp dir name"

  # Regression 10: config path for installed version
  echo ""
  echo "Test: config path backward compatible (regression)"
  # Verify default config path is ~/.config/brain-backup/
  grep -q "brain-backup/config.yaml" brain-dump
  assert_eq 0 $? "config path uses brain-backup"
}

test_regressions
