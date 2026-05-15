# AGENT_MEMORY.md — VedaDB Installers

> **Repository:** `veda-db/vedadb-installers`  
> **Branch:** `main`  
> **Purpose:** Official installation & packaging for VedaDB  
> **Last Updated:** 2025-01-15

---

## Repository Purpose

This repository contains all official VedaDB installation packages, distribution configs, and a configuration generator utility. It produces platform-native installers for macOS, Ubuntu/Debian, and Windows.

---

## Scale & Statistics

| Metric | Value |
|--------|-------|
| Total Files | **17** |
| Platforms | macOS, Ubuntu, Windows |
| Config Generator | Go binary (`config-generator.go`) |

---

## Directory Layout

```
├── macOS/
│   ├── homebrew/
│   │   ├── vedadb.rb                        # Homebrew formula
│   │   └── README.md
│   ├── pkg/
│   │   ├── build.sh                         # PKG package builder
│   │   └── distribution.xml
│   └── launchagent/
│       └── com.vedadb.server.plist          # macOS LaunchAgent
├── ubuntu/
│   ├── deb/
│   │   ├── control                          # DEB package metadata
│   │   ├── postinst                         # Post-install script
│   │   ├── prerm                            # Pre-remove script
│   │   └── build.sh
│   ├── systemd/
│   │   └── vedadb.service                   # systemd unit file
│   └── apt-repo/
│       ├── apt-ftparchive.conf              # APT repository config
│       └── update.sh                        # APT repo update script
├── windows/
│   ├── wix/
│   │   ├── vedadb.wxs                       # WiX MSI source
│   │   └── build.ps1                        # MSI build script
│   └── nsis/
│       ├── vedadb.nsi                       # NSIS installer script
│       └── build.sh
├── config-generator.go                      # Go binary: generates vedadb.yaml
├── Makefile
└── README.md
```

---

## Platform Details

### macOS

| Method | Path | Output |
|--------|------|--------|
| **Homebrew** | `macOS/homebrew/` | `vedadb.rb` formula |
| **PKG Installer** | `macOS/pkg/` | `.pkg` for drag-install |
| **LaunchAgent** | `macOS/launchagent/` | Auto-start on login (`launchctl`) |

```bash
# Install via Homebrew
brew tap veda-db/tap
brew install vedadb

# Or install PKG manually
sudo installer -pkg vedadb-*.pkg -target /
```

### Ubuntu / Debian

| Method | Path | Output |
|--------|------|--------|
| **DEB Package** | `ubuntu/deb/` | `.deb` installable |
| **systemd** | `ubuntu/systemd/` | Service auto-start |
| **APT Repo** | `ubuntu/apt-repo/` | Hosted APT repository |

```bash
# Install via APT
sudo add-apt-repository ppa:vedadb/stable
sudo apt-get install vedadb

# Or install DEB directly
sudo dpkg -i vedadb_*.deb
```

### Windows

| Method | Path | Output |
|--------|------|--------|
| **WiX MSI** | `windows/wix/` | `.msi` Windows Installer |
| **NSIS** | `windows/nsis/` | `.exe` setup wizard |

```powershell
# Install MSI
msiexec /i VedaDB.msi /quiet

# Or run NSIS installer
.\VedaDB-Setup.exe
```

---

## Config Generator

```go
// config-generator.go
// Usage: go run config-generator.go [flags]
// Generates vedadb.yaml from interactive prompts or flags.
//
// Flags:
//   --port         Listen port (default: 7480)
//   --data-dir     Data directory path
//   --engines      Comma-separated engine list
//   --cluster      Enable clustering mode
//   --output       Output file path
```

Build:
```bash
go build -o vedadb-config-gen config-generator.go
```

---

## Build All Packages

```bash
# Build everything
make all VERSION=1.x.x

# Build per platform
make macos VERSION=1.x.x
make ubuntu VERSION=1.x.x
make windows VERSION=1.x.x
```

---

## Files You Should Read First

1. `README.md` — Platform-specific install instructions
2. `config-generator.go` — Config generator source
3. `Makefile` — Build targets
4. `macOS/homebrew/vedadb.rb` — Most-used install path

---

*This file is auto-generated. Update it when new platforms or install methods are added.*
