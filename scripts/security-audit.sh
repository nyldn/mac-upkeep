#!/usr/bin/env zsh
# security-audit.sh — Weekly security posture verification
# Runs via LaunchAgent every Sunday at 04:00

set -uo pipefail

LOG="security-audit.log"  # Placeholder
source "${0:A:h}/common.sh"
LOG="$LOG_DIR/security-audit.log"
REPORT="$LOG_DIR/security-report-$(date +%Y-%m-%d).txt"

rotate_log "$LOG"
acquire_lock || exit 0

ISSUES=0
WARNINGS=0

pass() { echo "[PASS] $1" >> "$REPORT"; }
warn() { echo "[WARN] $1" >> "$REPORT"; WARNINGS=$((WARNINGS + 1)); }
fail() { echo "[FAIL] $1" >> "$REPORT"; ISSUES=$((ISSUES + 1)); }
info() { echo "[INFO] $1" >> "$REPORT"; }

echo "=== Security Audit Report — $(date) ===" > "$REPORT"
echo "Host: $(hostname)" >> "$REPORT"
echo "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))" >> "$REPORT"
echo "" >> "$REPORT"

# ── 1. System Integrity Protection ──────────────────
if csrutil status 2>/dev/null | grep -q "enabled"; then
    pass "System Integrity Protection is enabled"
else
    fail "SIP is DISABLED — critical security control missing"
fi

# ── 2. Gatekeeper ───────────────────────────────────
if spctl --status 2>/dev/null | grep -q "assessments enabled"; then
    pass "Gatekeeper is enabled"
else
    fail "Gatekeeper is DISABLED"
fi

# ── 3. FileVault ────────────────────────────────────
if fdesetup status 2>/dev/null | grep -q "FileVault is On"; then
    pass "FileVault disk encryption is ON"
else
    fail "FileVault is OFF — disk is not encrypted"
fi

# ── 4. Remote Login (SSH) ────────────────────────────
if launchctl list 2>/dev/null | grep -q "com.openssh.sshd"; then
    warn "SSH daemon (Remote Login) is ACTIVE — verify this is intentional"
else
    pass "Remote Login (sshd) is not running"
fi

# ── 5. Screen Lock ──────────────────────────────────
SCREEN_LOCK=$(sysadminctl -screenLock status 2>&1 || echo "unknown")
if echo "$SCREEN_LOCK" | grep -qi "immediate"; then
    pass "Screen lock is set to immediate"
elif echo "$SCREEN_LOCK" | grep -qi "off"; then
    fail "Screen lock is OFF"
else
    info "Screen lock status: $SCREEN_LOCK"
fi

# ── 6. XProtect Version ────────────────────────────
XPROTECT_VER=$(defaults read /Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo "unknown")
info "XProtect version: $XPROTECT_VER"

# ── 7. Software Updates ────────────────────────────
UPDATE_CHECK=$(softwareupdate -l 2>&1)
if echo "$UPDATE_CHECK" | grep -q "No new software available"; then
    pass "macOS software is up to date"
else
    warn "Software updates available — review: softwareupdate -l"
    echo "$UPDATE_CHECK" >> "$REPORT"
fi

# ── 8. Auto-Update Settings ─────────────────────────
AUTO_DL=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload 2>/dev/null || echo "unknown")
AUTO_INSTALL=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates 2>/dev/null || echo "unknown")
CRITICAL_INSTALL=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall 2>/dev/null || echo "unknown")

if [[ "$AUTO_DL" == "1" && "$AUTO_INSTALL" == "1" && "$CRITICAL_INSTALL" == "1" ]]; then
    pass "Automatic updates fully enabled (download + install + critical)"
elif [[ "$AUTO_DL" == "unknown" ]]; then
    info "Auto-update settings: unable to read (permission denied)"
else
    warn "Automatic update settings incomplete (AutoDL=$AUTO_DL, AutoInstall=$AUTO_INSTALL, Critical=$CRITICAL_INSTALL)"
fi

# ── 9. Open Wildcard Listeners ──────────────────────
WILDCARD_COUNT=$(lsof -iTCP -sTCP:LISTEN -n -P 2>/dev/null | grep -c '\*:' || echo "0")
if (( WILDCARD_COUNT > 5 )); then
    warn "$WILDCARD_COUNT services listening on all interfaces (wildcard *:port)"
    echo "  Top wildcard listeners:" >> "$REPORT"
    lsof -iTCP -sTCP:LISTEN -n -P 2>/dev/null | grep '\*:' | awk '{print "    " $1 " -> " $9}' | sort -u >> "$REPORT"
else
    info "$WILDCARD_COUNT services on wildcard interfaces"
fi

# ── Summary ─────────────────────────────────────────
echo "" >> "$REPORT"
echo "=== SUMMARY: $ISSUES failures, $WARNINGS warnings ===" >> "$REPORT"

if (( ISSUES > 0 )); then
    osascript -e "display notification \"$ISSUES security FAILURES detected\" with title \"Security Audit\" subtitle \"Review: ~/.mac-upkeep/logs/\"" 2>/dev/null || true
fi

log "Security audit: $ISSUES failures, $WARNINGS warnings"

# Rotate old reports
find "$LOG_DIR" -name "security-report-*.txt" -mtime +${SECURITY_REPORT_RETENTION_DAYS:-84} -delete 2>/dev/null || true
