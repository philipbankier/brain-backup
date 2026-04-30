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
  output=$("$BB_CLI" status --json 2>/dev/null)

  # Verify latest snapshot is shown (age < 10 seconds)
  local age
  age=$(echo "$output" | jq -r '.last_snapshot.age_seconds')
  [[ $age -lt 30 ]] && assert_eq 0 0 "latest snapshot shown" || assert_eq 1 0 "latest snapshot shown"

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
  output=$("$BB_CLI" snapshot --json 2>/dev/null)

  # Should be valid JSON (or contain valid JSON)
  local json_rc=0
  echo "$output" | jq '.' > /dev/null 2>&1 || json_rc=$?
  assert_eq 0 $json_rc "JSON parse succeeds"

  # Regression 5: preset resolve compact JSON output
  echo ""
  echo "Test: preset resolve compact JSON (regression)"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"

  # Create config with preset
  local config_path="$FIXTURES/config-preset-merge.yaml"
  cat > "$config_path" << YAML
version: 2
repository:
  backend: local
  path: "$TEMP_REPO"
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
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "$output" != *'""'* ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} no double quotes in size"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} no double quotes in size"
  fi

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
  echo "Test: config path uses renamed directory (regression)"
  # Verify default config path is ~/.config/brain-dump/
  grep -q "brain-dump/config.yaml" brain-dump
  assert_eq 0 $? "config path uses brain-dump"

  # Regression 11: config validate returns non-zero on invalid config
  echo ""
  echo "Test: config validate exit codes (regression)"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"
  "$BB_CLI" config validate >/dev/null 2>&1
  assert_eq 0 $? "valid v2 config passes"

  export BB_CONFIG_FILE="$FIXTURES/config-valid-v1.yaml"
  "$BB_CLI" config validate >/dev/null 2>&1
  assert_eq 0 $? "valid v1 config passes"

  local bad_config="$FIXTURES/config-invalid-v2.yaml"
  cat > "$bad_config" << YAML
version: 2
repository:
  backend: local
  path: "$TEMP_REPO"
profiles:
  - name: test
    paths: ["$TEST_DATA"]
error_handling:
  mode: "bogus"
resource_limits:
  max_memory_mb: -1
YAML
  export BB_CONFIG_FILE="$bad_config"
  "$BB_CLI" config validate >/dev/null 2>&1
  assert_eq 1 $? "invalid v2 config fails"

  # Regression 12: telemetry stats output
  echo ""
  echo "Test: telemetry stats (regression)"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"
  "$BB_CLI" snapshot >/dev/null 2>&1
  output=$("$BB_CLI" telemetry --stats --json 2>&1)
  echo "$output" | jq '.total_snapshots' >/dev/null
  assert_eq 0 $? "telemetry stats JSON valid"

  # Regression 13: errors --clear
  echo ""
  echo "Test: errors clear (regression)"
  mkdir -p "$HOME/.brain-dump/errors"
  echo '{"operation":"test"}' > "$HOME/.brain-dump/errors/test-error.json"
  output=$("$BB_CLI" errors --clear 2>&1)
  assert_contains "$output" "Cleared" "errors clear reports success"

  # Regression 14: resource limit warning
  echo ""
  echo "Test: resource limit warnings (regression)"
  local warn_config="$FIXTURES/config-resource-warning.yaml"
  cat > "$warn_config" << YAML
version: 2
repository:
  backend: local
  path: "$TEMP_REPO"
profiles:
  - name: test
    paths: ["$TEST_DATA"]
resource_limits:
  max_memory_mb: 512
  max_duration_minutes: 30
  max_files_per_profile: 1
YAML
  export BB_CONFIG_FILE="$warn_config"
  output=$("$BB_CLI" snapshot 2>&1)
  assert_contains "$output" "limit: 1" "file-count warning shown"
}

test_regressions
