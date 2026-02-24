#!/usr/bin/env zsh
# snapshot-thin.sh — Monthly Time Machine snapshot management
# Runs via LaunchAgent on 1st of each month at 02:00
# Thins local snapshots to prevent purgeable space bloat

set -uo pipefail

export PATH="/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin"

UPKEEP_DIR="${MAC_UPKEEP_DIR:-$HOME/.mac-upkeep}"
LOG_DIR="$UPKEEP_DIR/logs"
LOG="$LOG_DIR/snapshot-thin.log"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TIMESTAMP] $1" >> "$LOG"; }

log "=== Monthly snapshot thinning started ==="

# Count current snapshots
BEFORE_COUNT=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple" || echo "0")
log "Snapshots before: $BEFORE_COUNT"

AVAIL_BEFORE=$(df -g / | awk 'NR==2{print $4}')
log "Free space before: ${AVAIL_BEFORE} GB"

# Thin snapshots — request 50 GB of reclaimable space, urgency 3/4
tmutil thinlocalsnapshots / 53687091200 3 2>/dev/null
log "Thinning command executed (50 GB target, urgency 3)"

sleep 5

AFTER_COUNT=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple" || echo "0")
AVAIL_AFTER=$(df -g / | awk 'NR==2{print $4}')

log "Snapshots after: $AFTER_COUNT (removed $((BEFORE_COUNT - AFTER_COUNT)))"
log "Free space after: ${AVAIL_AFTER} GB (recovered $((AVAIL_AFTER - AVAIL_BEFORE)) GB)"
log "=== Snapshot thinning complete ==="
