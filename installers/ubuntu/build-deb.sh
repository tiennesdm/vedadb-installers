#!/bin/bash
# =============================================================================
# VedaDB Server - Debian/Ubuntu .deb Package Build Script
# =============================================================================
# Description:
#   Builds a .deb package for VedaDB Server using either fpm (preferred)
#   or dpkg-deb (fallback). Includes binaries, systemd service, config,
#   and maintainer scripts.
#
# Usage:
#   ./build-deb.sh [--version VERSION] [--release N] [--arch ARCH]
#                  [--output DIR] [--bin-dir DIR] [--use-fpm|--use-dpkg]
#
# Options:
#   --version    Package version (default: 1.0.0)
#   --release    Package release number (default: 1)
#   --arch       Target architecture: amd64, arm64 (default: amd64)
#   --output     Output directory for .deb file (default: ./dist)
#   --bin-dir    Directory containing compiled binaries
#   --use-fpm    Use fpm for building (default if available)
#   --use-dpkg   Use dpkg-deb for building
#
# Dependencies:
#   - fpm (gem install fpm) OR dpkg-deb (apt install dpkg-dev)
#   - tar, gzip, find
#
# Build Output:
#   dist/vedadb-server_{VERSION}-{RELEASE}_{ARCH}.deb
# =============================================================================

set -euo pipefail

# --- Determine script directory ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- Defaults ---
VERSION="1.0.0"
RELEASE="1"
ARCH="amd64"
OUTPUT_DIR="$SCRIPT_DIR/dist"
BIN_DIR="$PROJECT_ROOT/bin"
BUILD_TOOL="auto"  # auto, fpm, or dpkg

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}   $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --release)
            RELEASE="$2"
            shift 2
            ;;
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --bin-dir)
            BIN_DIR="$2"
            shift 2
            ;;
        --use-fpm)
            BUILD_TOOL="fpm"
            shift
            ;;
        --use-dpkg)
            BUILD_TOOL="dpkg"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Build VedaDB Server .deb package."
            echo ""
            echo "Options:"
            echo "  --version VERSION   Package version (default: 1.0.0)"
            echo "  --release N         Package release number (default: 1)"
            echo "  --arch ARCH         Target architecture: amd64, arm64 (default: amd64)"
            echo "  --output DIR        Output directory (default: ./dist)"
            echo "  --bin-dir DIR       Directory with compiled binaries"
            echo "  --use-fpm           Use fpm for building"
            echo "  --use-dpkg          Use dpkg-deb for building"
            echo "  --help, -h          Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --version 1.2.0 --arch arm64"
            echo "  $0 --version 1.0.0 --use-dpkg --output ./packages"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

# --- Validate architecture ---
case "$ARCH" in
    amd64|arm64) ;;
    *)
        log_error "Unsupported architecture: $ARCH"
        log_error "Supported: amd64, arm64"
        exit 1
        ;;
esac

# --- Validate Go binary path ---
LINUX_BIN_DIR="$BIN_DIR/linux-$ARCH"
if [ ! -d "$LINUX_BIN_DIR" ]; then
    log_error "Binary directory not found: $LINUX_BIN_DIR"
    log_error "Build binaries first with: cd $PROJECT_ROOT && make build-linux-$ARCH"
    exit 1
fi

# Check for required binaries
for binary in vedadb-server vedadb-cli; do
    if [ ! -f "$LINUX_BIN_DIR/$binary" ]; then
        log_error "Required binary not found: $LINUX_BIN_DIR/$binary"
        exit 1
    fi
done

log_info "Building vedadb-server_${VERSION}-${RELEASE}_${ARCH}.deb"
log_info "  Version: $VERSION"
log_info "  Release: $RELEASE"
log_info "  Architecture: $ARCH"
log_info "  Binaries: $LINUX_BIN_DIR"

# --- Select build tool ---
if [ "$BUILD_TOOL" == "auto" ]; then
    if command -v fpm &>/dev/null; then
        BUILD_TOOL="fpm"
        log_info "Auto-selected: fpm"
    elif command -v dpkg-deb &>/dev/null; then
        BUILD_TOOL="dpkg"
        log_info "Auto-selected: dpkg-deb"
    else
        log_error "No build tool found. Install one of:"
        log_error "  gem install fpm    (Ruby)"
        log_error "  apt install dpkg-dev fakeroot"
        exit 1
    fi
fi

# --- Build with fpm ---
build_with_fpm() {
    log_info "Building with fpm..."

    mkdir -p "$OUTPUT_DIR"

    # Build the fpm command
    local fpm_args=(
        -s dir                    # Source type: directory
        -t deb                    # Target type: deb
        -n "vedadb-server"        # Package name
        -v "${VERSION}"           # Version
        --iteration "$RELEASE"    # Release iteration
        -a "$ARCH"                # Architecture
        --license "MIT"
        --vendor "VedaDB Inc."
        --maintainer "VedaDB Team <team@vedadb.io>"
        --url "https://vedadb.io"
        --description "VedaDB - Multi-model database server"
        --category database
        --depends "adduser"
        --depends "libc6 (>= 2.31)"
        --depends "systemd"
        --deb-compression xz
        --deb-priority optional
        --deb-section database
        --deb-field "Homepage: https://vedadb.io"
        --after-install "$SCRIPT_DIR/DEBIAN/postinst"
        --before-remove "$SCRIPT_DIR/DEBIAN/prerm"
        --after-remove "$SCRIPT_DIR/DEBIAN/postrm"
        --config-files /etc/vedadb/config.yaml
        --directories /var/lib/vedadb
        --directories /var/log/vedadb
    )

    # Build a staging directory for fpm
    local STAGE_DIR
    STAGE_DIR="$(mktemp -d /tmp/vedadb-deb-stage.XXXXXX)"
    trap "rm -rf '$STAGE_DIR'" EXIT

    # Create directory structure
    mkdir -p "$STAGE_DIR/opt/vedadb/bin"
    mkdir -p "$STAGE_DIR/opt/vedadb/share"
    mkdir -p "$STAGE_DIR/etc/vedadb"
    mkdir -p "$STAGE_DIR/lib/systemd/system"
    mkdir -p "$STAGE_DIR/usr/bin"
    mkdir -p "$STAGE_DIR/var/lib/vedadb"
    mkdir -p "$STAGE_DIR/var/log/vedadb"

    # Copy binaries
    cp "$LINUX_BIN_DIR/vedadb-server" "$STAGE_DIR/opt/vedadb/bin/"
    cp "$LINUX_BIN_DIR/vedadb-cli" "$STAGE_DIR/opt/vedadb/bin/"
    [ -f "$LINUX_BIN_DIR/vedadb-bench" ] && \
        cp "$LINUX_BIN_DIR/vedadb-bench" "$STAGE_DIR/opt/vedadb/bin/"
    [ -f "$LINUX_BIN_DIR/vedadb-backup" ] && \
        cp "$LINUX_BIN_DIR/vedadb-backup" "$STAGE_DIR/opt/vedadb/bin/"
    [ -f "$LINUX_BIN_DIR/vedadb-config-generator" ] && \
        cp "$LINUX_BIN_DIR/vedadb-config-generator" "$STAGE_DIR/opt/vedadb/bin/"

    # Set binary permissions
    chmod 755 "$STAGE_DIR/opt/vedadb/bin/"*

    # Copy documentation
    [ -f "$PROJECT_ROOT/LICENSE" ] && \
        cp "$PROJECT_ROOT/LICENSE" "$STAGE_DIR/opt/vedadb/share/"
    [ -f "$PROJECT_ROOT/README.md" ] && \
        cp "$PROJECT_ROOT/README.md" "$STAGE_DIR/opt/vedadb/share/"

    # Copy systemd service
    cp "$SCRIPT_DIR/vedadb.service" "$STAGE_DIR/lib/systemd/system/"
    chmod 644 "$STAGE_DIR/lib/systemd/system/vedadb.service"

    # Create symlinks
    ln -sf "/opt/vedadb/bin/vedadb-server" "$STAGE_DIR/usr/bin/vedadb-server"
    ln -sf "/opt/vedadb/bin/vedadb-cli" "$STAGE_DIR/usr/bin/vedadb-cli"
    [ -f "$LINUX_BIN_DIR/vedadb-bench" ] && \
        ln -sf "/opt/vedadb/bin/vedadb-bench" "$STAGE_DIR/usr/bin/vedadb-bench"
    [ -f "$LINUX_BIN_DIR/vedadb-backup" ] && \
        ln -sf "/opt/vedadb/bin/vedadb-backup" "$STAGE_DIR/usr/bin/vedadb-backup"

    # Set ownership for data dirs (will be fixed by postinst, but set defaults)
    chmod 755 "$STAGE_DIR/var/lib/vedadb"
    chmod 755 "$STAGE_DIR/var/log/vedadb"

    # Build the package
    (cd "$STAGE_DIR" && fpm "${fpm_args[@]}" .)

    # Move output
    local PKG_FILE
    PKG_FILE="$(ls "$STAGE_DIR/"*.deb 2>/dev/null | head -1)"
    if [ -n "$PKG_FILE" ]; then
        mv "$PKG_FILE" "$OUTPUT_DIR/"
        log_ok "Package built: $OUTPUT_DIR/$(basename "$PKG_FILE")"
    else
        log_error "fpm did not produce a .deb file"
        exit 1
    fi
}

# --- Build with dpkg-deb ---
build_with_dpkg() {
    log_info "Building with dpkg-deb..."

    # Check for dpkg-deb
    if ! command -v dpkg-deb &>/dev/null; then
        log_error "dpkg-deb not found. Install: apt install dpkg-dev fakeroot"
        exit 1
    fi

    local BUILD_DIR
    BUILD_DIR="$(mktemp -d /tmp/vedadb-deb-build.XXXXXX)"
    trap "rm -rf '$BUILD_DIR'" EXIT

    # Create package structure
    mkdir -p "$BUILD_DIR/DEBIAN"
    mkdir -p "$BUILD_DIR/opt/vedadb/bin"
    mkdir -p "$BUILD_DIR/opt/vedadb/share"
    mkdir -p "$BUILD_DIR/etc/vedadb"
    mkdir -p "$BUILD_DIR/lib/systemd/system"
    mkdir -p "$BUILD_DIR/usr/bin"
    mkdir -p "$BUILD_DIR/var/lib/vedadb"
    mkdir -p "$BUILD_DIR/var/log/vedadb"

    # --- Copy control file ---
    sed -e "s/^Version: .*/Version: ${VERSION}-${RELEASE}/" \
        -e "s/^Architecture: .*/Architecture: ${ARCH}/" \
        "$SCRIPT_DIR/DEBIAN/control" > "$BUILD_DIR/DEBIAN/control"
    log_ok "Control file written."

    # --- Copy maintainer scripts ---
    for script in postinst prerm postrm; do
        if [ -f "$SCRIPT_DIR/DEBIAN/$script" ]; then
            cp "$SCRIPT_DIR/DEBIAN/$script" "$BUILD_DIR/DEBIAN/"
            chmod 755 "$BUILD_DIR/DEBIAN/$script"
            log_ok "$script script copied."
        fi
    done

    # --- Create conffiles ---
    cat > "$BUILD_DIR/DEBIAN/conffiles" << EOF
/etc/vedadb/config.yaml
/lib/systemd/system/vedadb.service
EOF
    chmod 644 "$BUILD_DIR/DEBIAN/conffiles"

    # --- Copy binaries ---
    log_info "Copying binaries..."
    cp "$LINUX_BIN_DIR/vedadb-server" "$BUILD_DIR/opt/vedadb/bin/"
    cp "$LINUX_BIN_DIR/vedadb-cli" "$BUILD_DIR/opt/vedadb/bin/"
    [ -f "$LINUX_BIN_DIR/vedadb-bench" ] && \
        cp "$LINUX_BIN_DIR/vedadb-bench" "$BUILD_DIR/opt/vedadb/bin/"
    [ -f "$LINUX_BIN_DIR/vedadb-backup" ] && \
        cp "$LINUX_BIN_DIR/vedadb-backup" "$BUILD_DIR/opt/vedadb/bin/"
    [ -f "$LINUX_BIN_DIR/vedadb-config-generator" ] && \
        cp "$LINUX_BIN_DIR/vedadb-config-generator" "$BUILD_DIR/opt/vedadb/bin/"
    chmod 755 "$BUILD_DIR/opt/vedadb/bin/"*
    log_ok "Binaries copied."

    # --- Copy documentation ---
    [ -f "$PROJECT_ROOT/LICENSE" ] && \
        cp "$PROJECT_ROOT/LICENSE" "$BUILD_DIR/opt/vedadb/share/"
    [ -f "$PROJECT_ROOT/README.md" ] && \
        cp "$PROJECT_ROOT/README.md" "$BUILD_DIR/opt/vedadb/share/"

    # --- Copy systemd service ---
    cp "$SCRIPT_DIR/vedadb.service" "$BUILD_DIR/lib/systemd/system/vedadb.service"
    chmod 644 "$BUILD_DIR/lib/systemd/system/vedadb.service"

    # --- Create symlinks ---
    ln -sf "/opt/vedadb/bin/vedadb-server" "$BUILD_DIR/usr/bin/vedadb-server"
    ln -sf "/opt/vedadb/bin/vedadb-cli" "$BUILD_DIR/usr/bin/vedadb-cli"
    [ -f "$LINUX_BIN_DIR/vedadb-bench" ] && \
        ln -sf "/opt/vedadb/bin/vedadb-bench" "$BUILD_DIR/usr/bin/vedadb-bench"
    [ -f "$LINUX_BIN_DIR/vedadb-backup" ] && \
        ln -sf "/opt/vedadb/bin/vedadb-backup" "$BUILD_DIR/usr/bin/vedadb-backup"
    log_ok "Symlinks created."

    # --- Build the package ---
    mkdir -p "$OUTPUT_DIR"
    local PKG_NAME="vedadb-server_${VERSION}-${RELEASE}_${ARCH}.deb"

    log_info "Building package (this may take a moment)..."

    # Use fakeroot to set proper ownership in the package
    if command -v fakeroot &>/dev/null; then
        fakeroot dpkg-deb --build "$BUILD_DIR" "$OUTPUT_DIR/$PKG_NAME"
    else
        log_warn "fakeroot not available, building without it."
        dpkg-deb --build "$BUILD_DIR" "$OUTPUT_DIR/$PKG_NAME"
    fi

    log_ok "Package built: $OUTPUT_DIR/$PKG_NAME"
}

# --- Run build ---
case "$BUILD_TOOL" in
    fpm)
        build_with_fpm
        ;;
    dpkg)
        build_with_dpkg
        ;;
    *)
        log_error "Unknown build tool: $BUILD_TOOL"
        exit 1
        ;;
esac

# --- Verify package ---
PKG_FILE="$OUTPUT_DIR/vedadb-server_${VERSION}-${RELEASE}_${ARCH}.deb"
if [ -f "$PKG_FILE" ]; then
    log_info "Verifying package..."
    dpkg-deb -I "$PKG_FILE" 2>/dev/null | head -20 || true

    PKG_SIZE="$(du -h "$PKG_FILE" | cut -f1)"
    echo ""
    echo "==================================="
    echo -e "  ${GREEN}Build Complete!${NC}"
    echo "==================================="
    echo ""
    echo "  Package: $PKG_FILE"
    echo "  Size:    $PKG_SIZE"
    echo "  Version: $VERSION-$RELEASE"
    echo "  Arch:    $ARCH"
    echo ""
    echo "  Install:  sudo dpkg -i $PKG_FILE"
    echo "  Verify:   dpkg-deb -c $PKG_FILE"
    echo ""
else
    log_error "Package file not found at expected location: $PKG_FILE"
    exit 1
fi
