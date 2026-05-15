#!/bin/bash
# =============================================================================
# VedaDB Server - macOS Uninstall Script
# =============================================================================
# Description:
#   Uninstalls VedaDB Server from macOS. Stops and unloads the LaunchAgent,
#   removes symlinks, and optionally cleans up data directories.
#
# Usage:
#   sudo /opt/vedadb/uninstall.sh
#
# Safety:
#   - Prompts before removing data directories
#   - Preserves data by default (only removes application files)
# =============================================================================

set -euo pipefail

# --- Configuration ---
VEDADB_USER="vedadb"
VEDADB_GROUP="vedadb"
INSTALL_DIR="/opt/vedadb"
DATA_DIR="/usr/local/var/vedadb"
LAUNCH_AGENT_LABEL="io.vedadb.server"
SYMLINK_DIR="/usr/local/bin"

# --- Colors for output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Functions ---
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC}   $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# --- Header ---
echo "==================================="
echo "  VedaDB Server Uninstaller"
echo "==================================="
echo ""

# --- Check if running as root ---
if [[ $EUID -ne 0 ]]; then
    log_error "This uninstaller must be run as root. Use: sudo $0"
    exit 1
fi

# --- Detect the real user (the one who ran sudo) ---
REAL_USER="${SUDO_USER:-$USER}"
if [[ "$REAL_USER" == "root" ]]; then
    # Try to find a non-root user
    REAL_USER="$(who | awk '{print $1}' | head -1)"
fi

# --- Stop and unload LaunchAgent ---
log_info "Checking for VedaDB LaunchAgent..."

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
if [[ -n "${SUDO_USER:-}" ]]; then
    REAL_HOME="$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory 2>/dev/null | sed 's/^NFSHomeDirectory: //' || echo "/Users/$SUDO_USER")"
    LAUNCH_AGENTS_DIR="$REAL_HOME/Library/LaunchAgents"
fi

PLIST_PATH="$LAUNCH_AGENTS_DIR/$LAUNCH_AGENT_LABEL.plist"

if launchctl list "$LAUNCH_AGENT_LABEL" &>/dev/null; then
    log_info "Stopping VedaDB Server service..."
    launchctl stop "$LAUNCH_AGENT_LABEL" 2>/dev/null || true
    sleep 1
    log_info "Unloading LaunchAgent..."
    launchctl unload "$PLIST_PATH" 2>/dev/null || launchctl unload -w "$PLIST_PATH" 2>/dev/null || true
    log_ok "LaunchAgent stopped and unloaded."
else
    log_warn "VedaDB LaunchAgent not found (may already be uninstalled)."
fi

# --- Remove LaunchAgent plist ---
if [[ -f "$PLIST_PATH" ]]; then
    log_info "Removing LaunchAgent plist..."
    rm -f "$PLIST_PATH"
    log_ok "LaunchAgent plist removed."
fi

# --- Remove system-wide LaunchDaemon (if installed) ---
if [[ -f "/Library/LaunchDaemons/$LAUNCH_AGENT_LABEL.plist" ]]; then
    log_info "Removing system LaunchDaemon..."
    launchctl unload "/Library/LaunchDaemons/$LAUNCH_AGENT_LABEL.plist" 2>/dev/null || true
    rm -f "/Library/LaunchDaemons/$LAUNCH_AGENT_LABEL.plist"
    log_ok "LaunchDaemon removed."
fi

# --- Remove symlinks ---
log_info "Removing symlinks from $SYMLINK_DIR..."
for binary in vedadb-server vedadb-cli vedadb-bench vedadb-backup; do
    if [[ -L "$SYMLINK_DIR/$binary" ]]; then
        rm -f "$SYMLINK_DIR/$binary"
        log_ok "Removed symlink: $SYMLINK_DIR/$binary"
    fi
done

# --- Ask about data cleanup ---
echo ""
log_warn "Data directory location: $DATA_DIR"
echo ""
echo "Choose data cleanup option:"
echo "  1) Remove all data and configuration"
echo "  2) Keep data, remove configuration only"
echo "  3) Keep all data (remove application files only)"
echo ""
read -rp "Enter choice [1-3] (default: 3): " choice
choice="${choice:-3}"

case "$choice" in
    1)
        log_info "Removing all data and configuration..."
        if [[ -d "$DATA_DIR" ]]; then
            rm -rf "$DATA_DIR"
            log_ok "Data directory removed."
        fi
        if [[ -d "/opt/vedadb/etc" ]]; then
            rm -rf "/opt/vedadb/etc"
            log_ok "Configuration directory removed."
        fi
        ;;
    2)
        log_info "Removing configuration, keeping data..."
        if [[ -d "/opt/vedadb/etc" ]]; then
            rm -rf "/opt/vedadb/etc"
            log_ok "Configuration directory removed."
        fi
        if [[ -f "$DATA_DIR/config.yaml" ]]; then
            rm -f "$DATA_DIR/config.yaml"
        fi
        log_ok "Data preserved at $DATA_DIR."
        ;;
    3)
        log_info "Keeping all data at $DATA_DIR."
        log_warn "You can manually remove this directory later if needed."
        ;;
    *)
        log_warn "Invalid choice. Keeping all data by default."
        ;;
esac

# --- Remove application files ---
log_info "Removing application files from $INSTALL_DIR..."
if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    log_ok "Application files removed."
fi

# --- Remove user and group (optional) ---
echo ""
read -rp "Remove the '$VEDADB_USER' service user and group? [y/N]: " remove_user
if [[ "$remove_user" =~ ^[Yy]$ ]]; then
    if dscl . read "/Users/$VEDADB_USER" &>/dev/null; then
        log_info "Removing user '$VEDADB_USER'..."
        dscl . -delete "/Users/$VEDADB_USER" 2>/dev/null || sysadminctl -deleteUser "$VEDADB_USER" 2>/dev/null || true
        log_ok "User removed."
    fi
    if dscl . read "/Groups/$VEDADB_GROUP" &>/dev/null; then
        log_info "Removing group '$VEDADB_GROUP'..."
        dscl . -delete "/Groups/$VEDADB_GROUP" 2>/dev/null || true
        log_ok "Group removed."
    fi
fi

# --- Summary ---
echo ""
echo "==================================="
echo -e "  ${GREEN}Uninstallation Complete${NC}"
echo "==================================="
echo ""
log_ok "VedaDB Server has been uninstalled successfully."
echo ""
if [[ "$choice" != "1" && -d "$DATA_DIR" ]]; then
    echo "  Data directory preserved: $DATA_DIR"
    echo "  To remove later: sudo rm -rf $DATA_DIR"
fi
echo ""
