#!/usr/bin/env zsh
# brew-maintenance.sh — Daily Homebrew update, upgrade, and cleanup
# Runs via LaunchAgent at 02:30 daily

set -uo pipefail

LOG="brew-maintenance.log"  # Placeholder
source "${0:A:h}/common.sh"
LOG="$LOG_DIR/brew-maintenance.log"

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_ENV_HINTS=1

rotate_log "$LOG"
acquire_lock || exit 0

# Dependency check: skip entirely if Homebrew is not installed
if ! command -v brew &>/dev/null; then
    log "Homebrew not found. Skipping brew maintenance."
    exit 0
fi

log "=== Homebrew maintenance started ==="

if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log "Running in DRY-RUN mode"
fi

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

# Capture outdated list
OUTDATED=$(brew outdated 2>/dev/null)
if [[ -n "$OUTDATED" ]]; then
    log "Outdated packages: $OUTDATED"
fi

# Upgrade formulae (respects config)
if [[ "${BREW_AUTO_UPGRADE:-true}" == "true" ]]; then
    log "Running brew upgrade..."

    # Build blocklist exclude args
    typeset -a exclude_args=()
    for blocked in "${BREW_BLOCKLIST[@]}"; do
        [[ -n "$blocked" ]] && exclude_args+=(--ignore="$blocked")
    done

    if (( ${#exclude_args} > 0 )); then
        run_or_dry "upgrade Homebrew formulae (with blocklist)" \
            brew upgrade "${exclude_args[@]}" >> "$LOG" 2>&1 || log "WARN: Some formulae failed to upgrade"
    else
        run_or_dry "upgrade Homebrew formulae" \
            brew upgrade >> "$LOG" 2>&1 || log "WARN: Some formulae failed to upgrade"
    fi
else
    log "BREW_AUTO_UPGRADE=false — skipping formula upgrades (outdated packages logged above)"
fi

# Upgrade casks (respects config + blocklist)
if [[ "${BREW_CASK_AUTO_UPGRADE:-true}" == "true" ]]; then
    log "Running brew upgrade --cask..."
    run_or_dry "upgrade Homebrew casks" \
        brew upgrade --cask >> "$LOG" 2>&1 || log "WARN: Some casks failed to upgrade"
else
    log "BREW_CASK_AUTO_UPGRADE=false — skipping cask upgrades"
fi

# Cleanup old versions and downloads
log "Running brew cleanup..."
run_or_dry "cleanup Homebrew (prune ${BREW_CLEANUP_PRUNE_DAYS:-7} days)" \
    brew cleanup --prune=${BREW_CLEANUP_PRUNE_DAYS:-7} >> "$LOG" 2>&1

# npm global package updates
if [[ "${BREW_NPM_GLOBAL_UPDATE:-true}" == "true" ]] && command -v npm &>/dev/null; then
    log "Checking npm global updates..."
    run_or_dry "update npm globals" \
        npm update -g >> "$LOG" 2>&1 || log "WARN: npm global update had issues"
fi

AVAIL=$(df -h / | awk 'NR==2{print $4}')
log "=== Homebrew maintenance complete. Disk available: $AVAIL ==="
