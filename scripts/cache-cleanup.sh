#!/usr/bin/env zsh
# cache-cleanup.sh — Daily targeted cache and temp file cleanup
# Runs via LaunchAgent at 03:00 daily

set -uo pipefail

LOG="cache-cleanup.log"  # Placeholder, overridden after sourcing common
source "${0:A:h}/common.sh"
LOG="$LOG_DIR/cache-cleanup.log"

rotate_log "$LOG"
acquire_lock || exit 0

TOTAL_FREED=0

safe_clean() {
    local dir="$1"
    local label="$2"
    dir=$(expand_path "$dir")

    if [[ -d "$dir" ]]; then
        local size_kb
        size_kb=$(du -sk "$dir" 2>/dev/null | awk '{print $1}')
        if (( size_kb > ${CACHE_THRESHOLD_KB:-102400} )); then
            run_or_dry "clean $label ($((size_kb / 1024)) MB)" \
                find "$dir" -mindepth 1 -delete
            log "CLEANED: $label ($((size_kb / 1024)) MB)"
            TOTAL_FREED=$((TOTAL_FREED + size_kb))
        fi
    fi
}

log "=== Daily cache cleanup started ==="

if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log "Running in DRY-RUN mode — no files will be deleted"
fi

# Clean targets from config (user-customizable list)
for entry in "${CACHE_TARGETS[@]}"; do
    local path="${entry%%|*}"
    local label="${entry##*|}"
    safe_clean "$path" "$label"
done

# Application logs over threshold — only remove files older than configured days
for logdir in ~/Library/Logs/*/; do
    if [[ -d "$logdir" ]]; then
        local_size=$(du -sk "$logdir" 2>/dev/null | awk '{print $1}')
        if (( local_size > ${CACHE_THRESHOLD_KB:-102400} )); then
            run_or_dry "prune logs >$CACHE_LOG_MAX_AGE_DAYS days in $(basename "$logdir")" \
                find "$logdir" -type f -mtime +${CACHE_LOG_MAX_AGE_DAYS:-7} -delete
            log "PRUNED logs >${CACHE_LOG_MAX_AGE_DAYS:-7}d: $(basename "$logdir")"
        fi
    fi
done

# Trash items older than configured days (only if trash exceeds threshold)
TRASH_SIZE=$(du -sk ~/.Trash 2>/dev/null | awk '{print $1}')
if (( TRASH_SIZE > ${CACHE_THRESHOLD_KB:-102400} )); then
    run_or_dry "prune Trash items >$CACHE_TRASH_MAX_AGE_DAYS days" \
        find ~/.Trash -mindepth 1 -mtime +${CACHE_TRASH_MAX_AGE_DAYS:-30} -delete
    log "PRUNED Trash items >${CACHE_TRASH_MAX_AGE_DAYS:-30} days"
fi

# Disk space check — notify if critically low
AVAIL_GB=$(df -g / | awk 'NR==2{print $4}')
if (( AVAIL_GB < ${DISK_ALERT_CRITICAL_GB:-10} )); then
    log "ALERT: Only ${AVAIL_GB} GB free on boot volume!"
    osascript -e "display notification \"Only ${AVAIL_GB} GB free on disk!\" with title \"Disk Space Alert\" subtitle \"Run cleanup or review large files\"" 2>/dev/null || true
fi

log "=== Cleanup complete. Freed ~$((TOTAL_FREED / 1024)) MB ==="
