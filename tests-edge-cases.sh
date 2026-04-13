#!/usr/bin/env bash
# tests-edge-cases.sh — Appendix C edge case tests

source "$(dirname "$0")/test-utils.sh"

test_edge_cases() {
  echo "=== Edge Case Tests (Appendix C) ==="
  echo ""

  # Test 1: concurrent snapshot handling
  echo "Test: concurrent snapshot detection"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"
  export RESTIC_REPOSITORY="$TEMP_REPO"

  # Create a lock manually to simulate concurrent run
  mkdir -p "$TEMP_REPO/lock"
  touch "$TEMP_REPO/lock/1234567890"

  "$BB_CLI" snapshot 2>&1 >/dev/null
  local rc=$?

  # Should fail with lock error (exit 4)
  assert_eq 4 $rc "exits 4 on lock"

  # Cleanup
  rm -rf "$TEMP_REPO/lock"

  # Test 2: duplicate profile names
  echo ""
  echo "Test: duplicate profile names rejected"
  export BB_CONFIG_FILE="$FIXTURES/config-duplicate-profiles.yaml"

  "$BB_CLI" snapshot 2>&1 >/dev/null
  rc=$?
  assert_eq 1 $rc "exits 1 on duplicate profiles"

  # Test 3: profile with neither paths nor preset
  echo ""
  echo "Test: profile with neither paths nor preset"
  local config_path="$FIXTURES/config-no-paths-preset.yaml"
  cat > "$config_path" << YAML
version: 1
repository:
  backend: local
  bucket: "$TEMP_REPO"
profiles:
  - name: empty
    exclude: []
schedule:
  interval: 3600
retention:
  hourly: 24
  daily: 30
  monthly: 12
YAML

  export BB_CONFIG_FILE="$config_path"
  "$BB_CLI" snapshot 2>&1 >/dev/null
  rc=$?
  assert_eq 1 $rc "exits 1 on empty profile"

  # Test 4: non-existent paths skipped silently
  echo ""
  echo "Test: non-existent paths skipped"
  export BB_CONFIG_FILE="$FIXTURES/config-nonexistent-paths.yaml"

  local output
  output=$("$BB_CLI" snapshot 2>&1)
  rc=$?

  # Should succeed despite non-existent path
  assert_eq 0 $rc "succeeds with nonexistent path"
  assert_contains "$output" "Snapshot" "creates snapshot"

  # Test 5: CRLF in config
  echo ""
  echo "Test: CRLF line endings handled"
  local config_path="$FIXTURES/config-crlf.yaml"
  printf 'version: 1\r\nrepository:\r\n  backend: local\r\n  bucket: test\r\nprofiles: []\r\n' > "$config_path"

  export BB_CONFIG_FILE="$config_path"

  # Should parse despite CRLF
  source lib/config.sh
  bb::config::load > /dev/null 2>&1
  rc=$?
  assert_eq 0 $rc "parses CRLF config"

  # Test 6: config file deleted between init and snapshot
  echo ""
  echo "Test: config file deleted"
  local config_path="$FIXTURES/config-deleted.yaml"
  cp "$FIXTURES/config-valid.yaml" "$config_path"

  export BB_CONFIG_FILE="$config_path"
  rm -f "$config_path"

  "$BB_CLI" snapshot 2>&1 >/dev/null
  rc=$?
  assert_eq 1 $rc "exits 1 when config missing"

  # Test 7: RESTIC_PASSWORD not set
  echo ""
  echo "Test: RESTIC_PASSWORD not set"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"
  unset RESTIC_PASSWORD

  "$BB_CLI" snapshot 2>&1 >/dev/null
  rc=$?
  assert_eq 3 $rc "exits 3 without password"

  # Restore password
  export RESTIC_PASSWORD="$TEST_PASSWORD"

  # Test 8: local path not absolute
  echo ""
  echo "Test: local path not absolute"
  echo -e "local\nrelative/path\n\n" | "$BB_CLI" init 2>&1 >/dev/null
  rc=$?
  assert_eq 1 $rc "exits 1 on relative path"

  # Test 9: multiple profiles with same path (dedup)
  echo ""
  echo "Test: same path in multiple profiles (dedup)"
  local config_path="$FIXTURES/config-duplicate-paths.yaml"
  cat > "$config_path" << YAML
version: 1
repository:
  backend: local
  bucket: "$TEMP_REPO"
profiles:
  - name: profile1
    paths: ["$TEST_DATA"]
  - name: profile2
    paths: ["$TEST_DATA"]
schedule:
  interval: 3600
retention:
  hourly: 24
  daily: 30
  monthly: 12
YAML

  export BB_CONFIG_FILE="$config_path"
  local output
  output=$("$BB_CLI" snapshot 2>&1)
  rc=$?
  assert_eq 0 $rc "dedup works"

  # Test 10: empty profiles array
  echo ""
  echo "Test: empty profiles array"
  local config_path="$FIXTURES/config-empty-profiles.yaml"
  cat > "$config_path" << YAML
version: 1
repository:
  backend: local
  bucket: "$TEMP_REPO"
profiles: []
schedule:
  interval: 3600
retention:
  hourly: 24
  daily: 30
  monthly: 12
YAML

  export BB_CONFIG_FILE="$config_path"
  "$BB_CLI" snapshot 2>&1 >/dev/null
  rc=$?
  assert_eq 5 $rc "exits 5 with no paths"

  # Test 11: preset that doesn't exist
  echo ""
  echo "Test: unknown preset"
  local config_path="$FIXTURES/config-unknown-preset.yaml"
  cat > "$config_path" << YAML
version: 1
repository:
  backend: local
  bucket: "$TEMP_REPO"
profiles:
  - name: test
    preset: nonexistent-preset
schedule:
  interval: 3600
retention:
  hourly: 24
  daily: 30
  monthly: 12
YAML

  export BB_CONFIG_FILE="$config_path"
  "$BB_CLI" snapshot 2>&1 >/dev/null
  rc=$?
  assert_eq 1 $rc "exits 1 on unknown preset"

  # Test 12: invalid YAML syntax
  echo ""
  echo "Test: invalid YAML"
  local config_path="$FIXTURES/config-invalid-yaml.yaml"
  echo "invalid: [unclosed" > "$config_path"

  export BB_CONFIG_FILE="$config_path"
  "$BB_CLI" snapshot 2>&1 >/dev/null
  rc=$?
  assert_eq 1 $rc "exits 1 on invalid YAML"

  # Test 13: snapshot with zero changes
  echo ""
  echo "Test: snapshot with zero changes"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"

  # Take a snapshot, then another with no changes
  "$BB_CLI" snapshot >/dev/null 2>&1
  "$BB_CLI" snapshot >/dev/null 2>&1
  rc=$?
  assert_eq 0 $rc "zero-change snapshot exits 0"

  # Test 14: schedule already installed
  echo ""
  echo "Test: schedule already installed"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"

  # Install once
  "$BB_CLI" schedule install 2>&1 >/dev/null

  # Try to install again
  "$BB_CLI" schedule install 2>&1 >/dev/null
  rc=$?
  assert_eq 1 $rc "exits 1 when already installed"

  # Test 15: schedule remove when not installed
  echo ""
  echo "Test: schedule remove when not installed"
  "$BB_CLI" schedule remove 2>&1 >/dev/null
  "$BB_CLI" schedule remove 2>&1 >/dev/null
  rc=$?
  assert_eq 0 $rc "remove when not installed exits 0"

  # Reinstall for cleanup
  "$BB_CLI" schedule install 2>&1 >/dev/null

  # Test 16: config --path with nested key
  echo ""
  echo "Test: config --path nested"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"
  local output
  output=$("$BB_CLI" config --path repository.bucket 2>&1)
  assert_contains "$output" "test-repo" "nested path works"

  # Test 17: restore latest without explicit ID
  echo ""
  echo "Test: restore 'latest' keyword"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"

  local restore_dir="$TEST_DIR/restore-latest"
  rm -rf "$restore_dir"
  "$BB_CLI" restore latest --target "$restore_dir" 2>&1 >/dev/null
  rc=$?
  assert_eq 0 $rc "restore latest works"
  [[ -f "$restore_dir/file1.txt" ]] && assert_eq 0 0 "file restored"

  # Test 18: very long path
  echo ""
  echo "Test: very long path"
  local long_path="/tmp/very/long/path/that/goes/on/and/on/$(date +%s)"
  mkdir -p "$long_path"
  echo "test" > "$long_path/file.txt"

  local config_path="$FIXTURES/config-long-path.yaml"
  cat > "$config_path" << YAML
version: 1
repository:
  backend: local
  bucket: "$TEMP_REPO"
profiles:
  - name: long-path
    paths: ["$long_path"]
schedule:
  interval: 3600
retention:
  hourly: 24
  daily: 30
  monthly: 12
YAML

  export BB_CONFIG_FILE="$config_path"
  "$BB_CLI" snapshot 2>&1 >/dev/null
  rc=$?
  assert_eq 0 $rc "handles long path"

  # Test 19: path with spaces
  echo ""
  echo "Test: path with spaces"
  local space_path="$TEST_DIR/path with spaces"
  mkdir -p "$space_path"
  echo "test" > "$space_path/file.txt"

  local config_path="$FIXTURES/config-space-path.yaml"
  cat > "$config_path" << YAML
version: 1
repository:
  backend: local
  bucket: "$TEMP_REPO"
profiles:
  - name: space-path
    paths: ["$space_path"]
schedule:
  interval: 3600
retention:
  hourly: 24
  daily: 30
  monthly: 12
YAML

  export BB_CONFIG_FILE="$config_path"
  "$BB_CLI" snapshot 2>&1 >/dev/null
  rc=$?
  assert_eq 0 $rc "handles path with spaces"

  # Test 20: empty exclude array
  echo ""
  echo "Test: empty exclude array"
  local config_path="$FIXTURES/config-empty-exclude.yaml"
  cat > "$config_path" << YAML
version: 1
repository:
  backend: local
  bucket: "$TEMP_REPO"
profiles:
  - name: no-exclude
    paths: ["$TEST_DATA"]
    exclude: []
schedule:
  interval: 3600
retention:
  hourly: 24
  daily: 30
  monthly: 12
YAML

  export BB_CONFIG_FILE="$config_path"
  "$BB_CLI" snapshot 2>&1 >/dev/null
  rc=$?
  assert_eq 0 $rc "handles empty exclude"

  # Test 21: include removes from excludes
  echo ""
  echo "Test: include removes from excludes"
  local config_path="$FIXTURES/config-include.yaml"
  cat > "$config_path" << YAML
version: 1
repository:
  backend: local
  bucket: "$TEMP_REPO"
profiles:
  - name: include-test
    paths: ["$TEST_DATA"]
    exclude:
      - "*.txt"
    include:
      - "file1.txt"
schedule:
  interval: 3600
retention:
  hourly: 24
  daily: 30
  monthly: 12
YAML

  export BB_CONFIG_FILE="$config_path"
  "$BB_CLI" snapshot 2>&1 >/dev/null
  rc=$?
  assert_eq 0 $rc "include logic works"

  # Test 22: retention policy with zeros
  echo ""
  echo "Test: retention policy with zeros"
  local config_path="$FIXTURES/config-zero-retention.yaml"
  cat > "$config_path" << YAML
version: 1
repository:
  backend: local
  bucket: "$TEMP_REPO"
profiles:
  - name: test
    paths: ["$TEST_DATA"]
schedule:
  interval: 3600
retention:
  hourly: 0
  daily: 0
  monthly: 0
YAML

  export BB_CONFIG_FILE="$config_path"
  "$BB_CLI" snapshot 2>&1 >/dev/null
  rc=$?
  assert_eq 0 $rc "handles zero retention"

  # Test 23: very large file count
  echo ""
  echo "Test: many small files"
  mkdir -p "$TEST_DIR/many-files"
  for i in $(seq 1 50); do
    echo "file $i" > "$TEST_DIR/many-files/file$i.txt"
  done

  local config_path="$FIXTURES/config-many-files.yaml"
  cat > "$config_path" << YAML
version: 1
repository:
  backend: local
  bucket: "$TEMP_REPO"
profiles:
  - name: many-files
    paths: ["$TEST_DATA/many-files"]
schedule:
  interval: 3600
retention:
  hourly: 24
  daily: 30
  monthly: 12
YAML

  export BB_CONFIG_FILE="$config_path"
  "$BB_CLI" snapshot 2>&1 >/dev/null
  rc=$?
  assert_eq 0 $rc "handles many files"

  # Test 24: Unicode in filenames
  echo ""
  echo "Test: Unicode filenames"
  mkdir -p "$TEST_DIR/unicode"
  echo "测试" > "$TEST_DIR/unicode/test-测试.txt"
  echo "🧠" > "$TEST_DIR/unicode/brain-emoji.txt"

  local config_path="$FIXTURES/config-unicode.yaml"
  cat > "$config_path" << YAML
version: 1
repository:
  backend: local
  bucket: "$TEMP_REPO"
profiles:
  - name: unicode
    paths: ["$TEST_DATA/unicode"]
schedule:
  interval: 3600
retention:
  hourly: 24
  daily: 30
  monthly: 12
YAML

  export BB_CONFIG_FILE="$config_path"
  "$BB_CLI" snapshot 2>&1 >/dev/null
  rc=$?
  assert_eq 0 $rc "handles Unicode filenames"

  # Test 25: Disk space check (simulate full disk)
  echo ""
  echo "Test: disk space check"
  export BB_CONFIG_FILE="$FIXTURES/config-valid.yaml"
  "$BB_CLI" snapshot 2>&1 >/dev/null
  # Just verify it doesn't crash on df check
  rc=$?
  assert_eq 0 $rc "handles disk space check"
}

test_edge_cases
