#!/bin/bash
# =============================================================================
# VedaDB Server - macOS PKG Installer Build Script
# =============================================================================
# Description:
#   Builds a macOS .pkg installer using pkgbuild + productbuild.
#   Creates a component package first, then wraps it in a distribution
#   package with a custom welcome screen and license.
#
# Usage:
#   ./build-pkg.sh [--version VERSION] [--output DIR] [--bin-dir DIR]
#
# Options:
#   --version    Package version (default: reads from git tag or uses 1.0.0)
#   --output     Output directory for .pkg file (default: ./dist)
#   --bin-dir    Directory containing compiled binaries (default: ../../bin)
#
# Dependencies:
#   - macOS 12+ with Xcode Command Line Tools
#   - pkgbuild, productbuild, lipo (included with macOS)
# =============================================================================

set -euo pipefail

# --- Determine script directory ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- Defaults ---
VERSION="${VEDADB_VERSION:-}"
OUTPUT_DIR="$SCRIPT_DIR/dist"
BIN_DIR="$PROJECT_ROOT/bin"
ARCH="universal"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC}   $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error(){ echo -e "${RED}[ERROR]${NC} $1" >&2; }

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="$2"
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
        --help|-h)
            echo "Usage: $0 [--version VERSION] [--output DIR] [--bin-dir DIR]"
            echo ""
            echo "Builds VedaDB Server macOS .pkg installer."
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# --- Auto-detect version from git if not set ---
if [[ -z "$VERSION" ]]; then
    if command -v git &>/dev/null && git -C "$PROJECT_ROOT" describe --tags --abbrev=0 2>/dev/null; then
        VERSION="$(git -C "$PROJECT_ROOT" describe --tags --abbrev=0 | sed 's/^v//')"
    else
        VERSION="1.0.0"
        log_warn "No version specified and no git tags found. Using default: $VERSION"
    fi
fi

log_info "Building VedaDB Server v$VERSION for macOS..."

# --- Validate environment ---
if [[ "$OSTYPE" != "darwin"* ]]; then
    log_error "This script must be run on macOS."
    exit 1
fi

for tool in pkgbuild productbuild; do
    if ! command -v "$tool" &>/dev/null; then
        log_error "Required tool '$tool' not found. Install Xcode Command Line Tools:"
        log_error "  xcode-select --install"
        exit 1
    fi
done

# --- Setup directories ---
BUILD_DIR="$(mktemp -d /tmp/vedadb-pkg-build.XXXXXX)"
trap "rm -rf '$BUILD_DIR'" EXIT

PKG_ROOT="$BUILD_DIR/root"
SCRIPTS_DIR="$BUILD_DIR/scripts"
RESOURCES_DIR="$BUILD_DIR/resources"
COMPONENT_PKG="$BUILD_DIR/vedadb-component.pkg"
DISTRIBUTION_PKG="$OUTPUT_DIR/VedaDB-Server-${VERSION}-macos-${ARCH}.pkg"

mkdir -p "$PKG_ROOT/opt/vedadb/bin"
mkdir -p "$PKG_ROOT/opt/vedadb/share"
mkdir -p "$PKG_ROOT/opt/vedadb/etc"
mkdir -p "$PKG_ROOT/usr/local/bin"
mkdir -p "$SCRIPTS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$OUTPUT_DIR"

log_ok "Build directories created."

# --- Resolve binary paths ---
DARWIN_AMD64_DIR="$BIN_DIR/darwin-amd64"
DARWIN_ARM64_DIR="$BIN_DIR/darwin-arm64"
DARWIN_UNIVERSAL_DIR="$BIN_DIR/darwin-universal"

# Check if universal binaries already exist
USE_UNIVERSAL=false
if [[ -d "$DARWIN_UNIVERSAL_DIR" ]] && \
   [[ -f "$DARWIN_UNIVERSAL_DIR/vedadb-server" ]] && \
   [[ -f "$DARWIN_UNIVERSAL_DIR/vedadb-cli" ]]; then
    USE_UNIVERSAL=true
    log_info "Using existing universal binaries."
fi

# --- Build universal binaries if needed ---
if [[ "$USE_UNIVERSAL" == false ]]; then
    log_info "Building universal binaries..."
    mkdir -p "$DARWIN_UNIVERSAL_DIR"

    # Check for architecture-specific binaries
    if [[ -d "$DARWIN_AMD64_DIR" ]] && [[ -d "$DARWIN_ARM64_DIR" ]]; then
        for binary in vedadb-server vedadb-cli vedadb-bench vedadb-backup; do
            AMD64_BIN="$DARWIN_AMD64_DIR/$binary"
            ARM64_BIN="$DARWIN_ARM64_DIR/$binary"
            UNIVERSAL_BIN="$DARWIN_UNIVERSAL_DIR/$binary"

            if [[ -f "$AMD64_BIN" ]] && [[ -f "$ARM64_BIN" ]]; then
                lipo -create "$AMD64_BIN" "$ARM64_BIN" -output "$UNIVERSAL_BIN"
                chmod +x "$UNIVERSAL_BIN"
                log_ok "  Created universal binary: $binary"
            elif [[ -f "$AMD64_BIN" ]]; then
                cp "$AMD64_BIN" "$UNIVERSAL_BIN"
                chmod +x "$UNIVERSAL_BIN"
                log_warn "  Only AMD64 binary for $binary (ARM64 missing)"
            elif [[ -f "$ARM64_BIN" ]]; then
                cp "$ARM64_BIN" "$UNIVERSAL_BIN"
                chmod +x "$UNIVERSAL_BIN"
                log_warn "  Only ARM64 binary for $binary (AMD64 missing)"
            else
                log_warn "  Binary not found: $binary"
            fi
        done
    elif [[ -d "$DARWIN_AMD64_DIR" ]]; then
        log_warn "Only AMD64 binaries found, copying as-is."
        cp "$DARWIN_AMD64_DIR"/* "$DARWIN_UNIVERSAL_DIR/" 2>/dev/null || true
    elif [[ -d "$DARWIN_ARM64_DIR" ]]; then
        log_warn "Only ARM64 binaries found, copying as-is."
        cp "$DARWIN_ARM64_DIR"/* "$DARWIN_UNIVERSAL_DIR/" 2>/dev/null || true
    else
        log_error "No macOS binaries found in $BIN_DIR."
        log_error "Expected: $DARWIN_AMD64_DIR/ or $DARWIN_ARM64_DIR/ or $DARWIN_UNIVERSAL_DIR/"
        exit 1
    fi
fi

# --- Copy binaries into package root ---
log_info "Copying binaries to package root..."
for binary in vedadb-server vedadb-cli vedadb-bench vedadb-backup; do
    SRC="$DARWIN_UNIVERSAL_DIR/$binary"
    if [[ -f "$SRC" ]]; then
        cp "$SRC" "$PKG_ROOT/opt/vedadb/bin/$binary"
        chmod 755 "$PKG_ROOT/opt/vedadb/bin/$binary"
        log_ok "  $binary"
    else
        log_warn "  $binary not found, skipping"
    fi
done

# --- Copy supporting files ---
log_info "Copying supporting files..."

# License and README
if [[ -f "$PROJECT_ROOT/LICENSE" ]]; then
    cp "$PROJECT_ROOT/LICENSE" "$PKG_ROOT/opt/vedadb/share/LICENSE"
fi
if [[ -f "$PROJECT_ROOT/README.md" ]]; then
    cp "$PROJECT_ROOT/README.md" "$PKG_ROOT/opt/vedadb/share/README.md"
fi

# LaunchAgent plist
if [[ -f "$SCRIPT_DIR/io.vedadb.server.plist" ]]; then
    cp "$SCRIPT_DIR/io.vedadb.server.plist" "$PKG_ROOT/opt/vedadb/share/io.vedadb.server.plist"
fi

# Uninstall script
if [[ -f "$SCRIPT_DIR/uninstall.sh" ]]; then
    cp "$SCRIPT_DIR/uninstall.sh" "$PKG_ROOT/opt/vedadb/uninstall.sh"
    chmod 755 "$PKG_ROOT/opt/vedadb/uninstall.sh"
fi

# Config generator binary
if [[ -f "$DARWIN_UNIVERSAL_DIR/vedadb-config-generator" ]]; then
    cp "$DARWIN_UNIVERSAL_DIR/vedadb-config-generator" "$PKG_ROOT/opt/vedadb/bin/"
    chmod 755 "$PKG_ROOT/opt/vedadb/bin/vedadb-config-generator"
fi

log_ok "Supporting files copied."

# --- Copy scripts ---
log_info "Copying installer scripts..."
if [[ -f "$SCRIPT_DIR/postinstall" ]]; then
    cp "$SCRIPT_DIR/postinstall" "$SCRIPTS_DIR/postinstall"
    chmod 755 "$SCRIPTS_DIR/postinstall"
    log_ok "  postinstall"
else
    log_error "postinstall script not found at $SCRIPT_DIR/postinstall"
    exit 1
fi

# Optional preinstall script
if [[ -f "$SCRIPT_DIR/preinstall" ]]; then
    cp "$SCRIPT_DIR/preinstall" "$SCRIPTS_DIR/preinstall"
    chmod 755 "$SCRIPTS_DIR/preinstall"
    log_ok "  preinstall"
fi

# --- Create distribution XML ---
log_info "Creating distribution descriptor..."
cat > "$BUILD_DIR/distribution.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>VedaDB Server ${VERSION}</title>
    <organization>io.vedadb</organization>
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
    <options customize="never" require-scripts="true" allow-external-scripts="no" rootVolumeOnly="true"/>
    <background file="background.png" alignment="center" scaling="proportional"/>
    <welcome file="welcome.rtf"/>
    <license file="license.rtf"/>
    <conclusion file="conclusion.rtf"/>

    <!-- Installer sections -->
    <pkg-ref id="io.vedadb.server" version="${VERSION}" auth="root">#vedadb-component.pkg</pkg-ref>

    <!-- Choices -->
    <choice id="vedadb" title="VedaDB Server" description="VedaDB multi-model database server" visible="false">
        <pkg-ref id="io.vedadb.server"/>
    </choice>

    <!-- Default choice -->
    <choices-outline>
        <line choice="vedadb"/>
    </choices-outline>
</installer-gui-script>
EOF

# --- Create resource files ---
log_info "Creating installer resources..."

# Welcome text
cat > "$RESOURCES_DIR/welcome.rtf" << 'EOF'
{\rtf1\ansi\ansicpg1252\cocoartf2708
\uc0\pard\tx560\tx1120\tx1680\tx2240\tx2800\tx3360\tx3920\tx4480\tx5040\tx5600\tx6160\tx6720\pardirnatural\qc

\f0\b\fs36 Welcome to VedaDB Server\fs24 \
\pard\tx560\tx1120\tx1680\tx2240\tx2800\tx3360\tx3920\tx4480\tx5040\tx5600\tx6160\tx6720\pardirnatural
\b0 \
VedaDB Server is a high-performance multi-model database supporting document, key-value, graph, and vector data models.\f1\
\
This installer will:\f0\
\f1   - Install VedaDB Server to /opt/vedadb/\
   - Create a dedicated service user and group\
   - Set up data directories in /usr/local/var/vedadb/\
   - Install a LaunchAgent for automatic startup\
   - Create command-line symlinks in /usr/local/bin/\
\
\f0 Click Continue to proceed with the installation.}
EOF

# License (reuse project LICENSE if available)
if [[ -f "$PROJECT_ROOT/LICENSE" ]]; then
    # Convert plain text to RTF
    echo '{\rtf1\ansi\ansicpg1252\cocoartf2708' > "$RESOURCES_DIR/license.rtf"
    echo '\pard\tx560\tx1120\tx1680\tx2240\tx2800\tx3360\tx3920\tx4480\tx5040\tx5600\tx6160\tx6720' >> "$RESOURCES_DIR/license.rtf"
    sed 's/$/\\/' "$PROJECT_ROOT/LICENSE" >> "$RESOURCES_DIR/license.rtf"
    echo '}' >> "$RESOURCES_DIR/license.rtf"
else
    cat > "$RESOURCES_DIR/license.rtf" << 'EOF'
{\rtf1\ansi\ansicpg1252\cocoartf2708
\pard\tx560\tx1120\tx1680\tx2240\tx2800\tx3360\tx3920\tx4480\tx5040\tx5600\tx6160\tx6720
Please refer to https://vedadb.io/license for the full license text.\f0\
}
EOF
fi

# Conclusion text
cat > "$RESOURCES_DIR/conclusion.rtf" << 'EOF'
{\rtf1\ansi\ansicpg1252\cocoartf2708
\pard\tx560\tx1120\tx1680\tx2240\tx2800\tx3360\tx3920\tx4480\tx5040\tx5600\tx6160\tx6720\qc

\f0\b VedaDB Server has been successfully installed!\b0\
\
\pard\tx560\tx1120\tx1680\tx2240\tx2800\tx3360\tx3920\tx4480\tx5040\tx5600\tx6160\tx6720
\
Install directory: /opt/vedadb/\
Data directory: /usr/local/var/vedadb/data/\
Config file: /opt/vedadb/etc/config.yaml\
\
Manage the service:\
   launchctl start io.vedadb.server\
   launchctl stop io.vedadb.server\
   launchctl list io.vedadb.server\
\
CLI tool:\
   vedadb-cli --help\
\
Uninstall:\
   sudo /opt/vedadb/uninstall.sh\
}
EOF

# --- Build component package ---
log_info "Building component package..."
pkgbuild \
    --root "$PKG_ROOT" \
    --scripts "$SCRIPTS_DIR" \
    --identifier "io.vedadb.server" \
    --version "$VERSION" \
    --install-location "/" \
    "$COMPONENT_PKG"

log_ok "Component package built: vedadb-component.pkg"

# --- Build distribution package ---
log_info "Building distribution package..."
productbuild \
    --distribution "$BUILD_DIR/distribution.xml" \
    --package-path "$BUILD_DIR" \
    --resources "$RESOURCES_DIR" \
    "$DISTRIBUTION_PKG"

log_ok "Distribution package built."

# --- Verify ---
log_info "Verifying package..."
if pkgutil --check-signature "$DISTRIBUTION_PKG" 2>/dev/null; then
    log_ok "Package signature verified."
else
    log_warn "Package is unsigned (expected for local builds)."
fi

# Show package info
log_info "Package info:"
pkgutil --pkg-info-package "$DISTRIBUTION_PKG" 2>/dev/null || true

# --- Summary ---
PKG_SIZE="$(du -h "$DISTRIBUTION_PKG" | cut -f1)"

echo ""
echo "==================================="
echo -e "  ${GREEN}Build Complete!${NC}"
echo "==================================="
echo ""
echo "  Package: $DISTRIBUTION_PKG"
echo "  Size:    $PKG_SIZE"
echo "  Version: $VERSION"
echo "  Arch:    $ARCH"
echo ""
echo "  Install:  sudo installer -pkg $DISTRIBUTION_PKG -target /"
echo "  Verify:   pkgutil --pkg-info io.vedadb.server"
echo ""
