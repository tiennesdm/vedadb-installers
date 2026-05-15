# VedaDB Installers

> **Installation Scripts & Packages for VedaDB**
> One-command install on any platform.

## Overview

This repository contains official installation scripts and packaging configuration for VedaDB Server and Workbench.

## Quick Install

### Linux (Ubuntu/Debian)
```bash
curl -fsSL https://get.vedadb.io | bash
```

### macOS
```bash
brew tap vedadb/tap
brew install vedadb
```

### Windows
```powershell
# PowerShell (Admin)
iwr -useb https://get.vedadb.io/win | iex
```

### Docker
```bash
docker run -p 8080:8080 vedadb/vedadb:latest
```

### Kubernetes
```bash
kubectl apply -f https://raw.githubusercontent.com/tiennesdm/vedadb-infra/main/k8s/vedadb-deployment.yaml
```

## Manual Installation

```bash
git clone https://github.com/tiennesdm/vedadb-installers.git
cd vedadb-installers

# Ubuntu/Debian
sudo ./install-ubuntu.sh

# CentOS/RHEL
sudo ./install-centos.sh

# macOS
./install-macos.sh

# From source
./install-from-source.sh
```

## Post-Installation

```bash
# Start service
sudo systemctl start vedadb

# Verify
http://localhost:8080/health

# Configure
sudo nano /etc/vedadb/vedadb.conf
sudo systemctl restart vedadb
```

## Uninstall

```bash
sudo ./uninstall.sh
```

## Related Repos

| Repo | Purpose |
|------|---------|
| [vedadb-infra](https://github.com/tiennesdm/vedadb-infra) | Docker, K8s, CI/CD configs |
| [vedadb-server-code](https://github.com/tiennesdm/vedadb-server-code) | Core database engine |
| [vedadb-workbench-desktop](https://github.com/tiennesdm/vedadb-workbench-desktop) | Desktop app |

## License

Apache 2.0
