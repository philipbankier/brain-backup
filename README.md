# 🧠 brain-dump

![Version](https://img.shields.io/badge/version-1.0.0-blue)

Opinionated, encrypted backup for AI agent memory.

Wraps [restic](https://restic.net/) with sane defaults for backing up AI agent
memory directories to S3-compatible storage (Backblaze B2, AWS S3, local).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/philipbankier/brain-dump/main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/philipbankier/brain-dump.git
cd brain-dump
chmod +x brain-dump
export PATH="$PWD:$PATH"
```

## Requirements

| Dependency | Version | Install |
|-----------|---------|---------|
| bash | 3.2+ | pre-installed on macOS |
| [restic](https://restic.net/) | 0.16+ | `brew install restic` |
| [yq](https://github.com/mikefarah/yq) | 4.0+ | `brew install yq` |
| [jq](https://stedolan.github.io/jq/) | 1.6+ | `brew install jq` |

## Quick Start

```bash
# 1. Set credentials (add to ~/.zshenv or ~/.bashrc)
export RESTIC_PASSWORD="your-strong-password"
export B2_ACCOUNT_ID="your-b2-key-id"
export B2_ACCOUNT_KEY="your-b2-application-key"

# 2. Initialize
brain-dump init

# 3. Take your first backup
brain-dump snapshot

# 4. Check health
brain-dump status

# 5. Schedule hourly backups (macOS)
brain-dump schedule install
```

## Commands

### `brain-dump init`
Interactive setup. Choose backend (B2, S3, local), bucket, and agent profiles.
Creates `~/.config/brain-dump/config.yaml` and initializes the restic repo.

```bash
brain-dump init                  # Interactive
brain-dump init --backend b2     # Skip backend prompt
```

### `brain-dump snapshot`
Take an incremental backup of all configured agent memory directories.

```bash
brain-dump snapshot              # All profiles
brain-dump snapshot --profile openclaw  # Single profile
brain-dump snapshot --dry-run    # Preview without running
brain-dump snapshot --json       # Machine-readable output
```

### `brain-dump restore`
Restore files from a snapshot. **Never auto-overwrites** existing files.

```bash
brain-dump restore latest                           # Restore to ~/brain-dump-restore-<timestamp>
brain-dump restore abc123 --target ~/my-restore     # Specific snapshot + target dir
brain-dump restore latest --dry-run                 # Preview
```

### `brain-dump list`
Show backup history (only brain-dump-tagged snapshots).

```bash
brain-dump list                  # All snapshots
brain-dump list --latest 5       # Last 5
brain-dump list --json           # Machine-readable
```

### `brain-dump status`
Show backup health: repo reachable, latest snapshot age, total stored, schedule.

```bash
brain-dump status                # Human-readable
brain-dump status --json         # Machine-readable
```

### `brain-dump prune`
Apply retention policy from config (runs `restic forget --prune`).

```bash
brain-dump prune                 # Apply retention
brain-dump prune --dry-run       # Preview what would be removed
```

### `brain-dump schedule`
Manage macOS launchd scheduled backups.

```bash
brain-dump schedule install      # Install hourly launchd job
brain-dump schedule remove       # Remove launchd job
brain-dump schedule status       # Show schedule state
```

### `brain-dump doctor`
Run the full 11-point health check: bash, restic, yq, jq, config,
encryption password, backend credentials, repository reachability, profile
paths, schedule freshness, and disk space.

```bash
brain-dump doctor                # Human-readable
brain-dump doctor --json         # Machine-readable
```

### `brain-dump config`
Show or validate resolved configuration.

```bash
brain-dump config                          # Full config
brain-dump config --path repository.backend  # Single value
brain-dump config validate                 # Validate schema and limits
```

### `brain-dump telemetry`
Show snapshot telemetry from `~/.brain-dump/telemetry.jsonl`.

```bash
brain-dump telemetry                       # Last 20 entries
brain-dump telemetry --last 5              # Last 5 entries
brain-dump telemetry --query 'exit_code == 0'
brain-dump telemetry --stats               # Summary statistics
brain-dump telemetry --stats --json        # Machine-readable stats
```

### `brain-dump errors`
Show quarantined snapshot/prune errors.

```bash
brain-dump errors                          # Last 10 errors
brain-dump errors --last 25                # Last 25 errors
brain-dump errors --clear                  # Clear local quarantine files
```

## Supported Agent Presets

| Preset | Paths | Notes |
|--------|-------|-------|
| **openclaw** | `~/.openclaw` | Excludes browser/, media/, delivery-queue/, *.log |
| **hermes** | `~/.hermes` | Excludes logs/, sessions/ |
| **claude-code** | `~/.claude` | Excludes cache/, debug/, downloads/, CachedData/, Code Cache/ |
| **codex** | `~/.codex` | Excludes log/, tmp/ |
| **windsurf** | `~/.codeium/windsurf/memories` | Full memories backup |

## Configuration

Config file: `~/.config/brain-dump/config.yaml`

```yaml
version: 2
config_schema: "2.0"
repository:
  backend: b2           # b2, s3, or local
  bucket: my-backup     # B2 bucket name or S3 bucket
  # endpoint: ""        # Optional: custom S3 endpoint
  # path: /absolute/repo # Required for local backend instead of bucket

profiles:
  - name: my-agents
    preset: openclaw    # Use preset defaults
    paths:
      - ~/.openclaw
      - ~/my-workspace  # Add custom paths
    exclude:
      - "*.log"         # Add custom excludes
    include:
      - "important.log" # Remove from excludes

  - name: custom
    paths:
      - ~/my-data
    exclude:
      - "*.tmp"

schedule:
  interval: 3600        # Seconds between backups

retention:
  hourly: 24            # Keep 24 hourly snapshots
  daily: 30             # Keep 30 daily snapshots
  monthly: 12           # Keep 12 monthly snapshots
  yearly: 0

error_handling:
  mode: "strict"        # strict or lenient
  quarantine_errors: true
  quarantine_dir: "~/.brain-dump/errors"

resource_limits:
  max_memory_mb: 512
  max_duration_minutes: 30
  max_files_per_profile: 100000
```

`version: 1` configs remain accepted for compatibility. New installs generate
the version 2 schema shown above.

### Merge Rules

When a profile uses a preset:
- **Paths**: Profile paths **override** preset paths entirely
- **Excludes**: Profile excludes **merge** with preset excludes (additive)
- **Include**: Profile include items are **removed** from merged excludes

## Credentials

brain-dump never stores credentials. Set them as environment variables:

### Backblaze B2
```bash
export RESTIC_PASSWORD="your-repo-password"
export B2_ACCOUNT_ID="your-key-id"
export B2_ACCOUNT_KEY="your-application-key"
```

### AWS S3
```bash
export RESTIC_PASSWORD="your-repo-password"
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
```

### Local
```bash
export RESTIC_PASSWORD="your-repo-password"
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Config error |
| 2 | Missing dependency |
| 3 | Credentials error |
| 4 | Restic error |
| 5 | No paths to back up |

## Agent Skill

brain-dump includes an [agentskills.io](https://agentskills.io) compliant skill
at `skill/brain-dump/`. Install it in your agent's skill directory to let AI
agents trigger backups and check status.

Restore always requires user confirmation — agents never auto-overwrite.

## How It Works

brain-dump is a thin bash wrapper around restic:

1. **`snapshot`**: Resolves profiles → deduplicates paths → runs `restic backup`
   with appropriate tags and excludes → applies retention policy
2. **`restore`**: Runs `restic restore` to a timestamped temp directory (never
   overwrites existing files)
3. **`schedule`**: Generates a macOS launchd plist and loads it via `launchctl`
4. Everything else is config/validation/formatting
5. **`telemetry`**: Reads structured JSONL backup history and summary stats
6. **`errors`**: Lists or clears local quarantined error records

No daemons, no background processes, no network services. Just bash + restic.

## License

[MIT](LICENSE)
