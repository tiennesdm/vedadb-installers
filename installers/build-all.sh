#!/bin/bash
# =============================================================================
# VedaDB Server - Master Build Script
# =============================================================================
# Description:
#   Unified build script that compiles all VedaDB Server native installers:
#   - Windows: .msi (WiX v4) and .exe (NSIS)
#   - macOS:   .pkg (pkgbuild + productbuild)
#   - Linux:   .deb (dpkg-deb or fpm)
#
#   Cross-compiles Go binaries for all platforms, then packages each.
#
# Usage:
#   ./build-all.sh [options]
#
# Options:
#   --version VERSION    Package version (default: git tag or "dev")
#   --output DIR         Output directory for all packages (default: ./dist)
#   --skip-windows       Skip Windows installer build
#   --skip-macos         Skip macOS installer build
#   --skip-linux         Skip Linux package build
#   --skip-binaries      Skip Go binary compilation (use existing)
#   --with-nsis          Also build NSIS installer
#   --clean              Clean output directory before building
#   --parallel           Build platforms in parallel (experimental)
#   --verbose            Enable verbose output
#   --help               Show this help message
#
# Examples:
#   ./build-all.sh --version 1.0.0
#   ./build-all.sh --version 1.0.0 --output ./releases --with-nsis
#   ./build-all.sh --skip-windows --skip-macos  # Linux only
#
# Dependencies:
#   - Go 1.21+ (for cross-compilation)
#   - WiX Toolset v4 (for Windows MSI) - optional
#   - NSIS (for Windows .exe) - optional
#   - pkgbuild/productbuild (for macOS .pkg) - requires macOS
#   - dpkg-deb or fpm (for Linux .deb)
# =============================================================================

set -euo pipefail

# --- Script paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GO_SOURCE="$PROJECT_ROOT/cmd/vedadb-server"

# --- Defaults ---
VERSION="dev"
OUTPUT_DIR="$SCRIPT_DIR/dist"
BUILD_DIR="$SCRIPT_DIR/.build"
SKIP_WINDOWS=false
SKIP_MACOS=false
SKIP_LINUX=false
SKIP_BINARIES=false
WITH_NSIS=false
CLEAN=false
PARALLEL=false
VERBOSE=false

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()   { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()     { echo -e "${GREEN}[OK]${NC}   $1"; }
log_warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()  { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_header() { echo -e "${BOLD}$1${NC}"; }
log_step()   { echo -e "${BOLD}==>${NC} $1"; }

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
        --skip-windows)
            SKIP_WINDOWS=true
            shift
            ;;
        --skip-macos)
            SKIP_MACOS=true
            shift
            ;;
        --skip-linux)
            SKIP_LINUX=true
            shift
            ;;
        --skip-binaries)
            SKIP_BINARIES=true
            shift
            ;;
        --with-nsis)
            WITH_NSIS=true
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        --parallel)
            PARALLEL=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "VedaDB Server - Master Build Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --version VERSION    Package version (default: git tag or 'dev')"
            echo "  --output DIR         Output directory (default: ./dist)"
            echo "  --skip-windows       Skip Windows installer build"
            echo "  --skip-macos         Skip macOS installer build"
            echo "  --skip-linux         Skip Linux package build"
            echo "  --skip-binaries      Use existing binaries (don't recompile)"
            echo "  --with-nsis          Also build NSIS .exe installer"
            echo "  --clean              Clean output before building"
            echo "  --parallel           Build platforms in parallel"
            echo "  --verbose            Enable verbose output"
            echo "  --help, -h           Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 --version 1.0.0"
            echo "  $0 --version 1.0.0 --with-nsis --clean"
            echo "  $0 --skip-macos --skip-windows  # Linux only"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

# --- Auto-detect version ---
if [ "$VERSION" == "dev" ] && command -v git &>/dev/null; then
    GIT_TAG="$(git -C "$PROJECT_ROOT" describe --tags --abbrev=0 2>/dev/null || true)"
    if [ -n "$GIT_TAG" ]; then
        VERSION="${GIT_TAG#v}"  # Remove 'v' prefix
    fi
fi

# Strip 'v' prefix if present
VERSION="${VERSION#v}"

# --- Clean ---
if [ "$CLEAN" == true ]; then
    log_step "Cleaning build directories..."
    rm -rf "$OUTPUT_DIR"
    rm -rf "$BUILD_DIR"
    log_ok "Clean complete."
fi

# --- Setup directories ---
mkdir -p "$OUTPUT_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$BUILD_DIR/bin/linux-amd64"
mkdir -p "$BUILD_DIR/bin/linux-arm64"
mkdir -p "$BUILD_DIR/bin/darwin-amd64"
mkdir -p "$BUILD_DIR/bin/darwin-arm64"
mkdir -p "$BUILD_DIR/bin/windows-amd64"

echo ""
echo "============================================"
echo "  VedaDB Server Build"
echo "  Version: $VERSION"
echo "  Output:  $OUTPUT_DIR"
echo "  Go:      $(go version 2>/dev/null || echo 'not found')"
echo "============================================"
echo ""

# =============================================================================
# STEP 1: Cross-Compile Go Binaries
# =============================================================================
build_binaries() {
    log_step "Step 1: Cross-compiling Go binaries..."

    local ldflags="-s -w -X main.Version=$VERSION"
    local go_version
    go_version="$(go version 2>/dev/null | awk '{print $3}' || echo 'unknown')"

    log_info "Go version: $go_version"
    log_info "Build ldflags: $ldflags"

    # Build each binary for each platform
    local platforms=(
        "linux amd64"
        "linux arm64"
        "darwin amd64"
        "darwin arm64"
        "windows amd64 .exe"
    )

    for plat in "${platforms[@]}"; do
        read -r goos goarch ext <<< "$plat"
        local outdir="$BUILD_DIR/bin/${goos}-${goarch}"
        mkdir -p "$outdir"

        log_info "Building for $goos/$goarch..."

        # Build server
        if ! GOOS="$goos" GOARCH="$goarch" CGO_ENABLED=0 \
             go build -ldflags="$ldflags" \
             -o "$outdir/vedadb-server${ext}" \
             "$PROJECT_ROOT/cmd/vedadb-server" 2>&1; then
            log_warn "Failed to build vedadb-server for $goos/$goarch"
            continue
        fi

        # Build CLI
        if [ -d "$PROJECT_ROOT/cmd/vedadb-cli" ]; then
            GOOS="$goos" GOARCH="$goarch" CGO_ENABLED=0 \
                go build -ldflags="$ldflags" \
                -o "$outdir/vedadb-cli${ext}" \
                "$PROJECT_ROOT/cmd/vedadb-cli" 2>/dev/null || \
                log_warn "vedadb-cli not built for $goos/$goarch"
        fi

        # Build bench
        if [ -d "$PROJECT_ROOT/cmd/vedadb-bench" ]; then
            GOOS="$goos" GOARCH="$goarch" CGO_ENABLED=0 \
                go build -ldflags="$ldflags" \
                -o "$outdir/vedadb-bench${ext}" \
                "$PROJECT_ROOT/cmd/vedadb-bench" 2>/dev/null || true
        fi

        # Build backup
        if [ -d "$PROJECT_ROOT/cmd/vedadb-backup" ]; then
            GOOS="$goos" GOARCH="$goarch" CGO_ENABLED=0 \
                go build -ldflags="$ldflags" \
                -o "$outdir/vedadb-backup${ext}" \
                "$PROJECT_ROOT/cmd/vedadb-backup" 2>/dev/null || true
        fi

        # Build config generator
        GOOS="$goos" GOARCH="$goarch" CGO_ENABLED=0 \
            go build -ldflags="$ldflags" \
            -o "$outdir/vedadb-config-generator${ext}" \
            "$PROJECT_ROOT/installers/config-generator.go" 2>/dev/null || \
            log_warn "config-generator not built for $goos/$goarch"

        log_ok "  $goos/$goarch done"
    done

    log_ok "Cross-compilation complete."
}

# =============================================================================
# STEP 2: Build Windows MSI Installer
# =============================================================================
build_windows() {
    log_step "Step 2: Building Windows MSI installer..."

    # Check for WiX v4
    if ! command -v wix &>/dev/null; then
        log_warn "WiX Toolset v4 not found (wix command missing)."
        log_warn "Install with: dotnet tool install --global wix"
        log_warn "Skipping Windows MSI build."
        return 1
    fi

    # Check for NSIS if requested
    if [ "$WITH_NSIS" == true ] && ! command -v makensis &>/dev/null; then
        log_warn "NSIS not found (makensis command missing)."
        log_warn "Install with: apt install nsis"
        log_warn "Skipping NSIS build."
    fi

    local wxs_file="$SCRIPT_DIR/windows/vedadb-server.wxs"
    local bin_dir="$BUILD_DIR/bin/windows-amd64"

    if [ ! -f "$bin_dir/vedadb-server.exe" ]; then
        log_warn "Windows binaries not found. Skipping MSI build."
        return 1
    fi

    log_info "Building MSI with WiX v4..."

    # Build the MSI
    local msi_name="VedaDB-Setup-${VERSION}-windows-x86_64.msi"
    if wix build -arch x64 \
         -d "Version=$VERSION" \
         -d "BinDir=$bin_dir" \
         -o "$OUTPUT_DIR/$msi_name" \
         "$wxs_file" 2>&1; then
        log_ok "MSI built: $OUTPUT_DIR/$msi_name"
    else
        log_warn "MSI build failed. Check WiX v4 installation."
        return 1
    fi

    # Build NSIS installer if requested
    if [ "$WITH_NSIS" == true ] && command -v makensis &>/dev/null; then
        log_info "Building NSIS installer..."
        local nsi_file="$SCRIPT_DIR/windows/installer.nsi"

        # Update version in NSIS script
        local nsi_build_dir="$BUILD_DIR/nsis"
        mkdir -p "$nsi_build_dir"

        if makensis -DVERSION="$VERSION" \
             -DBINDIR="$bin_dir" \
             -DOUTDIR="$OUTPUT_DIR" \
             "$nsi_file" 2>&1; then
            log_ok "NSIS installer built."
        else
            log_warn "NSIS build failed."
        fi
    fi
}

# =============================================================================
# STEP 3: Build macOS PKG Installer
# =============================================================================
build_macos() {
    log_step "Step 3: Building macOS PKG installer..."

    # macOS packaging must run on macOS
    if [[ "$OSTYPE" != "darwin"* ]]; then
        log_warn "macOS PKG build requires macOS host."
        log_warn "Skipping macOS PKG build."
        return 1
    fi

    # Check for required tools
    for tool in pkgbuild productbuild; do
        if ! command -v "$tool" &>/dev/null; then
            log_warn "$tool not found. Install Xcode Command Line Tools."
            return 1
        fi
    done

    log_info "Building macOS universal package..."

    # Run the macOS build script
    local build_script="$SCRIPT_DIR/macos/build-pkg.sh"
    if [ -x "$build_script" ]; then
        if "$build_script" \
             --version "$VERSION" \
             --output "$OUTPUT_DIR" \
             --bin-dir "$BUILD_DIR/bin"; then
            log_ok "macOS PKG built."
        else
            log_warn "macOS PKG build failed."
            return 1
        fi
    else
        log_error "Build script not found: $build_script"
        return 1
    fi
}

# =============================================================================
# STEP 4: Build Linux DEB Package
# =============================================================================
build_linux() {
    log_step "Step 4: Building Linux DEB packages..."

    # Build AMD64
    log_info "Building AMD64 package..."
    local amd64_script="$SCRIPT_DIR/ubuntu/build-deb.sh"

    if [ -x "$amd64_script" ]; then
        if "$amd64_script" \
             --version "$VERSION" \
             --release 1 \
             --arch amd64 \
             --output "$OUTPUT_DIR" \
             --bin-dir "$BUILD_DIR/bin"; then
            log_ok "AMD64 DEB package built."
        else
            log_warn "AMD64 DEB build failed."
        fi
    else
        log_warn "Build script not found: $amd64_script"
    fi

    # Build ARM64 (if binaries exist)
    if [ -f "$BUILD_DIR/bin/linux-arm64/vedadb-server" ]; then
        log_info "Building ARM64 package..."
        if "$amd64_script" \
             --version "$VERSION" \
             --release 1 \
             --arch arm64 \
             --output "$OUTPUT_DIR" \
             --bin-dir "$BUILD_DIR/bin"; then
            log_ok "ARM64 DEB package built."
        else
            log_warn "ARM64 DEB build failed."
        fi
    else
        log_warn "ARM64 binaries not found, skipping ARM64 package."
    fi
}

# =============================================================================
# STEP 5: Generate Checksums
# =============================================================================
generate_checksums() {
    log_step "Step 5: Generating checksums..."

    local checksum_file="$OUTPUT_DIR/SHA256SUMS"

    cd "$OUTPUT_DIR"

    # Generate SHA256 sums for all packages
    if command -v sha256sum &>/dev/null; then
        sha256sum -- *.msi *.pkg *.deb 2>/dev/null > "$checksum_file" || \
            sha256sum -- *.deb *.msi *.pkg 2>/dev/null > "$checksum_file" || \
            true
    elif command -v shasum &>/dev/null; then
        shasum -a 256 -- *.msi *.pkg *.deb 2>/dev/null > "$checksum_file" || \
            shasum -a 256 -- *.deb *.msi *.pkg 2>/dev/null > "$checksum_file" || \
            true
    fi

    if [ -f "$checksum_file" ]; then
        log_ok "Checksums written to: $checksum_file"
    else
        log_warn "No packages found to checksum."
    fi
}

# =============================================================================
# STEP 6: Build Summary
# =============================================================================
build_summary() {
    log_step "Build Summary"
    echo ""

    local pkg_count=0
    local total_size=0

    echo -e "  ${BOLD}Packages:${NC}"
    echo ""

    for f in "$OUTPUT_DIR"/*.{msi,pkg,deb,exe} 2>/dev/null; do
        [ -f "$f" ] || continue
        local name
        name="$(basename "$f")"
        local size
        size="$(du -h "$f" | cut -f1)"
        echo -e "    ${GREEN}✓${NC} $name ($size)"
        pkg_count=$((pkg_count + 1))
        total_size=$((total_size + $(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)))
    done

    echo ""

    if [ "$pkg_count" -eq 0 ]; then
        log_warn "No packages were built."
        return
    fi

    log_ok "Total packages: $pkg_count"

    # Human-readable total size
    if command -v numfmt &>/dev/null; then
        log_ok "Total size: $(echo "$total_size" | numfmt --to=iec-i --suffix=B)"
    fi

    echo ""
    echo "  Output directory: $OUTPUT_DIR"
    echo ""
}

# =============================================================================
# Main Execution
# =============================================================================

# Set verbose mode
if [ "$VERBOSE" == true ]; then
    set -x
fi

# Step 1: Build binaries
if [ "$SKIP_BINARIES" == false ]; then
    if command -v go &>/dev/null; then
        build_binaries
    else
        log_warn "Go not found. Using existing binaries."
    fi
fi

# Steps 2-4: Build installers
if [ "$PARALLEL" == true ]; then
    # Run platform builds in parallel (background jobs)
    [ "$SKIP_WINDOWS" == false ] && build_windows &
    [ "$SKIP_MACOS" == false ] && build_macos &
    [ "$SKIP_LINUX" == false ] && build_linux &
    wait
else
    # Run sequentially
    [ "$SKIP_WINDOWS" == false ] && build_windows || true
    [ "$SKIP_MACOS" == false ] && build_macos || true
    [ "$SKIP_LINUX" == false ] && build_linux || true
fi

# Step 5: Generate checksums
generate_checksums

# Step 6: Summary
build_summary

echo ""
echo "============================================"
log_ok "  Build process complete!"
echo "============================================"
echo ""
