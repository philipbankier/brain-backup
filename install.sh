#!/usr/bin/env bash
# brain-backup installer — curl | sh
# Usage: curl -fsSL https://raw.githubusercontent.com/philipbankier/brain-backup/main/install.sh | bash
set -euo pipefail

REPO_BASE="https://raw.githubusercontent.com/philipbankier/brain-backup/main"
INSTALL_BIN="${HOME}/.local/bin"
INSTALL_SHARE="${HOME}/.local/share/brain-backup"

# ── Colors ──────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
info()  { printf "${GREEN}[brain-backup]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[brain-backup]${NC} %s\n" "$*"; }
err()   { printf "${RED}[brain-backup]${NC} %s\n" "$*" >&2; }
die()   { err "$@"; exit 1; }

# ── 1. OS check ─────────────────────────────────────────
OS="$(uname -s)"
case "$OS" in
  Darwin|Linux) ;;
  *) die "Unsupported OS: $OS. brain-backup requires macOS or Linux." ;;
esac

# ── 2. bash version check ──────────────────────────────
if [[ "${BASH_VERSINFO[0]}" -lt 3 ]] || { [[ "${BASH_VERSINFO[0]}" -eq 3 ]] && [[ "${BASH_VERSINFO[1]}" -lt 2 ]]; }; then
  die "bash 3.2+ required. Current: ${BASH_VERSION}"
fi
info "bash ${BASH_VERSION} ✓"

# ── Helper: check + offer brew install ──────────────────
check_dep() {
  local name="$1" min_version="$2" get_version_cmd="$3"
  if command -v "$name" &>/dev/null; then
    local ver
    ver=$($get_version_cmd 2>&1 | head -1)
    info "$name found ($ver) ✓"
    return 0
  fi

  # Missing — offer to install via brew
  if command -v brew &>/dev/null; then
    printf "${YELLOW}[brain-backup]${NC} %s not found. Install via brew? [Y/n] " "$name"
    read -r answer < /dev/tty
    case "$answer" in
      n|N|no|NO) die "$name is required. Install manually: brew install $name" ;;
      *) brew install "$name" || die "brew install $name failed" ;;
    esac
  else
    die "$name not found and brew not available. Install $name ($min_version+) manually."
  fi
}

# ── 3-5. Dependency checks ─────────────────────────────
check_dep "restic" "0.16+" "restic version"
check_dep "yq"    "4.0+"  "yq --version"
check_dep "jq"    "1.6+"  "jq --version"

# ── 6. Create install dirs ─────────────────────────────
mkdir -p "$INSTALL_BIN"
mkdir -p "$INSTALL_SHARE/lib"
mkdir -p "$INSTALL_SHARE/presets"

# ── Helper: download with fallback ──────────────────────
download() {
  local src="$1" dest="$2"
  if ! curl -fsSL "$REPO_BASE/$src" -o "$dest" 2>/dev/null; then
    err "Failed to download $src"
    err "Manual install: git clone https://github.com/philipbankier/brain-backup.git"
    die "Then: cd brain-backup && ln -s \$(pwd)/brain-backup ~/.local/bin/brain-backup"
  fi
}

# ── 7. Download main script ────────────────────────────
info "Downloading brain-backup CLI..."
download "brain-backup" "$INSTALL_BIN/brain-backup"
chmod +x "$INSTALL_BIN/brain-backup"

# ── 8. Download lib/ ───────────────────────────────────
info "Downloading lib/..."
download "lib/config.sh"   "$INSTALL_SHARE/lib/config.sh"
download "lib/presets.sh"  "$INSTALL_SHARE/lib/presets.sh"
download "lib/output.sh"   "$INSTALL_SHARE/lib/output.sh"

# ── 9. Download presets/ ───────────────────────────────
info "Downloading presets/..."
for preset in openclaw hermes claude-code codex windsurf; do
  download "presets/${preset}.yaml" "$INSTALL_SHARE/presets/${preset}.yaml"
done

# ── 11. PATH setup ─────────────────────────────────────
if [[ ":$PATH:" != *":$INSTALL_BIN:"* ]]; then
  # Determine shell config file
  if [[ -n "${ZSH_VERSION:-}" ]] || [[ "${SHELL:-}" == */zsh ]]; then
    if [[ -f "$HOME/.zshrc" ]]; then
      echo '' >> "$HOME/.zshrc"
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
      info "Added to ~/.zshrc. Run: source ~/.zshrc"
    fi
  elif [[ "${SHELL:-}" == */fish ]]; then
    warn "Fish detected. Add to config.fish: set -gx PATH $HOME/.local/bin \$PATH"
  elif [[ -f "$HOME/.bashrc" ]]; then
    echo '' >> "$HOME/.bashrc"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    info "Added to ~/.bashrc. Run: source ~/.bashrc"
  else
    warn "Add to your shell config: export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi

  # Also make it work for the rest of THIS script
  export PATH="$INSTALL_BIN:$PATH"
fi

# ── 12. Done ────────────────────────────────────────────
echo ""
info "✅ brain-backup installed. Run: brain-backup init"
