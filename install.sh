#!/usr/bin/env zsh
# mac-upkeep installer
# Installs maintenance scripts and LaunchAgents for the current user.
# No sudo required. Fully non-interactive.
# Preserves user configuration on re-install.
#
# Usage: git clone https://github.com/nyldn/mac-upkeep && cd mac-upkeep && ./install.sh

set -uo pipefail
setopt NULL_GLOB  # Prevent errors on unmatched globs

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
UPKEEP_DIR="$HOME/.mac-upkeep"
LAUNCH_DIR="$HOME/Library/LaunchAgents"
SCRIPTS_DIR="$UPKEEP_DIR/scripts"
FAILURES=0

echo ""
echo "${CYAN}=== mac-upkeep installer ===${NC}"
echo "Host: $(hostname) | macOS $(sw_vers -productVersion) | $(uname -m)"
echo ""

# ── Preflight checks ────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
    echo "${RED}Error: mac-upkeep only runs on macOS.${NC}"
    exit 1
fi

# Dependency checks
SKIP_BREW=false
if ! command -v brew &>/dev/null; then
    echo "${YELLOW}  Homebrew not found — brew-maintenance agent will be skipped${NC}"
    SKIP_BREW=true
fi

# ── Step 1: Install scripts (preserving user modifications) ──
echo "${CYAN}[1/5]${NC} Installing scripts to $SCRIPTS_DIR..."
mkdir -p "$SCRIPTS_DIR"
mkdir -p "$UPKEEP_DIR/logs"
mkdir -p "$UPKEEP_DIR/locks"

for script in "$REPO_DIR/scripts"/*.sh; do
    filename=$(basename "$script")
    target="$SCRIPTS_DIR/$filename"

    if [[ -f "$target" ]]; then
        # Check if user has modified the installed script
        if ! diff -q "$script" "$target" &>/dev/null; then
            # Files differ — back up the user's version
            mkdir -p "$UPKEEP_DIR/backup"
            cp "$target" "$UPKEEP_DIR/backup/${filename}.$(date +%Y%m%d%H%M%S)"
            echo "${YELLOW}  Updated: $filename (previous version backed up)${NC}"
        fi
    fi
    cp "$script" "$target"
done
chmod 755 "$SCRIPTS_DIR"/*.sh
echo "${GREEN}  Done${NC}"

# ── Step 2: Install config defaults (never overwrite user config) ──
echo "${CYAN}[2/5]${NC} Installing configuration..."

# Always update the defaults file (these are our reference defaults)
cp "$REPO_DIR/config.defaults" "$UPKEEP_DIR/config.defaults"

# Never overwrite the user's config file
if [[ ! -f "$UPKEEP_DIR/config" ]]; then
    echo "${GREEN}  Created ~/.mac-upkeep/config (copy of defaults — customize here)${NC}"
    cp "$REPO_DIR/config.defaults" "$UPKEEP_DIR/config"
else
    echo "${GREEN}  User config preserved: ~/.mac-upkeep/config${NC}"
fi
echo "${GREEN}  Done${NC}"

# ── Step 3: Generate LaunchAgents with correct paths ─
echo "${CYAN}[3/5]${NC} Generating LaunchAgents..."
mkdir -p "$LAUNCH_DIR"

generate_plist() {
    local label="$1"
    local script="$2"
    local schedule="$3"
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

# Daily at 02:30 (skip if no Homebrew)
if [[ "$SKIP_BREW" == "false" ]]; then
    generate_plist "com.mac-upkeep.brew-maintenance" "brew-maintenance.sh" \
        "<dict><key>Hour</key><integer>2</integer><key>Minute</key><integer>30</integer></dict>" 15
fi

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

# ── Step 4: Load LaunchAgents (with proper error reporting) ──
echo "${CYAN}[4/5]${NC} Loading LaunchAgents..."

for plist in "$LAUNCH_DIR"/com.mac-upkeep.*.plist; do
    [[ -f "$plist" ]] || continue
    label=$(defaults read "$plist" Label 2>/dev/null || true)
    if [[ -z "$label" ]]; then
        echo "${RED}  INVALID plist: $(basename "$plist")${NC}"
        FAILURES=$((FAILURES + 1))
        continue
    fi

    # Unload first in case of re-install
    launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true

    # Load and check for actual success
    if launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null; then
        echo "${GREEN}  Loaded: $label${NC}"
    elif launchctl load "$plist" 2>/dev/null; then
        echo "${GREEN}  Loaded: $label (legacy method)${NC}"
    else
        echo "${RED}  FAILED to load: $label${NC}"
        FAILURES=$((FAILURES + 1))
    fi
done

# ── Step 5: Validate ────────────────────────────────
echo "${CYAN}[5/5]${NC} Validating..."

LOADED=$(launchctl list 2>/dev/null | grep -c "com.mac-upkeep" || echo "0")

PLIST_ERRORS=0
for plist in "$LAUNCH_DIR"/com.mac-upkeep.*.plist; do
    [[ -f "$plist" ]] || continue
    if ! plutil -lint "$plist" > /dev/null 2>&1; then
        echo "${RED}  INVALID: $(basename "$plist")${NC}"
        PLIST_ERRORS=$((PLIST_ERRORS + 1))
    fi
done

if (( PLIST_ERRORS == 0 && FAILURES == 0 )); then
    echo "${GREEN}  $LOADED agents loaded, all plists valid${NC}"
else
    echo "${RED}  $FAILURES load failures, $PLIST_ERRORS invalid plists${NC}"
fi

# ── Summary ──────────────────────────────────────────
echo ""
if (( FAILURES > 0 )); then
    echo "${RED}=== Installed with $FAILURES errors ===${NC}"
else
    echo "${CYAN}=== Installed ===${NC}"
fi
echo ""
if [[ "$SKIP_BREW" == "false" ]]; then
    echo "  ${GREEN}Daily  02:30${NC}  brew-maintenance   Homebrew update/upgrade/cleanup"
fi
echo "  ${GREEN}Daily  03:00${NC}  cache-cleanup      Targeted cache & temp pruning"
echo "  ${GREEN}Weekly 03:30${NC}  disk-health        SMART, APFS, space monitoring"
echo "  ${GREEN}Weekly 04:00${NC}  security-audit     Security posture verification"
echo "  ${GREEN}Monthly 1st${NC}   snapshot-thin      Time Machine snapshot thinning"
echo ""
echo "Config:  $UPKEEP_DIR/config  (edit to customize)"
echo "Scripts: $SCRIPTS_DIR/"
echo "Logs:    $UPKEEP_DIR/logs/"
echo ""
echo "Run any script with DRY_RUN=true to preview:"
echo "  DRY_RUN=true $SCRIPTS_DIR/cache-cleanup.sh"
echo ""

exit $FAILURES
