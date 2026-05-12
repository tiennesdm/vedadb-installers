#!/bin/bash
# =============================================================================
# VedaDB Server - APT Repository Setup Script
# =============================================================================
# Description:
#   One-line installer script for VedaDB Server on Ubuntu/Debian.
#   This is the script users run with:
#     curl -fsSL https://vedadb.io/install.sh | bash
#
#   It performs the following:
#     1. Detects the OS distribution and version
#     2. Installs required dependencies (curl, gnupg, ca-certificates)
#     3. Downloads and installs the VedaDB GPG signing key
#     4. Adds the VedaDB APT repository
#     5. Updates package lists
#     6. Installs vedadb-server
#
# Supported Distributions:
#   - Ubuntu 20.04 (focal), 22.04 (jammy), 24.04 (noble)
#   - Debian 11 (bullseye), 12 (bookworm)
#
# Usage:
#   curl -fsSL https://vedadb.io/install.sh | bash
#   # or with options:
#   curl -fsSL https://vedadb.io/install.sh | bash -s -- --version 1.0.0
#
# Options (passed via environment or CLI):
#   --version VERSION    Install specific version (default: latest)
#   --dry-run            Show what would be done without doing it
#   --skip-repo-setup    Skip repository setup (only install)
#   --help               Show help message
# =============================================================================

set -euo pipefail

# --- Configuration ---
REPO_URL="https://packages.vedadb.io"
GPG_KEY_URL="${REPO_URL}/gpg"
SUPPORTED_UBUNTU=("focal" "jammy" "noble")
SUPPORTED_DEBIAN=("bullseye" "bookworm")
PKG_NAME="vedadb-server"

# --- Defaults ---
TARGET_VERSION="latest"
DRY_RUN=false
SKIP_REPO_SETUP=false

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}   $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_step()  { echo -e "${BOLD}==>${NC} $1"; }

# --- Header ---
echo ""
echo "============================================"
echo -e "  ${BOLD}VedaDB Server Installer${NC}"
echo "============================================"
echo ""

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            TARGET_VERSION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-repo-setup)
            SKIP_REPO_SETUP=true
            shift
            ;;
        --help|-h)
            echo "VedaDB Server APT Repository Setup"
            echo ""
            echo "Usage:"
            echo "  curl -fsSL https://vedadb.io/install.sh | bash"
            echo "  curl -fsSL https://vedadb.io/install.sh | bash -s -- --version 1.0.0"
            echo ""
            echo "Options:"
            echo "  --version VERSION    Install a specific version (default: latest)"
            echo "  --dry-run            Show what would be done without executing"
            echo "  --skip-repo-setup    Skip repository setup, only install package"
            echo "  --help, -h           Show this help"
            echo ""
            echo "Environment Variables:"
            echo "  VEDADB_VERSION       Same as --version"
            echo "  VEDADB_NO_AUTO_START Set to '1' to prevent auto-starting service"
            echo "  VEDADB_REPO_URL      Override repository URL"
            echo ""
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

# Override from environment if set
[[ -n "${VEDADB_VERSION:-}" ]] && TARGET_VERSION="$VEDADB_VERSION"
[[ -n "${VEDADB_REPO_URL:-}" ]] && REPO_URL="$VEDADB_REPO_URL"
GPG_KEY_URL="${REPO_URL}/gpg"

# --- Dry-run helper ---
run_cmd() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "  [DRY-RUN] Would execute: $*"
    else
        "$@"
    fi
}

# --- Check root privileges ---
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root."
    log_error "Try: curl -fsSL https://vedadb.io/install.sh | sudo bash"
    exit 1
fi

# --- Detect OS ---
log_step "Step 1/6: Detecting operating system..."

if [ -f /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    DISTRO="$ID"
    DISTRO_VERSION="$VERSION_CODENAME"
    DISTRO_PRETTY="$PRETTY_NAME"
else
    log_error "Cannot detect OS. /etc/os-release not found."
    exit 1
fi

log_info "Detected: $DISTRO_PRETTY ($DISTRO_VERSION)"

# Validate supported distribution
SUPPORTED=false
if [ "$DISTRO" == "ubuntu" ]; then
    for v in "${SUPPORTED_UBUNTU[@]}"; do
        if [ "$DISTRO_VERSION" == "$v" ]; then
            SUPPORTED=true
            break
        fi
    done
elif [ "$DISTRO" == "debian" ]; then
    for v in "${SUPPORTED_DEBIAN[@]}"; do
        if [ "$DISTRO_VERSION" == "$v" ]; then
            SUPPORTED=true
            break
        fi
    done
fi

if [ "$SUPPORTED" != true ]; then
    log_warn "Your distribution ($DISTRO_PRETTY) is not officially supported."
    log_warn "Supported: Ubuntu ${SUPPORTED_UBUNTU[*]}, Debian ${SUPPORTED_DEBIAN[*]}"
    log_warn "Attempting to continue anyway..."
fi

# --- Install dependencies ---
log_step "Step 2/6: Installing dependencies..."

MISSING_DEPS=()
for dep in curl gnupg ca-certificates lsb-release; do
    if ! command -v "$dep" &>/dev/null; then
        MISSING_DEPS+=("$dep")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    log_info "Installing: ${MISSING_DEPS[*]}"
    run_cmd apt-get update -qq
    run_cmd apt-get install -y -qq "${MISSING_DEPS[@]}"
else
    log_ok "All dependencies already installed."
fi

# --- Download GPG key ---
if [[ "$SKIP_REPO_SETUP" != true ]]; then
    log_step "Step 3/6: Adding VedaDB GPG signing key..."

    GPG_KEYRING="/usr/share/keyrings/vedadb-archive-keyring.gpg"

    if [ -f "$GPG_KEYRING" ]; then
        log_warn "GPG keyring already exists, overwriting."
    fi

    log_info "Downloading GPG key from $GPG_KEY_URL..."
    if run_cmd bash -c "curl -fsSL '$GPG_KEY_URL' | gpg --dearmor -o '$GPG_KEYRING'"; then
        chmod 644 "$GPG_KEYRING"
        log_ok "GPG key installed."
    else
        log_error "Failed to download GPG key from $GPG_KEY_URL"
        log_error "Please check your network connection."
        exit 1
    fi

    # --- Add APT repository ---
    log_step "Step 4/6: Adding APT repository..."

    REPO_LIST="/etc/apt/sources.list.d/vedadb.list"
    REPO_LINE="deb [signed-by=${GPG_KEYRING}] ${REPO_URL}/deb ${DISTRO_VERSION} main"

    if [ -f "$REPO_LIST" ]; then
        # Backup existing
        cp "$REPO_LIST" "${REPO_LIST}.bak.$(date +%s)"
    fi

    run_cmd bash -c "echo '$REPO_LINE' > '$REPO_LIST'"
    log_ok "APT repository added: $REPO_LIST"

    # --- Update package lists ---
    log_step "Step 5/6: Updating package lists..."
    run_cmd apt-get update -qq
    log_ok "Package lists updated."
else
    log_info "Skipping repository setup (--skip-repo-setup)."
fi

# --- Install VedaDB Server ---
log_step "Step 6/6: Installing VedaDB Server..."

export DEBIAN_FRONTEND=noninteractive

if [ "$TARGET_VERSION" == "latest" ]; then
    log_info "Installing latest version..."
    if run_cmd apt-get install -y -q "$PKG_NAME"; then
        log_ok "VedaDB Server installed successfully."
    else
        log_error "Failed to install $PKG_NAME."
        log_error "Check: apt-cache policy $PKG_NAME"
        exit 1
    fi
else
    log_info "Installing version $TARGET_VERSION..."
    if run_cmd apt-get install -y -q "${PKG_NAME}=${TARGET_VERSION}*"; then
        log_ok "VedaDB Server v${TARGET_VERSION} installed."
    else
        log_error "Failed to install ${PKG_NAME}=${TARGET_VERSION}"
        log_error "Available versions:"
        apt-cache madison "$PKG_NAME" 2>/dev/null || true
        exit 1
    fi
fi

# --- Post-install summary ---
echo ""
echo "============================================"
log_ok "  VedaDB Server Installation Complete!"
echo "============================================"
echo ""

if [[ "$DRY_RUN" != true ]]; then
    echo -e "  ${BOLD}Service status:${NC}"
    systemctl status vedadb --no-pager 2>/dev/null || true
    echo ""
fi

echo -e "  ${BOLD}Quick reference:${NC}"
echo "    Service:     systemctl {start|stop|status} vedadb"
echo "    CLI:         vedadb-cli --help"
echo "    Config:      /etc/vedadb/config.yaml"
echo "    Data:        /var/lib/vedadb"
echo "    Logs:        /var/log/vedadb"
echo "    journald:    journalctl -u vedadb -f"
echo ""
echo -e "  ${BOLD}Uninstall:${NC}"
echo "    apt remove vedadb-server       (keeps data)"
echo "    apt purge vedadb-server        (removes all data)"
echo ""
echo -e "  ${BOLD}Documentation:${NC} https://docs.vedadb.io"
echo ""
