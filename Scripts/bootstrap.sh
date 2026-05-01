#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${ROLLHDR_REPO_URL:-https://github.com/jtc268/rollhdr.git}"
INSTALL_DIR="${ROLLHDR_INSTALL_DIR:-$HOME/.rollhdr-src}"

if [[ -d "$INSTALL_DIR/.git" ]]; then
  git -C "$INSTALL_DIR" pull --ff-only
else
  rm -rf "$INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

"$INSTALL_DIR/Scripts/install.sh"
