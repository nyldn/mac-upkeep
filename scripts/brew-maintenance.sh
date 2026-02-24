#!/usr/bin/env zsh
# brew-maintenance.sh — Daily Homebrew update, upgrade, and cleanup
# Runs via LaunchAgent at 02:30 daily

set -uo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin"
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_ENV_HINTS=1

UPKEEP_DIR="${MAC_UPKEEP_DIR:-$HOME/.mac-upkeep}"
LOG_DIR="$UPKEEP_DIR/logs"
LOG="$LOG_DIR/brew-maintenance.log"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TIMESTAMP] $1" >> "$LOG"; }

log "=== Homebrew maintenance started ==="

# Network connectivity check
if ! /sbin/ping -c 1 -t 10 1.1.1.1 &>/dev/null; then
    log "No network connectivity. Skipping."
    exit 0
fi

# Update formulae definitions
log "Running brew update..."
if ! brew update >> "$LOG" 2>&1; then
    log "ERROR: brew update failed"
    osascript -e 'display notification "brew update failed" with title "Homebrew" subtitle "Check ~/.mac-upkeep/logs/brew-maintenance.log"' 2>/dev/null || true
    exit 1
fi

# Capture outdated list before upgrading
OUTDATED=$(brew outdated 2>/dev/null)
if [[ -n "$OUTDATED" ]]; then
    log "Outdated packages: $OUTDATED"
fi

# Upgrade all formulae (non-interactive)
log "Running brew upgrade..."
brew upgrade >> "$LOG" 2>&1 || log "WARN: Some formulae failed to upgrade"

# Upgrade casks (skip those requiring interactive password prompts)
log "Running brew upgrade --cask..."
brew upgrade --cask >> "$LOG" 2>&1 || log "WARN: Some casks failed to upgrade"

# Cleanup old versions and downloads (keep 7 days of downloads)
log "Running brew cleanup..."
brew cleanup --prune=7 >> "$LOG" 2>&1

# npm global package updates
if command -v npm &>/dev/null; then
    log "Checking npm global updates..."
    npm update -g >> "$LOG" 2>&1 || log "WARN: npm global update had issues"
fi

# Log disk space after cleanup
AVAIL=$(df -h / | awk 'NR==2{print $4}')
log "=== Homebrew maintenance complete. Disk available: $AVAIL ==="
