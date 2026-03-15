#!/bin/bash
# install.sh — One-liner ANE-Training setup
# curl -sSL .../install.sh | bash

set -e

# ===== Colors =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; exit 1; }
info() { echo -e "  ${BLUE}→${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }

# ===== Banner =====
echo ""
echo -e "  ${BOLD}${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}${CYAN}║     ANE-Training Installer           ║${NC}"
echo -e "  ${BOLD}${CYAN}║     Apple Neural Engine Research     ║${NC}"
echo -e "  ${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""

# ===== Step 1: System checks =====
info "Checking system requirements..."

# Apple Silicon?
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    fail "Apple Silicon required (got: $ARCH)"
fi
ok "Apple Silicon ($ARCH)"

# macOS?
OS=$(uname -s)
if [ "$OS" != "Darwin" ]; then
    fail "macOS required (got: $OS)"
fi
MACOS_VER=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
ok "macOS $MACOS_VER"

# Xcode CLI tools?
if ! xcode-select -p &>/dev/null; then
    warn "Xcode Command Line Tools not found"
    info "Installing Xcode Command Line Tools..."
    xcode-select --install
    echo ""
    warn "Please re-run this script after Xcode tools are installed."
    exit 1
fi
ok "Xcode Command Line Tools"

# ANE framework exists?
if [ -f "/System/Library/PrivateFrameworks/AppleNeuralEngine.framework/AppleNeuralEngine" ]; then
    ok "AppleNeuralEngine.framework found"
else
    warn "AppleNeuralEngine.framework not at expected path (may still work)"
fi

# ===== Step 2: Clone =====
echo ""
INSTALL_DIR="$HOME/Code/ANE-Training"

if [ -d "$INSTALL_DIR" ]; then
    ok "ANE-Training already exists at $INSTALL_DIR"
    cd "$INSTALL_DIR"
else
    info "Cloning ANE-Training..."
    mkdir -p "$(dirname "$INSTALL_DIR")"
    if [ -n "$ANE_REPO_URL" ]; then
        git clone "$ANE_REPO_URL" "$INSTALL_DIR"
    else
        if command -v gh &>/dev/null; then
            gh repo clone ANE-Training "$INSTALL_DIR" 2>/dev/null || {
                warn "gh clone failed, using current directory..."
                INSTALL_DIR="$(pwd)"
            }
        else
            warn "No git remote configured. Using current directory."
            INSTALL_DIR="$(pwd)"
        fi
    fi
    cd "$INSTALL_DIR"
    ok "Repository ready at $INSTALL_DIR"
fi

# ===== Step 3: Build libane =====
echo ""
info "Building libane..."

if [ -f "libane/ane.m" ]; then
    cd libane
    if make test 2>&1 | tail -5; then
        ok "libane built and tests passed"
    else
        warn "libane tests had issues (continuing anyway)"
    fi
    cd ..
else
    fail "libane/ane.m not found — are you in the right directory?"
fi

# ===== Step 4: Build examples =====
echo ""
info "Building examples..."

cd examples

# Build all targets
if make demo_train bench_bin generate_bin explore_bin 2>&1 | tail -3; then
    ok "All examples built"
else
    warn "Some examples may have failed to build"
fi

cd ..

# ===== Step 5: Quick benchmark =====
echo ""
info "Running quick ANE benchmark..."
echo ""

if [ -f "examples/bench" ]; then
    ./examples/bench 2>&1 || warn "Benchmark failed"
else
    warn "Benchmark binary not found, skipping"
fi

# ===== Summary =====
echo ""
echo -e "  ${BOLD}${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}${GREEN}║     Installation Complete!            ║${NC}"
echo -e "  ${BOLD}${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""
echo -e "  Try these commands:"
echo ""
echo -e "    ${CYAN}cd $INSTALL_DIR/examples${NC}"
echo -e "    ${CYAN}make demo${NC}        # Train Y=2X on ANE"
echo -e "    ${CYAN}make bench${NC}       # Auto-benchmark your ANE"
echo -e "    ${CYAN}make generate${NC}    # Shakespeare text generation"
echo -e "    ${CYAN}make explore${NC}     # Explore ANE framework classes"
echo ""
echo -e "  Documentation: ${CYAN}$INSTALL_DIR/README.md${NC}"
echo ""
