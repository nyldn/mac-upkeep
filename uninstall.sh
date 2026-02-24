#!/usr/bin/env zsh
# mac-upkeep uninstaller
# Removes all LaunchAgents and scripts. No sudo required.
# Preserves user config in a backup if it exists.
#
# Usage: ./uninstall.sh

set -uo pipefail
setopt NULL_GLOB

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

UPKEEP_DIR="$HOME/.mac-upkeep"
LAUNCH_DIR="$HOME/Library/LaunchAgents"

echo ""
echo "${CYAN}=== mac-upkeep uninstaller ===${NC}"
echo ""

# Unload agents
for plist in "$LAUNCH_DIR"/com.mac-upkeep.*.plist; do
    [[ -f "$plist" ]] || continue
    label=$(defaults read "$plist" Label 2>/dev/null || basename "$plist" .plist)
    launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
    rm -f "$plist"
    echo "${YELLOW}  Removed: $label${NC}"
done

# Back up user config before removing everything
if [[ -f "$UPKEEP_DIR/config" ]]; then
    BACKUP="$HOME/.mac-upkeep-config-backup-$(date +%Y%m%d%H%M%S)"
    cp "$UPKEEP_DIR/config" "$BACKUP"
    echo "${GREEN}  User config backed up to: $BACKUP${NC}"
fi

# Remove scripts, locks, and logs
if [[ -d "$UPKEEP_DIR" ]]; then
    rm -rf "$UPKEEP_DIR"
    echo "${YELLOW}  Removed: $UPKEEP_DIR${NC}"
fi

echo ""
echo "${GREEN}mac-upkeep fully uninstalled.${NC}"
echo ""
