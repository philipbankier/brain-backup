# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.0] - 2026-04-30

### Added
- **Config v2 schema** with new sections:
  - `error_handling.mode`: Choose between "strict" (fail fast) or "lenient" (continue on per-profile errors)
  - `error_handling.quarantine_errors`: Enable/disable error quarantine
  - `error_handling.quarantine_dir`: Directory for quarantined error files
  - `resource_limits.max_memory_mb`: Memory limit hint (not enforced, for monitoring)
  - `resource_limits.max_duration_minutes`: Maximum backup duration before warning
  - `resource_limits.max_files_per_profile`: File count limit per profile before warning
- **`brain-dump config validate`** subcommand to validate config schema and limits
- **`brain-dump telemetry`** command for viewing backup history:
  - `--last N`: Show last N entries
  - `--query FILTER`: Filter with jq expressions
  - `--stats`: Show summary statistics
  - `--json`: Raw JSON output
- **`brain-dump errors`** command for viewing quarantined errors:
  - `--last N`: Show last N errors
  - `--clear`: Clear all quarantined errors
- **Per-profile backup in lenient mode**: When `error_handling.mode` is "lenient", each profile is backed up separately. Failures are logged to quarantine but don't stop the backup process.
- **Resource limit warnings**: Post-backup warnings when duration or file counts exceed configured limits.
- **Telemetry JSONL recording**: Every snapshot records detailed metrics to `~/.brain-dump/telemetry.jsonl` (30-day retention).
- **Error quarantine**: Failed operations write error details to `~/.brain-dump/errors/*.json` (30-day retention).
- **11-point doctor check**: Enhanced health check including:
  - Bash version
  - Restic, yq, jq versions
  - Config file validity
  - Encryption password
  - Backend credentials
  - Repository reachability
  - Profile paths existence
  - Schedule installation + freshness
  - Disk space

### Changed
- **Config directory renamed**: `~/.config/brain-backup/` → `~/.config/brain-dump/` (v0.2.0)
- **Config schema version**: New installs generate `version: 2` config with `config_schema: "2.0"`
- **Backward compatibility**: v1 configs remain accepted and validated
- **Snapshot output**: Always includes prune statistics (removed/kept counts)
- **Status command**: Shows schedule installation state and last backup age
- **Schedule install**: Uses launchd with proper environment sourcing for credentials

### Fixed
- **Test isolation**: Tests now clear stale restic locks between runs
- **Config path references**: All references updated from `brain-backup` to `brain-dump`
- **JSON output parsing**: Robust parsing of restic forget output (handles both object and array formats)
- **Status latest snapshot**: Now correctly shows the most recent snapshot (not oldest)
- **Schedule status interval**: Uses `plutil` for macOS plist parsing instead of yq
- **Doctor output**: Strips control characters for valid JSON output
- **Human bytes formatting**: Removes extra quotes from formatted byte strings

### Security
- Config file permissions set to 600 (owner read/write only)
- Config directory permissions set to 700 (owner read/write/execute only)
- Telemetry directory permissions set to 700
- Credentials never stored in config or files; must be in environment

### Performance
- Telemetry cleanup runs automatically after each snapshot (30-day retention)
- Error quarantine cleanup runs automatically (30-day retention)
- Preset resolution caches results within single snapshot run

## [0.2.0] - 2026-04-23

### Added
- Config v2 schema support (error_handling, resource_limits)
- Per-profile lenient mode backup
- Telemetry recording and querying
- Error quarantine system
- Enhanced doctor with 11 checks

### Changed
- Config directory renamed to brain-dump

## [0.1.0] - 2026-04-15

### Added
- Initial release
- Basic snapshot/restore/list/status/prune commands
- Config v1 schema
- B2, S3, and local backends
- Agent presets (openclaw, claude-code, codex, hermes, windsurf)
- macOS launchd scheduling
- Basic doctor check
