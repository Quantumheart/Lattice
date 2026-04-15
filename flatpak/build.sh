#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MANIFEST="$SCRIPT_DIR/io.github.quantumheart.kohera.json"

cd "$PROJECT_DIR"

if ! command -v flatpak-builder &>/dev/null; then
  echo "Error: flatpak-builder not found. Install it with: sudo dnf install flatpak-builder"
  exit 1
fi

echo "Building Flutter release..."
flutter build linux --release

echo "Building Flatpak..."
flatpak-builder --user --install --force-clean \
  "$SCRIPT_DIR/.flatpak-builder-build" \
  "$MANIFEST"

echo "Done. Run with: flatpak run io.github.quantumheart.kohera"
