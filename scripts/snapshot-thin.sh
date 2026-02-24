#!/usr/bin/env zsh
# snapshot-thin.sh — Monthly Time Machine snapshot management
# Runs via LaunchAgent on 1st of each month at 02:00

set -uo pipefail

LOG="snapshot-thin.log"  # Placeholder
source "${0:A:h}/common.sh"
LOG="$LOG_DIR/snapshot-thin.log"

rotate_log "$LOG"
acquire_lock || exit 0

log "=== Monthly snapshot thinning started ==="

if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log "Running in DRY-RUN mode"
fi

# Count current snapshots
BEFORE_COUNT=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple" || true)
BEFORE_COUNT=${BEFORE_COUNT:-0}
log "Snapshots before: $BEFORE_COUNT"

AVAIL_BEFORE=$(df -g / | awk 'NR==2{print $4}')
log "Free space before: ${AVAIL_BEFORE} GB"

# Thin snapshots
run_or_dry "thin snapshots (${SNAPSHOT_THIN_BYTES:-53687091200} bytes target, urgency ${SNAPSHOT_THIN_URGENCY:-3})" \
    tmutil thinlocalsnapshots / ${SNAPSHOT_THIN_BYTES:-53687091200} ${SNAPSHOT_THIN_URGENCY:-3}
log "Thinning command executed"

sleep 5

AFTER_COUNT=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple" || true)
AFTER_COUNT=${AFTER_COUNT:-0}
AVAIL_AFTER=$(df -g / | awk 'NR==2{print $4}')

log "Snapshots after: $AFTER_COUNT (removed $((BEFORE_COUNT - AFTER_COUNT)))"
log "Free space after: ${AVAIL_AFTER} GB (recovered $((AVAIL_AFTER - AVAIL_BEFORE)) GB)"
log "=== Snapshot thinning complete ==="
