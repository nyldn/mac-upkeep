#!/usr/bin/env zsh
# common.sh — Shared functions for mac-upkeep scripts
# Sourced by all scripts. Not executable on its own.

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin"

UPKEEP_DIR="${MAC_UPKEEP_DIR:-$HOME/.mac-upkeep}"
LOG_DIR="$UPKEEP_DIR/logs"
LOCK_DIR="$UPKEEP_DIR/locks"
mkdir -p "$LOG_DIR" "$LOCK_DIR"

# ── Load configuration ──────────────────────────────
# Source defaults first, then user overrides
_SCRIPT_DIR="${0:A:h}"
_DEFAULTS="${_SCRIPT_DIR}/../config.defaults"
_USER_CONFIG="$UPKEEP_DIR/config"

# Load defaults from the installed copy, fall back to repo copy
if [[ -f "$UPKEEP_DIR/config.defaults" ]]; then
    source "$UPKEEP_DIR/config.defaults"
elif [[ -f "$_DEFAULTS" ]]; then
    source "$_DEFAULTS"
fi

# User config overrides (this file is never overwritten by the installer)
if [[ -f "$_USER_CONFIG" ]]; then
    source "$_USER_CONFIG"
fi

# ── Logging with per-event timestamps ────────────────
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

# ── Log rotation ─────────────────────────────────────
rotate_log() {
    local logfile="${1:-$LOG}"
    local max_kb="${LOG_MAX_SIZE_KB:-1024}"
    local count="${LOG_ROTATE_COUNT:-3}"

    if [[ ! -f "$logfile" ]]; then
        return 0
    fi

    local size_kb
    size_kb=$(du -sk "$logfile" 2>/dev/null | awk '{print $1}')
    if (( size_kb > max_kb )); then
        # Rotate: .3 -> delete, .2 -> .3, .1 -> .2, current -> .1
        local i=$count
        while (( i > 1 )); do
            [[ -f "${logfile}.$((i-1))" ]] && mv "${logfile}.$((i-1))" "${logfile}.$i"
            i=$((i - 1))
        done
        mv "$logfile" "${logfile}.1"
        touch "$logfile"
        log "Log rotated: $(basename "$logfile")"
    fi
}

# ── Lockfile (prevents concurrent runs) ──────────────
acquire_lock() {
    local name="${1:-$(basename "$0" .sh)}"
    local lockfile="$LOCK_DIR/${name}.lock"

    if mkdir "$lockfile" 2>/dev/null; then
        # Write PID for debugging
        echo $$ > "$lockfile/pid"
        # Clean up on exit (normal, error, or signal)
        trap "rm -rf '$lockfile'" EXIT INT TERM HUP
        return 0
    else
        # Check if the holding process is still alive
        local held_pid
        held_pid=$(cat "$lockfile/pid" 2>/dev/null)
        if [[ -n "$held_pid" ]] && kill -0 "$held_pid" 2>/dev/null; then
            log "SKIP: Another instance is running (PID $held_pid)"
            return 1
        else
            # Stale lock — previous run crashed
            log "Removing stale lock (PID $held_pid no longer running)"
            rm -rf "$lockfile"
            mkdir "$lockfile" 2>/dev/null || return 1
            echo $$ > "$lockfile/pid"
            trap "rm -rf '$lockfile'" EXIT INT TERM HUP
            return 0
        fi
    fi
}

# ── Dry-run guard ────────────────────────────────────
# Usage: run_or_dry "description" command arg1 arg2 ...
run_or_dry() {
    local desc="$1"
    shift
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "DRY-RUN: Would $desc"
        return 0
    else
        "$@"
    fi
}

# ── Expand ~ in paths ────────────────────────────────
expand_path() {
    local p="$1"
    echo "${p/#\~/$HOME}"
}
