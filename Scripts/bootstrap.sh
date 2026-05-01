#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${GLOWGOBLIN_REPO_URL:-https://github.com/jtc268/glowgoblin.git}"
INSTALL_DIR="${GLOWGOBLIN_INSTALL_DIR:-$HOME/.glowgoblin-src}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "GlowGoblin needs '$1' to install from source." >&2
    echo "Install Apple's Xcode Command Line Tools, then run this again:" >&2
    echo "  xcode-select --install" >&2
    exit 1
  fi
}

require_command git
require_command swift

echo "GlowGoblin: fetching source..."
if [[ -d "$INSTALL_DIR/.git" ]]; then
  git -C "$INSTALL_DIR" pull --ff-only
else
  rm -rf "$INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

echo "GlowGoblin: building and installing..."
"$INSTALL_DIR/Scripts/install.sh"
