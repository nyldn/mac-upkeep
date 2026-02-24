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

## Configuration

All settings live in `~/.mac-upkeep/config`. This file is created on first install and **never overwritten** by updates.

```bash
# Edit your config
open ~/.mac-upkeep/config

# Reset to defaults
cp ~/.mac-upkeep/config.defaults ~/.mac-upkeep/config
```

Key settings you can customize:

| Setting | Default | Purpose |
|---------|---------|---------|
| `DRY_RUN` | `false` | Preview mode — logs what would happen without acting |
| `CACHE_THRESHOLD_KB` | `102400` | Minimum cache size (KB) before cleanup triggers |
| `CACHE_TARGETS` | 17 directories | Which cache directories to clean (add/remove entries) |
| `BREW_AUTO_UPGRADE` | `true` | Auto-upgrade formulae, or just report outdated |
| `BREW_BLOCKLIST` | `()` | Packages to never auto-upgrade |
| `DISK_ALERT_CRITICAL_GB` | `10` | Disk space alert threshold |
| `LOG_MAX_SIZE_KB` | `1024` | Log rotation size threshold |

See `config.defaults` for the full list with documentation.

## Dry-run mode

Preview what any script would do without making changes:

```bash
DRY_RUN=true ~/.mac-upkeep/scripts/cache-cleanup.sh
DRY_RUN=true ~/.mac-upkeep/scripts/brew-maintenance.sh
```

Or set `DRY_RUN=true` in `~/.mac-upkeep/config` to make all scripts preview-only.

## Design principles

- **No sudo.** Everything runs in user context. Nothing requires a password or interactive input.
- **Safe defaults.** Caches are only cleaned when above 100 MB. Trash items must be 30+ days old. Downloads are never touched.
- **Configurable.** Every threshold, target list, and behavior is tunable via `~/.mac-upkeep/config`.
- **Non-destructive updates.** Re-running `install.sh` preserves your config. Modified scripts are backed up before overwriting.
- **Dry-run first.** Every destructive script supports `DRY_RUN=true` to preview operations.
- **No concurrent collisions.** All scripts use lockfiles to prevent overlapping runs.
- **Alerts when it matters.** macOS notifications fire for low disk space, SMART failures, and security drift.
- **Portable.** No hardcoded paths. Scripts resolve `$HOME` at runtime.

## What it cleans

Cache cleanup targets are defined in `CACHE_TARGETS` in your config. Defaults include:

- Browser caches (Chrome, Firefox)
- App updater staging (ShipIt directories)
- Streaming caches (Spotify)
- Dev tool caches (node-gyp, Playwright, Xcode DerivedData, pip, Gradle)
- IDE caches (VS Code, JetBrains)
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

All logs live in `~/.mac-upkeep/logs/`. Append-mode logs auto-rotate at 1 MB (configurable). Weekly reports auto-delete after 12 weeks.

```bash
# Recent cache cleanup activity
tail -20 ~/.mac-upkeep/logs/cache-cleanup.log

# Latest security report
cat ~/.mac-upkeep/logs/security-report-$(date +%Y-%m-%d).txt

# Latest disk health report
cat ~/.mac-upkeep/logs/disk-health-$(date +%Y-%m-%d).txt
```

## Updating

```bash
cd mac-upkeep
git pull
./install.sh
```

Your `~/.mac-upkeep/config` is preserved. Modified scripts are backed up to `~/.mac-upkeep/backup/` before overwriting.

## Requirements

- macOS 14+ (Sonoma or later)
- [Homebrew](https://brew.sh) (optional — installer skips brew agent if not found)
- No other dependencies

## License

MIT
