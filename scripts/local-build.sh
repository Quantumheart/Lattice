#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "[Lattice] Running local build pipeline..."

echo "[Lattice] Installing dependencies..."
flutter pub get

echo "[Lattice] Running analysis..."
flutter analyze

echo "[Lattice] Generating mocks..."
dart run build_runner build --delete-conflicting-outputs

echo "[Lattice] Running tests..."
flutter test

if [[ "${1:-}" == "--release" ]]; then
  echo "[Lattice] Building Linux release..."
  flutter build linux --release
  echo "[Lattice] Release build at: build/linux/x64/release/bundle/"
else
  echo "[Lattice] Skipping release build (pass --release to include it)"
fi

echo "[Lattice] Done."
