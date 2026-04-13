#!/usr/bin/env bash
# lib/presets.sh — Preset resolution and merge logic for brain-backup
set -euo pipefail

# Preset directory (installed location)
BB_PRESET_DIR="${BB_PRESET_DIR:-$HOME/.local/share/brain-backup/presets}"

# Fallback: check relative to script (dev mode)
if [[ ! -d "$BB_PRESET_DIR" ]]; then
  BB_PRESET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../presets" && pwd 2>/dev/null || echo "$BB_PRESET_DIR")"
fi

# All known preset names
BB_KNOWN_PRESETS=(openclaw hermes claude-code codex windsurf)

#######################################
# List available preset names
# Globals:
#   BB_KNOWN_PRESETS
# Arguments:
#   None
# Outputs:
#   Preset names, one per line
#######################################
bb::presets::list() {
  printf '%s\n' "${BB_KNOWN_PRESETS[@]}"
}

#######################################
# Check if a preset name is known
# Globals:
#   BB_KNOWN_PRESETS
# Arguments:
#   $1 - preset name
# Returns:
#   0 if known, 1 if not
#######################################
bb::presets::exists() {
  local name="$1"
  local p
  for p in "${BB_KNOWN_PRESETS[@]}"; do
    [[ "$p" == "$name" ]] && return 0
  done
  return 1
}

#######################################
# Load a preset YAML file
# Globals:
#   BB_PRESET_DIR
# Arguments:
#   $1 - preset name
# Outputs:
#   Preset YAML to stdout
# Returns:
#   1 if preset not found
#######################################
bb::presets::load() {
  local name="$1"
  local file="$BB_PRESET_DIR/${name}.yaml"

  if [[ ! -f "$file" ]]; then
    bb::output::error "Unknown preset: '${name}'. Available: $(bb::presets::list | tr '\n' ' ')"
    return 1
  fi

  cat "$file"
}

#######################################
# Get preset field value
# Arguments:
#   $1 - preset name
#   $2 - yq path (e.g. '.paths')
# Outputs:
#   Value to stdout
#######################################
bb::presets::get() {
  local name="$1"
  local path="$2"
  bb::presets::load "$name" | yq eval "${path}" -
}

#######################################
# Resolve a profile's final paths and excludes
# Preset merge rules (spec section 7):
#   - Profile paths OVERRIDE preset paths (not merge)
#   - Profile excludes MERGE with preset excludes (additive)
#   - Profile include removes items from merged exclude list
# Globals:
#   None
# Arguments:
#   $1 - config YAML (full config)
#   $2 - profile index (0-based)
# Outputs:
#   Two lines: paths (JSON array), excludes (JSON array)
#######################################
bb::presets::resolve() {
  local config="$1"
  local idx="$2"

  local name preset_name
  name=$(echo "$config" | yq eval ".profiles[$idx].name" -)
  preset_name=$(echo "$config" | yq eval ".profiles[$idx].preset" -)

  local paths_json excludes_json

  # If preset specified, load defaults
  if [[ -n "$preset_name" && "$preset_name" != "null" ]]; then
    if ! bb::presets::exists "$preset_name"; then
      bb::output::error "Unknown preset: '${preset_name}'. Available: $(bb::presets::list | tr '\n' ' ')"
      return 1
    fi

    local preset_paths preset_excludes
    preset_paths=$(bb::presets::get "$preset_name" '.paths')
    preset_excludes=$(bb::presets::get "$preset_name" '.exclude')

    # Paths: profile overrides preset
    local profile_paths_len
    profile_paths_len=$(echo "$config" | yq eval ".profiles[$idx].paths | length" -)
    if [[ "$profile_paths_len" != "0" && "$profile_paths_len" != "null" ]]; then
      paths_json=$(echo "$config" | yq eval -o=json -c ".profiles[$idx].paths" -)
    else
      # Use preset paths (convert YAML array to JSON)
      paths_json=$(echo "$preset_paths" | yq eval -o=json -c '.' -)
    fi

    # Excludes: merge preset + profile (additive)
    local preset_excludes_json profile_excludes_json
    preset_excludes_json=$(echo "$preset_excludes" | yq eval -o=json -c '.' -)
    profile_excludes_json=$(echo "$config" | yq eval -o=json -c ".profiles[$idx].exclude // []" -)
    excludes_json=$(echo "{\"a\":$preset_excludes_json,\"b\":$profile_excludes_json}" | jq -r '.a + .b | unique')

    # Apply include: remove items from merged excludes
    local includes_json
    includes_json=$(echo "$config" | yq eval -o=json -c ".profiles[$idx].include // []" -)
    if [[ "$includes_json" != "[]" && "$includes_json" != "null" ]]; then
      excludes_json=$(echo "{\"excludes\":$excludes_json,\"includes\":$includes_json}" | jq -r '.excludes - .includes')
    fi
  else
    # No preset — use profile paths/excludes directly
    paths_json=$(echo "$config" | yq eval -o=json -c ".profiles[$idx].paths" -)
    excludes_json=$(echo "$config" | yq eval -o=json -c ".profiles[$idx].exclude // []" -)
  fi

  # Expand ~ in paths to $HOME
  paths_json=$(echo "$paths_json" | jq -r --arg home "$HOME" '.[] | sub("~"; $home)' | jq -R . | jq -sc .)

  # Compact JSON for reliable line-by-line reading
  paths_json=$(echo "$paths_json" | jq -c '. // []' 2>/dev/null || echo '[]')
  excludes_json=$(echo "$excludes_json" | jq -c '. // []' 2>/dev/null || echo '[]')

  printf '%s\n' "$paths_json"
  printf '%s\n' "$excludes_json"
}

#######################################
# Resolve all profiles and return deduplicated paths + merged excludes
# Globals:
#   None
# Arguments:
#   $1 - config YAML
#   $2 - (optional) profile name filter — only resolve this profile
# Outputs:
#   Two lines: all-paths (JSON array, deduplicated), all-excludes (JSON array, merged)
#######################################
bb::presets::resolve_all() {
  local config="$1"
  local filter="${2:-}"

  local count
  count=$(echo "$config" | yq eval '.profiles | length' -)

  local all_paths="[]"
  local all_excludes="[]"

  local i=0
  while [[ $i -lt $count ]]; do
    local name
    name=$(echo "$config" | yq eval ".profiles[$i].name" -)

    # If filter specified, skip non-matching profiles
    if [[ -n "$filter" && "$name" != "$filter" ]]; then
      i=$((i + 1))
      continue
    fi

    local paths_json excludes_json
    {
      read -r paths_json
      read -r excludes_json
    } < <(bb::presets::resolve "$config" "$i")

    # Merge paths (deduplicate) and excludes (deduplicate)
    all_paths=$(echo "{\"a\":$all_paths,\"b\":$paths_json}" | jq -c '.a + .b | unique')
    all_excludes=$(echo "{\"a\":$all_excludes,\"b\":$excludes_json}" | jq -c '.a + .b | unique')

    i=$((i + 1))
  done

  echo "$all_paths" | jq -c .
  echo "$all_excludes" | jq -c .
}

#######################################
# Filter paths to only those that exist on disk
# Per spec: non-existent paths are skipped silently
# Globals:
#   None
# Arguments:
#   $1 - JSON array of paths
# Outputs:
#   Filtered JSON array of existing paths
#######################################
bb::presets::filter_existing() {
  local paths_json="$1"
  local existing="[]"

  local path
  while IFS= read -r path; do
    if [[ -d "$path" ]]; then
      existing=$(echo "$existing" | jq --arg p "$path" '. + [$p]')
    fi
  done < <(echo "$paths_json" | jq -r '.[]')

  echo "$existing"
}
