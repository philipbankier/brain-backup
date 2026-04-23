#!/usr/bin/env bash
# lib/output.sh — Human + JSON output formatting for brain-dump
# Uses jq for JSON output
set -euo pipefail

# Output mode: controlled by --json/--quiet/--verbose flags
BB_JSON_MODE="${BB_JSON_MODE:-false}"
BB_QUIET_MODE="${BB_QUIET_MODE:-false}"
BB_VERBOSE_MODE="${BB_VERBOSE_MODE:-false}"

#######################################
# Print a message to stdout (unless --quiet)
# Globals:
#   BB_QUIET_MODE
# Arguments:
#   $@ - message text
#######################################
bb::output::print() {
  if [[ "$BB_QUIET_MODE" != "true" ]]; then
    echo "$@"
  fi
}

#######################################
# Print a message to stderr (always, even in --quiet)
# Globals:
#   BB_JSON_MODE
# Arguments:
#   $@ - message text
#######################################
bb::output::error() {
  if [[ "$BB_JSON_MODE" == "true" ]]; then
    # JSON errors go to stderr as JSON object
    local msg="$*"
    jq -n --arg msg "$msg" '{"error": $msg}' >&2
  else
    echo "Error: $*" >&2
  fi
}

#######################################
# Print verbose/debug output (only if --verbose)
# Globals:
#   BB_VERBOSE_MODE
# Arguments:
#   $@ - message text
#######################################
bb::output::verbose() {
  if [[ "$BB_VERBOSE_MODE" == "true" ]]; then
    echo "[verbose] $*" >&2
  fi
}

#######################################
# Print JSON to stdout (only in --json mode)
# Globals:
#   BB_JSON_MODE
# Arguments:
#   $1 - JSON string, or pipe JSON to stdin
#######################################
bb::output::json() {
  if [[ "$BB_JSON_MODE" == "true" ]]; then
    if [[ $# -gt 0 ]]; then
      echo "$1"
    else
      cat
    fi
  fi
}

#######################################
# Print success message (human or JSON)
# Globals:
#   BB_JSON_MODE
# Arguments:
#   $1 - JSON data (in json mode)
#   $2 - human message (in human mode)
#######################################
bb::output::success() {
  local json_data="$1"
  local human_msg="$2"

  if [[ "$BB_JSON_MODE" == "true" ]]; then
    echo "$json_data"
  else
    bb::output::print "✅ $human_msg"
  fi
}

#######################################
# Format bytes to human-readable
# Arguments:
#   $1 - bytes (integer)
# Outputs:
#   Human-readable string (e.g. "106 MB")
#######################################
bb::output::human_bytes() {
  local bytes="$1"
  if [[ $bytes -ge 1073741824 ]]; then
    jq -n --argjson b "$bytes" '$b / 1073741824 | floor * 1.0 + ($b % 1073741824) / 1073741824 | . * 100 | floor / 100 | tostring + " GB"' | tr -d '"'
  elif [[ $bytes -ge 1048576 ]]; then
    jq -n --argjson b "$bytes" '($b / 1048576 | floor) * 1.0 + ($b % 1048576 / 1048576) | . * 100 | floor / 100 | tostring + " MB"' | tr -d '"'
  elif [[ $bytes -ge 1024 ]]; then
    jq -n --argjson b "$bytes" '($b / 1024 | floor) | tostring + " KB"' | tr -d '"'
  else
    echo "${bytes} B"
  fi
}

#######################################
# Format seconds to human-readable duration
# Arguments:
#   $1 - seconds (integer or float)
# Outputs:
#   Human-readable string (e.g. "2 hours ago", "5 min")
#######################################
bb::output::human_age() {
  local seconds="$1"
  local secs
  secs=$(jq -n --argjson s "$seconds" '$s | floor')

  if [[ $secs -ge 86400 ]]; then
    local days=$((secs / 86400))
    echo "${days} day(s) ago"
  elif [[ $secs -ge 3600 ]]; then
    local hours=$((secs / 3600))
    echo "${hours} hour(s) ago"
  elif [[ $secs -ge 60 ]]; then
    local mins=$((secs / 60))
    echo "${mins} min(s) ago"
  else
    echo "${secs}s ago"
  fi
}

#######################################
# Format human age with fallback (for cases where seconds might be float)
# Arguments:
#   $1 - seconds (float string from jq)
# Outputs:
#   Human-readable string
#######################################
bb::output::human_age_float() {
  local seconds="$1"
  local secs
  secs=$(jq -n --arg s "$seconds" '$s | tonumber | floor' 2>/dev/null || echo "$seconds")
  bb::output::human_age "$secs"
}

#######################################
# Format snapshot summary (from restic JSON output)
# Globals:
#   BB_JSON_MODE
# Arguments:
#   $1 - restic backup JSON output
#   $2 - pruned count
#   $3 - kept count
#   $4 - profile names (comma-separated)
#######################################
bb::output::snapshot_summary() {
  local restic_json="$1"
  local pruned="${2:-0}"
  local kept="${3:-0}"
  local profiles="${4:-}"

  if [[ "$BB_JSON_MODE" == "true" ]]; then
    # Build full JSON output per spec appendix A
    jq -n \
      --argjson restic "$restic_json" \
      --argjson pruned "$pruned" \
      --argjson kept "$kept" \
      --arg profiles "$profiles" \
      '{
        success: true,
        snapshot_id: $restic.snapshot_id,
        time: (now | todate),
        files_new: $restic.files_new,
        files_changed: $restic.files_changed,
        files_unmodified: $restic.files_unmodified,
        bytes_added: $restic.data_added,
        bytes_stored: $restic.total_bytes_processed,
        duration_seconds: $restic.total_duration,
        profiles: ($profiles | split(",") | map(select(length > 0))),
        pruned: {
          removed: $pruned,
          kept: $kept
        }
      }'
  else
    # Human-readable summary
    local snap_id files_new files_changed bytes_added
    snap_id=$(echo "$restic_json" | jq -r '.snapshot_id // "unknown"')
    files_new=$(echo "$restic_json" | jq -r '.files_new // 0')
    files_changed=$(echo "$restic_json" | jq -r '.files_changed // 0')
    bytes_added=$(echo "$restic_json" | jq -r '.data_added // 0')

    local stored_str
    stored_str=$(bb::output::human_bytes "$bytes_added")

    bb::output::print "✅ Snapshot ${snap_id} | ${files_new} new, ${files_changed} changed | +${stored_str} stored | prune: ${pruned} removed"
  fi
}

#######################################
# Format status output
# Globals:
#   BB_JSON_MODE
# Arguments:
#   $1 - JSON object with all status fields
#######################################
bb::output::status_summary() {
  local status_json="$1"

  if [[ "$BB_JSON_MODE" == "true" ]]; then
    echo "$status_json" | jq '.'
  else
    local reachable backend bucket
    reachable=$(echo "$status_json" | jq -r '.repo_reachable')
    backend=$(echo "$status_json" | jq -r '.backend')
    bucket=$(echo "$status_json" | jq -r '.bucket // "N/A"')

    bb::output::print "Backend: ${backend} (${bucket})"
    bb::output::print "Repo: $([[ "$reachable" == "true" ]] && echo "✅ reachable" || echo "❌ unreachable")"

    local last_time last_id
    last_time=$(echo "$status_json" | jq -r '.last_snapshot.time // "never"')
    last_id=$(echo "$status_json" | jq -r '.last_snapshot.id // "none"')
    local age_human
    age_human=$(echo "$status_json" | jq -r '.last_snapshot.age_human // "N/A"')

    bb::output::print "Last backup: ${last_time} (${age_human})"
    bb::output::print "Last snapshot: ${last_id}"

    local total_snapshots stored_human
    total_snapshots=$(echo "$status_json" | jq -r '.total_snapshots // 0')
    stored_human=$(echo "$status_json" | jq -r '.total_stored_human // "N/A"')
    bb::output::print "Snapshots: ${total_snapshots} | Stored: ${stored_human}"

    local sched_installed sched_interval
    sched_installed=$(echo "$status_json" | jq -r '.schedule.installed')
    sched_interval=$(echo "$status_json" | jq -r '.schedule.interval_human // "N/A"')
    if [[ "$sched_installed" == "true" ]]; then
      bb::output::print "Schedule: ✅ installed (${sched_interval})"
    else
      bb::output::print "Schedule: not installed"
    fi
  fi
}

#######################################
# Format snapshot list as table or JSON
# Globals:
#   BB_JSON_MODE
# Arguments:
#   $1 - JSON array of snapshots (from restic)
#######################################
bb::output::snapshot_list() {
  local snapshots="$1"

  if [[ "$BB_JSON_MODE" == "true" ]]; then
    echo "$snapshots" | jq '.'
  else
    if [[ "$(echo "$snapshots" | jq 'length')" -eq 0 ]]; then
      bb::output::print "No snapshots found."
      return 0
    fi

    # Table header
    bb::output::print "$(printf '%-12s %-22s %-12s %s' 'ID' 'Time' 'Size' 'Tags')"
    bb::output::print "$(printf '%-12s %-22s %-12s %s' '----------' '--------------------' '----------' '----------')"

    # Table rows
    echo "$snapshots" | jq -r '.[] | "\(.short_id // (.id[:8]))\t\(.time)\t\(.summary.total_bytes_processed // 0)\t\(.tags | join(", "))"' | while IFS=$'\t' read -r id time size tags; do
      local size_str
      size_str=$(bb::output::human_bytes "${size:-0}")
      bb::output::print "$(printf '%-12s %-22s %-12s %s' "$id" "$time" "$size_str" "$tags")"
    done
  fi
}

#######################################
# Format doctor check results
# Globals:
#   BB_JSON_MODE
# Arguments:
#   $1 - JSON object with checks array
#######################################
bb::output::doctor_results() {
  local results="$1"

  if [[ "$BB_JSON_MODE" == "true" ]]; then
    echo "$results" | jq '.'
  else
    local total passed failed all_pass
    total=$(echo "$results" | jq -r '.total // (.checks | length)')
    passed=$(echo "$results" | jq -r '.passed // ([.checks[] | select(.status == "pass")] | length)')
    failed=$(echo "$results" | jq -r '.failed // ([.checks[] | select(.status == "fail")] | length)')
    all_pass=$(echo "$results" | jq -r '.all_pass')

    echo ""
    echo "$results" | jq -r '.checks[] | if .status == "pass" then "  ✅ \(.name): \(.detail // .version // "ok")" else "  ❌ \(.name): \(.detail // "failed")" end'
    echo ""
    if [[ "$all_pass" == "true" ]]; then
      echo "  Health Check: PASS (${passed}/${total}) ✅"
    else
      echo "  Health Check: FAIL (${passed}/${total} passed, ${failed} failed) ❌"
    fi
    echo ""
  fi
}
