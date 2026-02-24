#!/usr/bin/env zsh
# cache-cleanup.sh — Daily targeted cache and temp file cleanup
# Runs via LaunchAgent at 03:00 daily
# Only cleans caches that are safe to remove and above size thresholds

set -uo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin"

UPKEEP_DIR="${MAC_UPKEEP_DIR:-$HOME/.mac-upkeep}"
LOG_DIR="$UPKEEP_DIR/logs"
LOG="$LOG_DIR/cache-cleanup.log"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TOTAL_FREED=0

log() { echo "[$TIMESTAMP] $1" >> "$LOG"; }

# Size threshold: only clean directories larger than this (in KB)
THRESHOLD_KB=102400  # 100 MB

safe_clean() {
    local dir="$1"
    local label="$2"
    if [[ -d "$dir" ]]; then
        local size_kb
        size_kb=$(du -sk "$dir" 2>/dev/null | awk '{print $1}')
        if (( size_kb > THRESHOLD_KB )); then
            rm -rf "$dir" 2>/dev/null
            log "CLEANED: $label ($((size_kb / 1024)) MB)"
            TOTAL_FREED=$((TOTAL_FREED + size_kb))
        fi
    fi
}

log "=== Daily cache cleanup started ==="

# App updater staging caches (re-downloaded on next update check)
safe_clean ~/Library/Caches/com.google.antigravity.ShipIt "Chrome updater staging"
safe_clean ~/Library/Caches/com.anthropic.claudefordesktop.ShipIt "Claude Desktop updater staging"
safe_clean ~/Library/Caches/pencil-updater "Pencil updater staging"

# Browser caches (regenerate automatically)
safe_clean ~/Library/Caches/Google/Chrome/Default/Cache "Chrome browser cache"
safe_clean ~/Library/Caches/Google/Chrome/Default/Code\ Cache "Chrome code cache"

# Streaming/media app caches
safe_clean ~/Library/Caches/com.spotify.client "Spotify cache"

# Development tool caches (safe to clear, rebuilt on demand)
safe_clean ~/Library/Caches/node-gyp "node-gyp build cache"
safe_clean ~/Library/Caches/ms-playwright "Playwright browsers"
safe_clean ~/Library/Caches/ms-playwright-go "Playwright Go browsers"

# Xcode derived data (safe — forces clean rebuild)
safe_clean ~/Library/Developer/Xcode/DerivedData "Xcode DerivedData"

# Application logs over threshold — only remove files older than 7 days
for logdir in ~/Library/Logs/*/; do
    if [[ -d "$logdir" ]]; then
        local_size=$(du -sk "$logdir" 2>/dev/null | awk '{print $1}')
        if (( local_size > THRESHOLD_KB )); then
            find "$logdir" -type f -mtime +7 -delete 2>/dev/null
            log "PRUNED logs >7d: $(basename "$logdir")"
        fi
    fi
done

# Trash items older than 30 days (only if trash exceeds threshold)
TRASH_SIZE=$(du -sk ~/.Trash 2>/dev/null | awk '{print $1}')
if (( TRASH_SIZE > THRESHOLD_KB )); then
    find ~/.Trash -mindepth 1 -mtime +30 -delete 2>/dev/null
    log "PRUNED Trash items >30 days"
fi

# Disk space check — notify if critically low
AVAIL_GB=$(df -g / | awk 'NR==2{print $4}')
if (( AVAIL_GB < 15 )); then
    log "ALERT: Only ${AVAIL_GB} GB free on boot volume!"
    osascript -e "display notification \"Only ${AVAIL_GB} GB free on disk!\" with title \"Disk Space Alert\" subtitle \"Run cleanup or review large files\"" 2>/dev/null || true
fi

log "=== Cleanup complete. Freed ~$((TOTAL_FREED / 1024)) MB ==="
