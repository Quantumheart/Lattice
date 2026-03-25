#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MANIFEST="$SCRIPT_DIR/io.github.quantumheart.lattice.json"

cd "$PROJECT_DIR"

echo "Building Flutter release..."
flutter build linux --release

echo "Building Flatpak..."
flatpak-builder --user --install --force-clean \
  "$SCRIPT_DIR/.flatpak-builder-build" \
  "$MANIFEST"

echo "Done. Run with: flatpak run io.github.quantumheart.lattice"
