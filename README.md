<p align="center">
  <img src="assets/app_icon.png" width="150" alt="Mac Clean Icon" />
</p>

<h1 align="center">Mac Clean</h1>

<p align="center">
  <strong>The open-source Mac cleaner, optimizer, and malware scanner.</strong><br>
  A feature-complete, free alternative to CleanMyMac — built with Swift 6 and SwiftUI.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue?style=flat-square" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/swift-6.0-orange?style=flat-square" alt="Swift 6" />
  <img src="https://img.shields.io/badge/tests-65%20passing-brightgreen?style=flat-square" alt="Tests" />
  <img src="https://img.shields.io/badge/coverage-improving-orange?style=flat-square" alt="Coverage" />
  <img src="https://img.shields.io/badge/license-BSD--3--Clause-green?style=flat-square" alt="License" />
  <img src="https://img.shields.io/badge/security-audited-purple?style=flat-square" alt="Security" />
  <img src="https://img.shields.io/badge/PRs-welcome-ff69b4?style=flat-square" alt="PRs Welcome" />
</p>

<p align="center">
  <img src="assets/demo.png" width="700" alt="Mac Clean Screenshot" />
</p>

<p align="center">
  <strong>Install in one command:</strong>
</p>

```bash
brew tap iliyami/macclean && brew install --cask mac-clean
```

<p align="center">
  Or grab the <a href="https://github.com/iliyami/MacClean/releases/latest">latest DMG</a> from Releases.
</p>

---

## What is Mac Clean?

Mac Clean is a **free, open-source** macOS app that cleans junk files, removes malware, optimizes performance, uninstalls apps completely, and visualizes disk usage — all from a single, beautiful interface. It replicates every major feature of CleanMyMac while being fully transparent and community-driven.

**No subscriptions. No telemetry. No ads. Just a clean Mac.**

## How Mac Clean compares

|  | Mac Clean | CleanMyMac | Pearcleaner | PureMac | OnyX |
|---|:---:|:---:|:---:|:---:|:---:|
| **Price** | Free | $39.95/yr | Free | Free | Free |
| **Open source** | ✅ BSD-3 | ❌ | ✅ Fair-code | ✅ MIT | ❌ |
| **Telemetry** | ❌ None | ⚠️ Yes | ❌ None | ❌ None | ❌ None |
| **Smart Scan (one-click)** | ✅ | ✅ | ❌ | ➖ Partial | ❌ |
| **System Junk (16 categories)** | ✅ | ✅ | ➖ | ✅ | ➖ Limited |
| **Malware scanner** | ✅ | ✅ | ❌ | ❌ | ❌ |
| **Browser privacy cleaner** | ✅ | ✅ | ❌ | ❌ | ➖ |
| **Uninstaller with leftover detection** | ✅ 10-level | ✅ | ✅ Focus | ❌ | ❌ |
| **Disk treemap visualizer** | ✅ | ❌ | ❌ | ❌ | ❌ |
| **Duplicate finder** | ✅ | ✅ | ❌ | ❌ | ❌ |
| **Menu bar system monitor** | ✅ | ✅ Menu | ❌ | ❌ | ❌ |
| **Maintenance scripts** | ✅ | ✅ | ❌ | ❌ | ✅ Strong |
| **Notarized by Apple** | ❌ | ✅ | ✅ | ✅ | ✅ |
| **macOS version** | 14+ | 13+ | 13+ | 13+ | varies |

> CleanMyMac is a great product — they deserve the revenue from users who want a polished, supported experience. Mac Clean is for everyone who'd rather have transparent source code and zero subscription.

## Features

### Cleanup
| Module | Description |
|--------|------------|
| **Smart Scan** | One-click scan combining cleanup, protection, and performance analysis with live progress across 13 modules |
| **System Junk** | 16 scan categories — user/system caches, logs, language files, broken preferences, broken login items, document versions, iOS backups, Xcode junk, universal binaries, deleted users, and more |
| **Mail Attachments** | Find cached attachments from Apple Mail, Outlook, and Spark |
| **Trash Bins** | Empty trash from all locations including external drives |

### Protection
| Module | Description |
|--------|------------|
| **Malware Removal** | Signature-based scanning with 3 depths (Quick / Balanced / Deep), checks launch agents/daemons, browser extensions, and known malware patterns |
| **Privacy** | Clean Safari, Chrome, and Firefox data — history, cookies, cache. System traces cleanup with time filters |

### Performance
| Module | Description |
|--------|------------|
| **Optimization** | Manage login items and launch agents with enable/disable toggles |
| **Maintenance** | 10 system tasks — free RAM, run maintenance scripts, repair permissions, rebuild Launch Services, reindex Spotlight, flush DNS, thin Time Machine snapshots |

### Applications
| Module | Description |
|--------|------------|
| **Uninstaller** | 10-level app matching engine that finds every associated file across 17+ Library subdirectories. Complete removal, app reset, unused app detection |
| **Updater** | Check for available updates across installed apps via Sparkle appcast feeds |

### Files
| Module | Description |
|--------|------------|
| **Space Lens** | Squarified treemap visualization of disk usage with drill-down navigation |
| **Large & Old Files** | Find files >50 MB sorted by size and last access date |
| **Duplicates** | Progressive detection — size grouping → partial SHA-256 (4KB) → full hash → inode verification |
| **Shredder** | Secure file erasure with standard, permanent, and secure overwrite modes |

### Menu Bar Monitor
Independent menu bar app with **real-time system stats**:
- CPU load via `host_processor_info` (Mach API)
- Memory pressure via `vm_statistics64`
- Disk usage and health
- Battery charge, health, cycle count, temperature
- Network throughput via `getifaddrs`

## Architecture

```
Mac Clean
├── MacClean          — Main SwiftUI app (14 modules, 15 views)
├── MacCleanKit       — Shared framework (models, constants, protocols)
├── MacCleanHelper    — XPC privileged helper (LaunchDaemon for root ops)
├── MacCleanMenu      — Menu bar monitor (independent process)
└── MacCleanTestRunner — Standalone test suite (56 tests)
```

### Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 6 with strict concurrency |
| UI | SwiftUI + AppKit hybrid |
| Concurrency | Actors, TaskGroup, async/await, @Sendable |
| Database | GRDB.swift (SQLite) with WAL mode |
| File Scanning | URLResourceKey prefetching on APFS |
| Incremental Updates | FSEvents with historical replay |
| Privileged Ops | SMAppService + NSXPCConnection |
| System Stats | Mach APIs (host_processor_info, vm_statistics64, proc_pidinfo) |

### Safety Model

Mac Clean is designed to **never cause data loss**:

- **Protected paths blocklist** — `/System`, `/usr`, `/bin`, `/sbin`, Apple system apps are untouchable
- **Trash-first deletion** — all removals go to Trash by default
- **Dry-run mode** — preview what would be deleted without touching anything
- **TOCTOU prevention** — symlinks re-resolved immediately before deletion
- **10,000 file cap** — prevents runaway deletion operations
- **Orphan safety policy** — orphan cleanup restricted to caches/logs only
- **Operation logging** — every action logged to `~/Library/Logs/MacClean/`

## Installation

### Homebrew (recommended — one command, no warnings)

```bash
brew tap iliyami/macclean
brew install --cask mac-clean
```

The Cask automatically handles Gatekeeper for you. Launch from Spotlight or Applications — no warnings, no right-clicks, no commands.

### One-line installer

```bash
curl -fsSL https://raw.githubusercontent.com/iliyami/MacClean/main/scripts/install.sh | bash
```

This downloads the latest DMG, installs the app to `/Applications`, and removes the quarantine flag automatically.

### DMG download

Download the latest DMG from [Releases](https://github.com/iliyami/MacClean/releases/latest) and drag Mac Clean to your Applications folder. On first launch, either right-click the app and choose **Open**, or run once:

```bash
sudo xattr -dr com.apple.quarantine "/Applications/Mac Clean.app"
```

### Build from source

```bash
git clone https://github.com/iliyami/MacClean.git
cd MacClean
swift build
swift run MacCleanTestRunner   # run 56 tests
bash scripts/build-dmg.sh      # build local DMG
```

### Granting Full Disk Access

Some modules (Mail Attachments, Privacy, Malware) need Full Disk Access to scan protected areas:

1. Open **System Settings → Privacy & Security → Full Disk Access**
2. Click **+** and add **Mac Clean.app** from Applications
3. Restart Mac Clean

## Why Mac Clean isn't notarized by Apple

Apple charges **$99/year** for a Developer ID — the only way to bypass Gatekeeper warnings on macOS. Mac Clean is free, open-source, and built by volunteers. Paying Apple's annual gatekeeping tax just so users can open the app without a warning isn't worth it when:

1. The source is right here for you to read
2. Homebrew install handles it automatically — `brew install --cask mac-clean` and you're done
3. The one-line installer handles it automatically
4. The whole "Gatekeeper warning" thing is just an extra `xattr` command for direct DMG installs

If our community ever wants to fund a Developer ID (or some other open-source organization wants to sponsor one), we'll happily ship notarized builds. Until then, **no paywall just to launch a free app**.

For maintainers with a Developer ID who want to ship notarized builds:

```bash
export APPLE_DEVELOPER_ID='Developer ID Application: Your Name (TEAMID)'
xcrun notarytool store-credentials 'MacClean' --apple-id YOU@example.com --team-id TEAMID
export NOTARY_PROFILE='MacClean'
bash scripts/build-dmg.sh --notarize
```

## Requirements

- macOS 14 (Sonoma) or later
- For building from source: Swift 6 toolchain (Xcode 16+)

## Project Structure

```
Sources/
├── MacClean/
│   ├── App/                    # App entry point, state, content view
│   ├── Core/
│   │   ├── Scanner/            # FileTreeScanner, TargetedScanner, ScanCoordinator
│   │   ├── Cleaner/            # CleaningEngine, SafetyGuard
│   │   ├── Cache/              # GRDB database layer
│   │   └── FSMonitor/          # FSEvents incremental watcher
│   ├── Modules/                # 13 scan modules
│   │   ├── SystemJunk/         # 16 junk categories
│   │   ├── Malware/            # Signature scanner + real-time monitor
│   │   ├── Uninstaller/        # 10-level app matching engine
│   │   ├── SpaceLens/          # Squarified treemap algorithm
│   │   ├── Duplicates/         # Progressive hash pipeline
│   │   └── ...
│   ├── Views/                  # SwiftUI views (14 module views + shared components)
│   ├── ViewModels/             # @Observable view models
│   ├── Services/               # PermissionManager, XPCClient
│   └── Utilities/              # SuperEllipse shape, extensions
├── MacCleanKit/                # Shared models, constants, protocols
├── MacCleanHelper/             # XPC privileged helper (root operations)
├── MacCleanMenu/               # Menu bar system monitor
└── MacCleanTestRunner/         # 56 standalone tests
```

## Tests

```bash
swift run MacCleanTestRunner
```

```
Results: 65 passed, 0 failed, 65 total
```

**Honest disclosure:** the 65 tests cover roughly **15–20% of the codebase**. Most coverage is on models, constants, the protected-paths blocklist, and the new `PlistJunkFilter`. The most safety-critical files — `SafetyGuard.swift` and `CleaningEngine.swift` — are barely tested today. There are no end-to-end tests.

This is being fixed. See [`docs/TESTING.md`](docs/TESTING.md) for the full plan to reach 85%+ coverage with 100% on safety-critical paths. Progress is tracked in [issues labeled `testing`](https://github.com/iliyami/MacClean/issues?q=is%3Aissue+label%3Atesting). Contributions welcome — each phase has a "good first issue" surface.

## Security

Mac Clean takes security seriously:

- **No network access** — the app never phones home, no telemetry, no analytics
- **No elevated privileges by default** — XPC helper only activated for maintenance tasks
- **Code signature verification** — XPC helper validates caller identity
- **Protected paths** — 27+ Apple system apps and all SIP-protected paths are blocklisted
- **Open source** — every line of code is auditable

### Security Audit Checklist

- [x] No command injection vectors (all Process args are hardcoded constants)
- [x] No arbitrary file deletion (SafetyGuard validates every path)
- [x] TOCTOU race condition prevention (symlink re-resolution before delete)
- [x] File operation caps (10,000 file limit per operation)
- [x] XPC caller validation (code signature check)
- [x] No secrets or credentials in source
- [x] Trash-first policy (recoverable by default)
- [x] Operation audit log (every action recorded)

## Contributing

We welcome contributions! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting a PR.

### Quick Start

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests (`swift run MacCleanTestRunner`)
5. Commit (`git commit -m 'Add amazing feature'`)
6. Push (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## License

This project is licensed under the **BSD 3-Clause License** — see the [LICENSE](LICENSE) file for details.

This means you can use, modify, and redistribute this code, but you **must**:
- Include the original copyright notice
- Include the license text
- **Not** use the name "Mac Clean" or contributors' names to endorse derived products without permission

## Acknowledgments

Inspired by the open-source Mac utility community:
- [Pearcleaner](https://github.com/alienator88/Pearcleaner) — app uninstaller patterns
- [Mole](https://github.com/nicehash/Mole) — cleanup categories
- [Tencent Lemon Cleaner](https://github.com/nicehash/Lemon) — modular architecture
- Squarified Treemap algorithm by Bruls, Huizing & van Wijk (2000)

---

<p align="center">
  <strong>Mac Clean is free software built by the community, for the community.</strong><br>
  If you find it useful, please star the repo and share it with others.
</p>
