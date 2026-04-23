#!/usr/bin/env bash
# lib/telemetry.sh — Structured telemetry for brain-dump
# Writes JSONL telemetry after each operation
set -euo pipefail

# Telemetry state directory
BB_TELEMETRY_DIR="${HOME}/.brain-dump"
BB_TELEMETRY_FILE="${BB_TELEMETRY_DIR}/telemetry.jsonl"
BB_ERRORS_DIR="${BB_TELEMETRY_DIR}/errors"

#######################################
# Ensure telemetry directories exist
# Globals:
#   BB_TELEMETRY_DIR, BB_TELEMETRY_FILE, BB_ERRORS_DIR
#######################################
bb::telemetry::init() {
  mkdir -p "$BB_TELEMETRY_DIR" "$BB_ERRORS_DIR"
  chmod 700 "$BB_TELEMETRY_DIR" 2>/dev/null || true
}

#######################################
# Append a telemetry entry
# Globals:
#   BB_TELEMETRY_FILE
# Arguments:
#   $1 - JSON object with telemetry data
#######################################
bb::telemetry::record() {
  bb::telemetry::init
  local entry="$1"
  echo "$entry" >> "$BB_TELEMETRY_FILE"
}

#######################################
# Record a snapshot telemetry entry
# Globals:
#   None
# Arguments:
#   $1 - snapshot_id
#   $2 - duration_seconds
#   $3 - files_new
#   $4 - files_changed
#   $5 - files_unmodified
#   $6 - bytes_added
#   $7 - bytes_stored
#   $8 - exit_code
#   $9 - profiles (comma-separated)
#######################################
bb::telemetry::record_snapshot() {
  local snap_id="${1:-unknown}"
  local duration="${2:-0}"
  local files_new="${3:-0}"
  local files_changed="${4:-0}"
  local files_unmodified="${5:-0}"
  local bytes_added="${6:-0}"
  local bytes_stored="${7:-0}"
  local exit_code="${8:-0}"
  local profiles="${9:-}"
  local pruned="${10:-0}"

  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  bb::telemetry::record "$(jq -n \
    --arg ts "$ts" \
    --arg snap_id "$snap_id" \
    --argjson duration "$duration" \
    --argjson files_new "$files_new" \
    --argjson files_changed "$files_changed" \
    --argjson files_unmodified "$files_unmodified" \
    --argjson bytes_added "$bytes_added" \
    --argjson bytes_stored "$bytes_stored" \
    --argjson exit_code "$exit_code" \
    --arg profiles "$profiles" \
    --argjson pruned "$pruned" \
    '{
      type: "snapshot",
      timestamp: $ts,
      snapshot_id: $snap_id,
      duration_seconds: $duration,
      files_new: $files_new,
      files_changed: $files_changed,
      files_unmodified: $files_unmodified,
      bytes_added: $bytes_added,
      bytes_stored: $bytes_stored,
      exit_code: $exit_code,
      profiles: ($profiles | split(",") | map(select(length > 0))),
      pruned: $pruned
    }')"
}

#######################################
# Record an error to quarantine
# Globals:
#   BB_ERRORS_DIR
# Arguments:
#   $1 - operation (snapshot, restore, prune)
#   $2 - error message
#   $3 - exit code
#######################################
bb::telemetry::record_error() {
  bb::telemetry::init
  local operation="${1:-unknown}"
  local message="${2:-unknown error}"
  local code="${3:-1}"
  local ts
  ts=$(date +"%Y%m%d-%H%M%S")

  local err_file="${BB_ERRORS_DIR}/${operation}-${ts}.json"
  jq -n \
    --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg op "$operation" \
    --arg msg "$message" \
    --argjson code "$code" \
    '{
      timestamp: $ts,
      operation: $op,
      error: $msg,
      exit_code: $code
    }' > "$err_file"
}

#######################################
# Query telemetry entries
# Globals:
#   BB_TELEMETRY_FILE
# Arguments:
#   $1 - max entries (0 = all)
#   $2 - jq filter expression (optional)
# Outputs:
#   Filtered JSONL entries
#######################################
bb::telemetry::query() {
  local max_entries="${1:-0}"
  local filter="${2:-.}"

  if [[ ! -f "$BB_TELEMETRY_FILE" ]]; then
    echo "[]"
    return 0
  fi

  local result
  result=$(cat "$BB_TELEMETRY_FILE" | jq -c 'select(.)' 2>/dev/null || true)

  if [[ -n "$filter" && "$filter" != "." ]]; then
    result=$(echo "$result" | jq -c "select($filter)" 2>/dev/null || true)
  fi

  if [[ "$max_entries" -gt 0 ]]; then
    result=$(echo "$result" | tail -n "$max_entries")
  fi

  if [[ -n "$result" ]]; then
    echo "$result"
  else
    echo "[]"
  fi
}

#######################################
# Clean up old telemetry entries
# Globals:
#   BB_TELEMETRY_FILE
# Arguments:
#   $1 - retention days (default: 30)
#######################################
bb::telemetry::cleanup() {
  local retention_days="${1:-30}"

  if [[ ! -f "$BB_TELEMETRY_FILE" ]]; then
    return 0
  fi

  local cutoff
  cutoff=$(date -u -v-"${retention_days}d" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "${retention_days} days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || return 0)

  local tmp_file
  tmp_file=$(mktemp)
  cat "$BB_TELEMETRY_FILE" | jq -c --arg cutoff "$cutoff" 'select(.timestamp >= $cutoff)' > "$tmp_file" 2>/dev/null
  mv "$tmp_file" "$BB_TELEMETRY_FILE"
}

#######################################
# Clean up old error files
# Globals:
#   BB_ERRORS_DIR
# Arguments:
#   $1 - retention days (default: 30)
#######################################
bb::telemetry::cleanup_errors() {
  local retention_days="${1:-30}"

  if [[ ! -d "$BB_ERRORS_DIR" ]]; then
    return 0
  fi

  find "$BB_ERRORS_DIR" -name "*.json" -mtime +"${retention_days}" -delete 2>/dev/null || true
}

#######################################
# Get telemetry stats (summary)
# Globals:
#   BB_TELEMETRY_FILE
# Outputs:
#   JSON object with summary stats
#######################################
bb::telemetry::stats() {
  if [[ ! -f "$BB_TELEMETRY_FILE" ]]; then
    jq -n '{total_snapshots: 0, total_errors: 0, total_bytes_added: 0, avg_duration_seconds: 0}'
    return 0
  fi

  cat "$BB_TELEMETRY_FILE" | jq -s '{
    total_snapshots: [.[].type | select(. == "snapshot")] | length,
    total_errors: [.[].exit_code | select(. != 0)] | length,
    total_bytes_added: [.[].bytes_added // 0] | add,
    avg_duration_seconds: ([.[].duration_seconds // 0] | add / length * 100 | floor / 100),
    last_snapshot: (map(select(.type == "snapshot")) | last | .timestamp // "never"),
    last_error: (map(select(.exit_code != 0)) | last | .timestamp // "never")
  }'
}
