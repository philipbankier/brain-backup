# brain-dump v0.2.0 — Phase 2: Error Handling, Config Versioning, Resource Limits

Working directory: ~/vic-workspace/brain-backup
Branch: feature/v0.2.0

## Phase 1: Config Versioning

### 1.1 Add version 2 config schema support to init command
- File: `brain-dump` (the main binary)
- In `cmd_init()`, change `version: 1` to `version: 2` in the generated config
- Also add `config_schema: "2.0"` field after the version line
- The generated config should look like:
```yaml
version: 2
config_schema: "2.0"
repository:
  ...
```

### 1.2 Add config validate subcommand
- File: `brain-dump`
- Add a new case in `cmd_config()` for a `validate` subcommand:
```bash
cmd_config() {
  local subcmd="${1:-}"
  case "$subcmd" in
    validate)
      bb::config::validate && echo "✅ Config is valid" || true
      return $? ;;
    show|"")
      # existing logic
```
- Update the router: change `config) cmd_config "$@" ;;` to pass through args
- Update `--help` text for config command

### 1.3 Add error_handling and resource_limits sections to init
- File: `brain-dump`
- In `cmd_init()`, append these blocks to the generated config after the retention block:
```yaml
error_handling:
  mode: "strict"
  quarantine_errors: true
  quarantine_dir: "~/.brain-dump/errors"
resource_limits:
  max_memory_mb: 512
  max_duration_minutes: 30
  max_files_per_profile: 100000
```

## Phase 2: Error Quarantine in Snapshot

### 2.1 Read error_handling config in snapshot command
- File: `brain-dump`
- In `cmd_snapshot()`, after loading config, read error_handling.mode:
```bash
local error_mode
error_mode=$(echo "$config" | yq eval '.error_handling.mode // "strict"' -)
```

### 2.2 Add per-profile error handling
- File: `brain-dump`
- Currently the snapshot command builds all paths into one restic backup call
- Add a loop that backs up each profile separately (so one profile failing doesn't block others in lenient mode)
- In strict mode (default): if any profile fails, fail the whole snapshot
- In lenient mode: log the error to quarantine and continue with next profile
- For both modes: record telemetry with the aggregated results

### 2.3 Add resource limit warnings
- File: `brain-dump`
- After restic backup completes, check:
  - Duration: if > max_duration_minutes, print warning
  - Use `du -sk` on each profile path to check file counts against max_files_per_profile
- Read limits from config:
```bash
local max_duration
max_duration=$(echo "$config" | yq eval '.resource_limits.max_duration_minutes // 30' -)
local max_memory
max_memory=$(echo "$config" | yq eval '.resource_limits.max_memory_mb // 512' -)
local max_files
max_files=$(echo "$config" | yq eval '.resource_limits.max_files_per_profile // 100000' -)
```

## Phase 3: Update Config Validation

### 3.1 Update config.sh to validate v2 fields
- File: `lib/config.sh`
- In `bb::config::validate()`, after the existing retention validation, add validation for v2 optional fields:
  - error_handling.mode must be "strict" or "lenient" (if present)
  - resource_limits values must be positive integers (if present)

## Phase 4: Update the Existing Config

### 4.1 Update the live config file
- File: `~/.config/brain-dump/config.yaml`
- Add the v2 fields to the existing config:
```yaml
version: 2
config_schema: "2.0"
error_handling:
  mode: "strict"
  quarantine_errors: true
  quarantine_dir: "~/.brain-dump/errors"
resource_limits:
  max_memory_mb: 512
  max_duration_minutes: 30
  max_files_per_profile: 100000
```
- Do NOT change existing repository, profiles, schedule, or retention settings

## Testing

After all changes, verify:
1. `brain-dump config validate` returns 0
2. `brain-dump doctor` passes all checks
3. `brain-dump snapshot --dry-run` works
4. `brain-dump snapshot` completes successfully and records telemetry
5. `brain-dump telemetry --stats` shows the new snapshot
6. `brain-dump errors` shows no errors
7. `brain-dump --version` shows v0.2.0
