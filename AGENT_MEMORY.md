# AGENT_MEMORY.md — vedadb-installers

> **Repository:** `vedadb-installers`  
> **Owner:** `tiennesdm`  
> **Branch:** `master`  
> **Visibility:** PRIVATE  
> **Type:** Installation Scripts & Packaging  
> **Total Files:** 17

---

## Overview

This repository contains platform-specific installation scripts, packaging configs, and a Go-based configuration generator for deploying VedaDB across macOS, Ubuntu/Debian, and Windows.

```
┌──────────────────────────────────────────────────────────────┐
│                VedaDB Installation Artifacts                  │
│                      (17 files total)                         │
├─────────────────────┬────────────────────┬───────────────────┤
│      macOS          │   Ubuntu/Debian    │     Windows       │
│  Homebrew + pkg     │   DEB + systemd    │   MSI + NSIS      │
├─────────────────────┴────────────────────┴───────────────────┤
│            config-generator.go (OS-aware config tool)         │
└──────────────────────────────────────────────────────────────┘
```

---

## File Inventory

### macOS (3 files)

| File | Purpose |
|---|---|
| `homebrew/vedadb.rb` | Homebrew formula for `brew install vedadb` |
| `macos-pkg/VedaDB.pkgproj` | macOS `.pkg` installer project config |
| `macos-launchagent/com.vedadb.plist` | LaunchAgent plist for auto-start on boot |

### Ubuntu/Debian (3 files)

| File | Purpose |
|---|---|
| `deb/DEBIAN/control` | DEB package metadata |
| `deb/DEBIAN/postinst` | Post-installation script |
| `systemd/vedadb.service` | systemd service unit file |

### Windows (2 files)

| File | Purpose |
|---|---|
| `wix/VedaDB.wxs` | WiX Toolset MSI installer source |
| `nsis/installer.nsi` | NSIS installer script (alternative to MSI) |

### Shared (2 files)

| File | Purpose |
|---|---|
| `config-generator.go` | Go binary for OS-aware VedaDB config generation |
| `README.md` | Repository documentation |

### CI/Build (7 files)

| File | Purpose |
|---|---|
| `.github/workflows/build.yml` | CI pipeline for building all packages |
| `scripts/build-deb.sh` | DEB package build script |
| `scripts/build-pkg.sh` | macOS pkg build script |
| `scripts/build-msi.sh` | Windows MSI build script |
| `scripts/build-nsis.sh` | NSIS installer build script |
| `scripts/sign-packages.sh` | Code signing script |
| `Makefile` | Orchestrates all build targets |

---

## Platform Details

### macOS Installation

**Homebrew Formula** (`homebrew/vedadb.rb`):
```bash
brew tap vedadb/tap
brew install vedadb
```
- Downloads pre-built binary
- Sets up config directories
- Installs LaunchAgent for auto-start

**PKG Installer** (`macos-pkg/VedaDB.pkgproj`):
- Double-click `.pkg` installer
- Guides through installation wizard
- Installs to `/usr/local/vedadb/`

**LaunchAgent** (`macos-launchagent/com.vedadb.plist`):
- Auto-starts VedaDB on login
- Runs as user process (no root required)
- Logs to `~/Library/Logs/VedaDB/`

### Ubuntu/Debian Installation

**DEB Package** (`deb/`):
```bash
sudo dpkg -i vedadb_<version>_<arch>.deb
# or
sudo apt install ./vedadb_<version>_<arch>.deb
```
- Installs binary to `/usr/bin/vedadb`
- Config to `/etc/vedadb/`
- Data to `/var/lib/vedadb/`
- Logs to `/var/log/vedadb/`

**systemd Service** (`systemd/vedadb.service`):
```bash
sudo systemctl enable vedadb
sudo systemctl start vedadb
sudo systemctl status vedadb
```
- Runs as `vedadb` system user
- Auto-restart on failure
- Structured logging to journald

**APT Repository Setup:**
```bash
curl -s https://apt.vedadb.io/setup.sh | sudo bash
sudo apt update && sudo apt install vedadb
```

### Windows Installation

**MSI Installer** (`wix/VedaDB.wxs`):
- Built with WiX Toolset v4
- Standard Windows installer wizard
- Installs to `C:\Program Files\VedaDB\`
- Registers Windows service

**NSIS Installer** (`nsis/installer.nsi`):
- Alternative lightweight installer
- Built with NSIS (Nullsoft Scriptable Install System)
- Smaller footprint than MSI

---

## Configuration Generator (`config-generator.go`)

A Go binary that generates OS-optimized VedaDB configuration files.

### Features
- Detects OS, CPU cores, RAM, disk type
- Generates optimal `vedadb.conf` settings
- Supports flags for non-interactive mode
- Validates generated configuration

### Usage
```bash
# Interactive mode — asks questions
go run config-generator.go

# Auto-detect everything
go run config-generator.go --auto

# Output to specific file
go run config-generator.go --output /etc/vedadb/vedadb.conf

# Dry run (print to stdout)
go run config-generator.go --dry-run
```

### Generated Config Sections
- `server` — bind address, port, TLS
- `storage` — data directory, engine selection
- `memory` — cache size, buffer pool (auto-detected from RAM)
- `logging` — log level, output destinations
- `cluster` — replication, sharding (if applicable)
- `security` — auth method, TLS certificates

---

## Build System

### Makefile Targets

```bash
# Build everything
make all

# Platform-specific builds
make deb          # Ubuntu/Debian DEB package
make pkg          # macOS .pkg installer
make msi          # Windows MSI installer
make nsis         # Windows NSIS installer
make brew-formula # Validate Homebrew formula

# Utility
make config-gen   # Build config-generator.go binary
make sign         # Sign all packages
make clean        # Clean build artifacts
```

### CI Pipeline

The GitHub Actions workflow (`.github/workflows/build.yml`) builds all packages on tagged releases:
1. Build DEB on Ubuntu runner
2. Build PKG on macOS runner
3. Build MSI on Windows runner
4. Build config-generator for all platforms
5. Sign packages with GPG/codesign
6. Upload to releases page

---

## Directory Structure

```
vedadb-installers/
├── homebrew/
│   └── vedadb.rb                    # Homebrew formula
├── macos-pkg/
│   └── VedaDB.pkgproj               # PKG project file
├── macos-launchagent/
│   └── com.vedadb.plist             # LaunchAgent plist
├── deb/
│   ├── DEBIAN/
│   │   ├── control                  # Package metadata
│   │   └── postinst                 # Post-install script
│   └── ...
├── systemd/
│   └── vedadb.service               # systemd unit file
├── wix/
│   └── VedaDB.wxs                   # WiX MSI source
├── nsis/
│   └── installer.nsi                # NSIS script
├── config-generator.go              # Go config generator
├── scripts/
│   ├── build-deb.sh
│   ├── build-pkg.sh
│   ├── build-msi.sh
│   ├── build-nsis.sh
│   └── sign-packages.sh
├── .github/
│   └── workflows/
│       └── build.yml
├── Makefile
└── README.md
```

---

## Notes for Future Agents

1. **`master` branch is the release branch.** All package configs target production releases.
2. **Version numbers** are updated in: `homebrew/vedadb.rb`, `deb/DEBIAN/control`, `wix/VedaDB.wxs`, and `nsis/installer.nsi`.
3. **Build scripts require platform-specific runners.** DEB needs Ubuntu, PKG needs macOS, MSI needs Windows.
4. **Code signing** is configured in `scripts/sign-packages.sh` — requires certificates in repository secrets.
5. **Adding a new platform:** Create a new top-level directory with packaging configs, add Makefile target, update CI workflow.
6. **`config-generator.go` should stay in sync** with the latest VedaDB configuration schema.
7. **The systemd service** assumes a `vedadb` user exists — the DEB postinst script creates this user.
8. **Homebrew formula** uses GitHub releases as the download source — update the URL and SHA256 on each release.
