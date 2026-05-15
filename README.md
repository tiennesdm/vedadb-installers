# VedaDB Native Installers

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Ubuntu%2FDebian-lightgrey.svg)]()
[![Shell](https://img.shields.io/badge/shell-bash-green.svg)]()
[![WiX](https://img.shields.io/badge/WiX-v4-orange.svg)]()

Production-grade native installers for VedaDB Server on Windows, macOS, and Ubuntu/Debian.

## Supported Platforms

| OS | Format | Tool | One-Line Install |
|----|--------|------|-----------------|
| **Windows** | .msi | WiX Toolset v4 | Download .msi, double-click |
| **macOS** | .pkg + .dmg | pkgbuild + productbuild | `brew install vedadb` |
| **Ubuntu/Debian** | .deb | dpkg-deb + fpm | `curl -fsSL https://vedadb.io/install.sh \| bash` |

## Quick Install

### Windows (.msi Wizard)
```powershell
# 6-step wizard: Welcome -> License -> Directory -> Config -> Install -> Finish
# Auto: Windows Service, firewall rule, PATH, Start Menu
vedadb-server.msi
```

### macOS (PKG or Homebrew)
```bash
# PKG installer
sudo installer -pkg vedadb-macos.pkg -target /

# Or Homebrew
brew tap tiennesdm/vedadb
brew install vedadb
brew services start vedadb
```

### Ubuntu/Debian
```bash
# One-liner
curl -fsSL https://vedadb.io/install.sh | bash

# Or APT
sudo add-apt-repository ppa:vedadb/stable
sudo apt update
sudo apt install vedadb-server
```

## Build

```bash
./build-all.sh --version 1.0.0 --output ./dist
```

## Files

- `windows/vedadb-server.wxs` -- WiX v4 MSI source (6-page wizard)
- `windows/installer.nsi` -- NSIS alternative installer
- `macos/build-pkg.sh` -- macOS PKG build script
- `macos/postinstall` -- Post-install (data dir, LaunchAgent, config)
- `macos/io.vedadb.server.plist` -- LaunchAgent for auto-start
- `macos/uninstall.sh` -- macOS uninstall script
- `macos/vedadb.rb` -- Homebrew formula
- `ubuntu/build-deb.sh` -- Debian package build
- `ubuntu/DEBIAN/` -- control, postinst, prerm, postrm
- `ubuntu/vedadb.service` -- systemd unit (hardened)
- `ubuntu/setup-apt-repo.sh` -- `curl | bash` one-liner
- `config-generator.go` -- OS-aware YAML config generator
- `build-all.sh` -- Master build orchestrator

## License
Apache 2.0
