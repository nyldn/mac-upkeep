# mac-upkeep

Automated macOS system maintenance. No sudo required.

Installs lightweight LaunchAgents that run in the background to keep your Mac healthy — cache cleanup, Homebrew updates, disk monitoring, security checks, and Time Machine snapshot management.

## Install

```bash
git clone https://github.com/nyldn/mac-upkeep.git
cd mac-upkeep
./install.sh
```

## Uninstall

```bash
cd mac-upkeep
./uninstall.sh
```

## What it does

| Schedule | Script | Purpose |
|----------|--------|---------|
| Daily 02:30 | `brew-maintenance.sh` | Homebrew update, upgrade, cleanup, npm globals |
| Daily 03:00 | `cache-cleanup.sh` | Prune app caches, updater staging, old logs, stale trash |
| Weekly Sun 03:30 | `disk-health.sh` | SMART status, APFS health, space alerts, swap monitoring |
| Weekly Sun 04:00 | `security-audit.sh` | SIP, Gatekeeper, FileVault, XProtect, update status |
| Monthly 1st 02:00 | `snapshot-thin.sh` | Thin Time Machine local snapshots |

All scripts run as `ProcessType: Background` with `LowPriorityIO` and `Nice 20` — they yield to anything you're doing and won't slow your Mac down.

## Design principles

- **No sudo.** Everything runs in user context. Nothing requires a password or interactive input.
- **Safe defaults.** Caches are only cleaned when above 100 MB. Trash items must be 30+ days old. Downloads are never touched.
- **Alerts when it matters.** macOS notifications fire for low disk space (<15 GB), SMART failures, and security drift.
- **Portable.** No hardcoded paths. Scripts resolve `$HOME` at runtime. The installer generates plists with the correct user paths.
- **Replaceable.** Each script is independent. Disable or replace any one without affecting the others.

## What it cleans

Cache cleanup targets directories that safely regenerate:

- Browser caches (Chrome)
- App updater staging (ShipIt directories)
- Streaming caches (Spotify)
- Dev tool caches (node-gyp, Playwright, Xcode DerivedData)
- App logs older than 7 days (only from directories over 100 MB)
- Trash items older than 30 days

### What it never touches

- `~/Downloads` — always manual
- `~/Library/Caches/CloudKit` — iCloud sync metadata
- `~/Library/Caches/com.apple.dyld` — system runtime cache
- `/System/Library/Caches` — protected by SIP
- `/var/db/dyld` — boot-critical

## Security audit checks

The weekly security audit verifies:

- System Integrity Protection (SIP) enabled
- Gatekeeper enabled
- FileVault disk encryption on
- Remote Login (SSH) not running
- Screen lock set to immediate
- XProtect version logged
- macOS software update status
- Automatic update settings complete
- Wildcard TCP listeners inventory

Results are saved to `~/.mac-upkeep/logs/security-report-YYYY-MM-DD.txt`.

## Logs

All logs live in `~/.mac-upkeep/logs/`. Weekly reports auto-rotate after 12 weeks.

```bash
# Recent cache cleanup activity
tail -20 ~/.mac-upkeep/logs/cache-cleanup.log

# Latest security report
cat ~/.mac-upkeep/logs/security-report-$(date +%Y-%m-%d).txt

# Latest disk health report
cat ~/.mac-upkeep/logs/disk-health-$(date +%Y-%m-%d).txt

# Homebrew maintenance log
tail -20 ~/.mac-upkeep/logs/brew-maintenance.log
```

## Manually running a script

Any script can be run on demand:

```bash
~/.mac-upkeep/scripts/cache-cleanup.sh
~/.mac-upkeep/scripts/security-audit.sh
~/.mac-upkeep/scripts/disk-health.sh
```

## Requirements

- macOS 14+ (Sonoma or later)
- [Homebrew](https://brew.sh) (for `brew-maintenance.sh`)
- No other dependencies

## License

MIT
