#!/usr/bin/env zsh
# disk-health.sh — Weekly disk health monitoring
# Runs via LaunchAgent every Sunday at 03:30

set -uo pipefail

LOG="disk-health.log"  # Placeholder
source "${0:A:h}/common.sh"
LOG="$LOG_DIR/disk-health.log"
REPORT="$LOG_DIR/disk-health-$(date +%Y-%m-%d).txt"

rotate_log "$LOG"
acquire_lock || exit 0

echo "=== Disk Health Report — $(date) ===" > "$REPORT"
echo "Host: $(hostname)" >> "$REPORT"
echo "" >> "$REPORT"

# ── 1. SMART Status ─────────────────────────────────
echo "--- SMART Status ---" >> "$REPORT"
SMART_STATUS=$(diskutil info disk0 2>/dev/null | grep "SMART Status" | awk -F: '{print $2}' | xargs)
if [[ "$SMART_STATUS" == "Verified" ]]; then
    echo "[PASS] SMART Status: Verified" >> "$REPORT"
else
    echo "[FAIL] SMART Status: $SMART_STATUS" >> "$REPORT"
    osascript -e "display notification \"SMART status: $SMART_STATUS\" with title \"Disk Health ALERT\" subtitle \"Drive may be failing!\"" 2>/dev/null || true
fi

# ── 2. Volume Space ─────────────────────────────────
echo "" >> "$REPORT"
echo "--- Volume Space ---" >> "$REPORT"
df -h / /System/Volumes/Data 2>/dev/null >> "$REPORT"

AVAIL_GB=$(df -g / | awk 'NR==2{print $4}')
CAPACITY_PCT=$(df / | awk 'NR==2{print $5}' | tr -d '%')

echo "" >> "$REPORT"
echo "Available: ${AVAIL_GB} GB | Used: ${CAPACITY_PCT}%" >> "$REPORT"

if (( AVAIL_GB < ${DISK_ALERT_CRITICAL_GB:-10} )); then
    echo "[CRITICAL] Less than ${DISK_ALERT_CRITICAL_GB:-10} GB free!" >> "$REPORT"
    osascript -e "display notification \"Only ${AVAIL_GB} GB free!\" with title \"Disk Space CRITICAL\" subtitle \"Immediate cleanup required\"" 2>/dev/null || true
elif (( AVAIL_GB < ${DISK_ALERT_WARN_GB:-25} )); then
    echo "[WARN] Less than ${DISK_ALERT_WARN_GB:-25} GB free" >> "$REPORT"
    osascript -e "display notification \"${AVAIL_GB} GB free — consider cleanup\" with title \"Disk Space Warning\"" 2>/dev/null || true
else
    echo "[OK] Disk space healthy" >> "$REPORT"
fi

# ── 3. APFS Container Info ──────────────────────────
echo "" >> "$REPORT"
echo "--- APFS Container ---" >> "$REPORT"
diskutil apfs list 2>/dev/null | grep -E "Container|Capacity|Free Space" >> "$REPORT"

# ── 4. Local Snapshots ──────────────────────────────
echo "" >> "$REPORT"
echo "--- Time Machine Local Snapshots ---" >> "$REPORT"
SNAP_COUNT=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple" || true)
SNAP_COUNT=${SNAP_COUNT:-0}
echo "Snapshot count: $SNAP_COUNT" >> "$REPORT"
tmutil listlocalsnapshots / >> "$REPORT" 2>/dev/null || echo "  (none)" >> "$REPORT"

if (( SNAP_COUNT > 10 )); then
    echo "[WARN] Many local snapshots ($SNAP_COUNT) — consider thinning" >> "$REPORT"
fi

# ── 5. Top Space Consumers ──────────────────────────
echo "" >> "$REPORT"
echo "--- Top Space Consumers (user home) ---" >> "$REPORT"
du -sh ~/Downloads ~/Library/Caches ~/Library/Application\ Support \
    ~/Library/Containers ~/Documents ~/Desktop \
    ~/.Trash 2>/dev/null | sort -rh >> "$REPORT"

# ── 6. Memory & Swap ────────────────────────────────
echo "" >> "$REPORT"
echo "--- Memory & Swap ---" >> "$REPORT"
SWAP_INFO=$(sysctl vm.swapusage 2>/dev/null)
echo "$SWAP_INFO" >> "$REPORT"

SWAP_USED_MB=$(echo "$SWAP_INFO" | grep -oE 'used = [0-9.]+M' | grep -oE '[0-9.]+')
if [[ -n "$SWAP_USED_MB" ]] && (( ${SWAP_USED_MB%.*} > ${SWAP_WARN_MB:-8192} )); then
    echo "[WARN] Swap usage over $((${SWAP_WARN_MB:-8192} / 1024)) GB — memory pressure high" >> "$REPORT"
fi

# ── 7. Uptime ───────────────────────────────────────
echo "" >> "$REPORT"
echo "--- System Uptime ---" >> "$REPORT"
uptime >> "$REPORT"

UPTIME_DAYS=$(uptime | grep -oE 'up [0-9]+ day' | grep -oE '[0-9]+')
if [[ -n "$UPTIME_DAYS" ]] && (( UPTIME_DAYS > ${UPTIME_WARN_DAYS:-14} )); then
    echo "[WARN] System has been up for $UPTIME_DAYS days — consider a reboot" >> "$REPORT"
fi

echo "" >> "$REPORT"
echo "=== Report complete ===" >> "$REPORT"

log "Disk health check complete. ${AVAIL_GB} GB free, SMART: $SMART_STATUS"

# Rotate old reports
find "$LOG_DIR" -name "disk-health-*.txt" -mtime +${DISK_REPORT_RETENTION_DAYS:-84} -delete 2>/dev/null || true
