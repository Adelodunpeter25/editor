#!/bin/bash
# Build and install the `ed` launcher to a PATH directory.
set -e
cd "$(dirname "$0")/.."

PREFIX="${ED_INSTALL_PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
mkdir -p "$BIN_DIR"

echo "==> swift build ed launcher"
swift build -c release --product ed

echo "==> installing to $BIN_DIR/ed"
cp ".build/release/ed" "$BIN_DIR/ed"
chmod +x "$BIN_DIR/ed"

case ":$PATH:" in
  *":$BIN_DIR:"*) echo "==> $BIN_DIR is already on PATH" ;;
  *) echo "==> add $BIN_DIR to PATH if needed" ;;
esac

echo "==> done"
