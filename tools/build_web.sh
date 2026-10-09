#!/usr/bin/env bash
# Build the Web export into build/web/.
#
# Usage:
#   tools/build_web.sh           # release export (what GitHub Pages ships)
#   tools/build_web.sh --debug   # debug export (keeps dev console/profiler support)
#
# Env:
#   GODOT   Path to the Godot editor binary (default: ~/tools/godot/godot).
#           CI overrides this to point at the downloaded editor binary.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-$HOME/tools/godot/godot}"
PRESET="Web"
EXPORT_DIR="$REPO_ROOT/build/web"
EXPORT_PATH="$EXPORT_DIR/index.html"

MODE="release"
if [[ "${1:-}" == "--debug" ]]; then
	MODE="debug"
fi

if ! command -v "$GODOT" >/dev/null 2>&1 && [[ ! -x "$GODOT" ]]; then
	echo "error: Godot editor binary not found or not executable: $GODOT" >&2
	echo "       set GODOT=/path/to/godot to override" >&2
	exit 1
fi

mkdir -p "$EXPORT_DIR"

# build/ lives inside res:// (it's only kept out of git via .gitignore), so without
# this Godot's filesystem scanner picks up the previous export's output as project
# resources, generates .import sidecars for its PNGs, and then packs those sidecars
# into the *next* export, growing the .pck with leftovers of itself on every rebuild.
touch "$REPO_ROOT/build/.gdignore"

echo "==> Godot: $("$GODOT" --version)"

echo "==> Importing project assets..."
"$GODOT" --headless --path "$REPO_ROOT" --import

echo "==> Exporting Web build ($MODE) to $EXPORT_PATH"
if [[ "$MODE" == "debug" ]]; then
	"$GODOT" --headless --path "$REPO_ROOT" --export-debug "$PRESET" "$EXPORT_PATH"
else
	"$GODOT" --headless --path "$REPO_ROOT" --export-release "$PRESET" "$EXPORT_PATH"
fi

echo "==> Build output:"
ls -la "$EXPORT_DIR"
