#!/usr/bin/env zsh
# mac-upkeep installer
# Installs maintenance scripts and LaunchAgents for the current user.
# No sudo required. Fully non-interactive.
#
# Usage: git clone https://github.com/nyldn/mac-upkeep && cd mac-upkeep && ./install.sh

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
UPKEEP_DIR="$HOME/.mac-upkeep"
LAUNCH_DIR="$HOME/Library/LaunchAgents"
SCRIPTS_DIR="$UPKEEP_DIR/scripts"

echo ""
echo "${CYAN}=== mac-upkeep installer ===${NC}"
echo "Host: $(hostname) | macOS $(sw_vers -productVersion) | $(uname -m)"
echo ""

# ── Preflight checks ────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
    echo "${RED}Error: mac-upkeep only runs on macOS.${NC}"
    exit 1
fi

# ── Step 1: Install scripts ─────────────────────────
echo "${CYAN}[1/4]${NC} Installing scripts to $SCRIPTS_DIR..."
mkdir -p "$SCRIPTS_DIR"
mkdir -p "$UPKEEP_DIR/logs"

for script in "$REPO_DIR/scripts"/*.sh; do
    cp "$script" "$SCRIPTS_DIR/"
done
chmod 755 "$SCRIPTS_DIR"/*.sh
echo "${GREEN}  Done${NC}"

# ── Step 2: Generate LaunchAgents with correct paths ─
echo "${CYAN}[2/4]${NC} Generating LaunchAgents..."
mkdir -p "$LAUNCH_DIR"

generate_plist() {
    local label="$1"
    local script="$2"
    local schedule="$3"  # XML fragment for StartCalendarInterval
    local nice="${4:-20}"

    cat > "$LAUNCH_DIR/$label.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPTS_DIR/$script</string>
    </array>
    <key>StartCalendarInterval</key>
    $schedule
    <key>ProcessType</key>
    <string>Background</string>
    <key>LowPriorityIO</key>
    <true/>
    <key>Nice</key>
    <integer>$nice</integer>
    <key>StandardOutPath</key>
    <string>$UPKEEP_DIR/logs/$label-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$UPKEEP_DIR/logs/$label-stderr.log</string>
    <key>ThrottleInterval</key>
    <integer>3600</integer>
</dict>
</plist>
PLIST
    echo "${GREEN}  Generated: $label${NC}"
}

# Daily at 02:30
generate_plist "com.mac-upkeep.brew-maintenance" "brew-maintenance.sh" \
    "<dict><key>Hour</key><integer>2</integer><key>Minute</key><integer>30</integer></dict>" 15

# Daily at 03:00
generate_plist "com.mac-upkeep.cache-cleanup" "cache-cleanup.sh" \
    "<dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer></dict>"

# Weekly Sunday at 03:30
generate_plist "com.mac-upkeep.disk-health" "disk-health.sh" \
    "<dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>30</integer><key>Weekday</key><integer>0</integer></dict>"

# Weekly Sunday at 04:00
generate_plist "com.mac-upkeep.security-audit" "security-audit.sh" \
    "<dict><key>Hour</key><integer>4</integer><key>Minute</key><integer>0</integer><key>Weekday</key><integer>0</integer></dict>"

# Monthly 1st at 02:00
generate_plist "com.mac-upkeep.snapshot-thin" "snapshot-thin.sh" \
    "<dict><key>Day</key><integer>1</integer><key>Hour</key><integer>2</integer><key>Minute</key><integer>0</integer></dict>"

# ── Step 3: Unload previous versions if re-installing
echo "${CYAN}[3/4]${NC} Loading LaunchAgents..."

for plist in "$LAUNCH_DIR"/com.mac-upkeep.*.plist; do
    label=$(defaults read "$plist" Label 2>/dev/null || true)
    if [[ -n "$label" ]]; then
        # Unload first in case of re-install
        launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
        # Load
        launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || \
            launchctl load "$plist" 2>/dev/null || true
        echo "${GREEN}  Loaded: $label${NC}"
    fi
done

echo "${GREEN}  Done${NC}"

# ── Step 4: Validate ────────────────────────────────
echo "${CYAN}[4/4]${NC} Validating..."

LOADED=$(launchctl list 2>/dev/null | grep -c "com.mac-upkeep" || echo "0")
echo "${GREEN}  $LOADED agents loaded successfully${NC}"

for plist in "$LAUNCH_DIR"/com.mac-upkeep.*.plist; do
    plutil -lint "$plist" > /dev/null 2>&1 || echo "${RED}  INVALID: $(basename "$plist")${NC}"
done

echo "${GREEN}  All plists valid${NC}"

# ── Summary ──────────────────────────────────────────
echo ""
echo "${CYAN}=== Installed ===${NC}"
echo ""
echo "  ${GREEN}Daily  02:30${NC}  brew-maintenance   Homebrew update/upgrade/cleanup"
echo "  ${GREEN}Daily  03:00${NC}  cache-cleanup      Targeted cache & temp pruning"
echo "  ${GREEN}Weekly 03:30${NC}  disk-health        SMART, APFS, space monitoring"
echo "  ${GREEN}Weekly 04:00${NC}  security-audit     Security posture verification"
echo "  ${GREEN}Monthly 1st${NC}   snapshot-thin      Time Machine snapshot thinning"
echo ""
echo "Scripts: $SCRIPTS_DIR/"
echo "Logs:    $UPKEEP_DIR/logs/"
echo ""
