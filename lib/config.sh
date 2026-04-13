#!/usr/bin/env bash
# lib/config.sh — Config loading + validation for brain-backup
# Uses yq to parse YAML config file
set -euo pipefail

# Default config path
BB_CONFIG_FILE="${BB_CONFIG_FILE:-$HOME/.config/brain-backup/config.yaml}"

#######################################
# Load and return raw config YAML (strips CRLF)
# Globals:
#   BB_CONFIG_FILE
# Arguments:
#   None
# Outputs:
#   Raw YAML config to stdout
# Returns:
#   1 if config file missing or invalid YAML
#######################################
bb::config::load() {
  if [[ ! -f "$BB_CONFIG_FILE" ]]; then
    bb::output::error "No config found. Run: brain-backup init"
    return 1
  fi

  # Strip CRLF and parse
  local raw
  raw=$(tr -d '\r' < "$BB_CONFIG_FILE" 2>/dev/null)

  if ! echo "$raw" | yq eval '.' - > /dev/null 2>&1; then
    local errmsg
    errmsg=$(echo "$raw" | yq eval '.' - 2>&1)
    bb::output::error "Config error: $errmsg"
    return 1
  fi

  echo "$raw"
}

#######################################
# Get a single config value by yq path
# Globals:
#   None
# Arguments:
#   $1 - yq path expression (e.g. '.repository.backend')
# Outputs:
#   Value to stdout
#######################################
bb::config::get() {
  local path="$1"
  local config
  config=$(bb::config::load) || return 1
  echo "$config" | yq eval "${path}" -
}

#######################################
# Validate the entire config file
# Checks all required fields and rules from spec section 6
# Globals:
#   BB_CONFIG_FILE
# Arguments:
#   None
# Returns:
#   0 if valid, 1 if invalid (prints error)
#######################################
bb::config::validate() {
  local config
  config=$(bb::config::load) || return 1

  # Rule 1: version must be 1
  local version
  version=$(echo "$config" | yq eval '.version' -)
  if [[ "$version" != "1" ]]; then
    bb::output::error "Config missing or invalid: version (must be 1)"
    return 1
  fi

  # Rule 2: repository.backend must be b2, s3, or local
  local backend
  backend=$(echo "$config" | yq eval '.repository.backend' -)
  if [[ -z "$backend" || "$backend" == "null" ]]; then
    bb::output::error "Config missing: repository.backend"
    return 1
  fi
  if [[ "$backend" != "b2" && "$backend" != "s3" && "$backend" != "local" ]]; then
    bb::output::error "Config invalid: repository.backend must be b2, s3, or local (got: $backend)"
    return 1
  fi

  # Rule 3: bucket required for b2/s3
  if [[ "$backend" == "b2" || "$backend" == "s3" ]]; then
    local bucket
    bucket=$(echo "$config" | yq eval '.repository.bucket' -)
    if [[ -z "$bucket" || "$bucket" == "null" ]]; then
      bb::output::error "Config missing: repository.bucket (required for backend: $backend)"
      return 1
    fi
  fi

  # Rule 4: path required for local
  if [[ "$backend" == "local" ]]; then
    local repo_path
    repo_path=$(echo "$config" | yq eval '.repository.path' -)
    if [[ -z "$repo_path" || "$repo_path" == "null" ]]; then
      bb::output::error "Config missing: repository.path (required for backend: local)"
      return 1
    fi
    if [[ "$repo_path" != /* ]]; then
      bb::output::error "Config invalid: repository.path must be absolute (start with /)"
      return 1
    fi
  fi

  # Rule 5: profiles must be non-empty array
  local profiles_len
  profiles_len=$(echo "$config" | yq eval '.profiles | length' -)
  if [[ "$profiles_len" == "0" || "$profiles_len" == "null" ]]; then
    bb::output::error "Config missing: profiles (must have at least one)"
    return 1
  fi

  # Validate each profile
  local names_seen=""
  local i=0
  local count="$profiles_len"
  while [[ $i -lt $count ]]; do
    local name
    name=$(echo "$config" | yq eval ".profiles[$i].name" -)
    if [[ -z "$name" || "$name" == "null" ]]; then
      bb::output::error "Config missing: profiles[$i].name"
      return 1
    fi

    # Rule 6: unique names
    if echo "$names_seen" | grep -qw "$name"; then
      bb::output::error "Duplicate profile name: '$name'. Profile names must be unique."
      return 1
    fi
    names_seen="$names_seen $name"

    # Rule 7: must have paths or preset
    local preset paths_len
    preset=$(echo "$config" | yq eval ".profiles[$i].preset" -)
    paths_len=$(echo "$config" | yq eval ".profiles[$i].paths | length" -)
    if [[ -z "$preset" || "$preset" == "null" ]]; then
      if [[ "$paths_len" == "0" || "$paths_len" == "null" ]]; then
        bb::output::error "Profile '$name' has no paths and no preset. Add at least one."
        return 1
      fi
    fi

    i=$((i + 1))
  done

  # Rule 10: retention values must be non-negative integers (if present)
  local ret_keys=("hourly" "daily" "monthly" "yearly")
  for key in "${ret_keys[@]}"; do
    local val
    val=$(echo "$config" | yq eval ".retention.$key" -)
    if [[ -n "$val" && "$val" != "null" ]]; then
      if ! [[ "$val" =~ ^[0-9]+$ ]]; then
        bb::output::error "Config invalid: retention.$key must be a non-negative integer (got: $val)"
        return 1
      fi
    fi
  done

  return 0
}

#######################################
# Build restic repo URL from config
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Restic repository URL (e.g. b2:bucket:path, s3:endpoint/bucket, /local/path)
#######################################
bb::config::repo_url() {
  local config
  config=$(bb::config::load) || return 1

  local backend
  backend=$(echo "$config" | yq eval '.repository.backend' -)

  case "$backend" in
    b2)
      local bucket
      bucket=$(echo "$config" | yq eval '.repository.bucket' -)
      echo "b2:${bucket}:"
      ;;
    s3)
      local bucket endpoint
      bucket=$(echo "$config" | yq eval '.repository.bucket' -)
      endpoint=$(echo "$config" | yq eval '.repository.endpoint' -)
      if [[ -n "$endpoint" && "$endpoint" != "null" ]]; then
        echo "s3:${endpoint}/${bucket}"
      else
        echo "s3:${bucket}"
      fi
      ;;
    local)
      local repo_path
      repo_path=$(echo "$config" | yq eval '.repository.path' -)
      # Expand ~ and env vars
      eval echo "$repo_path"
      ;;
    *)
      bb::output::error "Unknown backend: $backend"
      return 1
      ;;
  esac
}

#######################################
# Set restic env vars from config
# Must be called before any restic command
# Globals:
#   Sets RESTIC_REPOSITORY, RESTIC_PASSWORD (already must be set)
# Arguments:
#   None
# Returns:
#   3 if credentials missing
#######################################
bb::config::set_restic_env() {
  local config
  config=$(bb::config::load) || return 1

  export RESTIC_REPOSITORY
  RESTIC_REPOSITORY=$(bb::config::repo_url) || return 1

  # RESTIC_PASSWORD must already be in env
  if [[ -z "${RESTIC_PASSWORD:-}" ]]; then
    bb::output::error "RESTIC_PASSWORD not set. Add to ~/.zshenv"
    return 3
  fi

  # Backend-specific credential check
  local backend
  backend=$(echo "$config" | yq eval '.repository.backend' -)

  case "$backend" in
    b2)
      if [[ -z "${B2_ACCOUNT_ID:-}" || -z "${B2_ACCOUNT_KEY:-}" ]]; then
        bb::output::error "B2_ACCOUNT_ID and/or B2_ACCOUNT_KEY not set. Add to ~/.zshenv"
        return 3
      fi
      ;;
    s3)
      if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        bb::output::error "AWS_ACCESS_KEY_ID and/or AWS_SECRET_ACCESS_KEY not set. Add to ~/.zshenv"
        return 3
      fi
      ;;
    local)
      # No extra credentials needed
      ;;
  esac

  return 0
}

#######################################
# Get retention flags for restic forget
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Space-separated retention flags (e.g. "--keep-hourly 24 --keep-daily 30")
#######################################
bb::config::retention_flags() {
  local config
  config=$(bb::config::load) || return 1

  local flags=""
  local ret_keys=("hourly" "daily" "monthly" "yearly")
  for key in "${ret_keys[@]}"; do
    local val
    val=$(echo "$config" | yq eval ".retention.$key" -)
    if [[ -n "$val" && "$val" != "null" && "$val" != "0" ]]; then
      flags="$flags --keep-$key $val"
    fi
  done

  echo "$flags"
}
